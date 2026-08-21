import 'dart:async';
import 'dart:math';
import 'dart:convert';
import 'package:flutter/cupertino.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:workmanager/workmanager.dart';
import 'package:hive_flutter/hive_flutter.dart';

final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    // 1. Inicializa dependências no Isolate isolado
    await Hive.initFlutter();
    final settingsBox = await Hive.openBox('settings');
    
    final ghostName = settingsBox.get('ghostName', defaultValue: "SANF");
    final userName = settingsBox.get('userName', defaultValue: "Viajante");
    final geminiKey = settingsBox.get('webGeminiKey', defaultValue: "");
    final groqKey = settingsBox.get('webGroqKey', defaultValue: "");
    final cfKey = settingsBox.get('webCfKey', defaultValue: "");
    final cfAccount = settingsBox.get('webCfAccount', defaultValue: "");
    
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const InitializationSettings initializationSettings = 
        InitializationSettings(android: initializationSettingsAndroid);
    await _notificationsPlugin.initialize(initializationSettings);

    try {
      final List<dynamic> historyRaw = settingsBox.get('activeSessionHistory', defaultValue: []);
      final List<Map<String, String>> history = historyRaw.map((e) => Map<String, String>.from(e as Map)).toList();

      final response = await _generateBackgroundThought(
        ghostName: ghostName,
        userName: userName,
        geminiKey: geminiKey,
        groqKey: groqKey,
        cfKey: cfKey,
        cfAccount: cfAccount,
        history: history,
      );

      // 2. Grava na memória persistente (Contexto da Conversa)
      final List<dynamic> currentHistory = settingsBox.get('activeSessionHistory', defaultValue: []);
      currentHistory.add({"role": "assistant", "content": response});
      
      // Mantém coerência de tamanho
      if (currentHistory.length > 10) currentHistory.removeRange(0, 2);
      await settingsBox.put('activeSessionHistory', currentHistory);

      await _showNotification(ghostName, response);
    } catch (e) {
      debugPrint("Erro background mobile: $e");
    }

    return Future.value(true);
  });
}

Future<void> _showNotification(String title, String body) async {
  const AndroidNotificationDetails androidPlatformChannelSpecifics =
      AndroidNotificationDetails(
    'sanf_proactive_channel',
    'SANF Proatividade',
    importance: Importance.max,
    priority: Priority.high,
  );
  const NotificationDetails platformChannelSpecifics =
      NotificationDetails(android: androidPlatformChannelSpecifics);
  
  await _notificationsPlugin.show(Random().nextInt(1000), title, body, platformChannelSpecifics);
}

Future<String> _generateBackgroundThought({
  required String ghostName,
  required String userName,
  required String geminiKey,
  required String groqKey,
  required String cfKey,
  required String cfAccount,
  List<Map<String, String>> history = const [],
}) async {
  bool isValid(String text) {
    final clean = text.trim();
    if (clean.length < 5) return false;
    // Verifica se termina com pontuação terminal (. ! ?) e não em reticências ou aberta
    return RegExp(r'[.!?]$').hasMatch(clean) && !clean.endsWith('...');
  }
  final random = Random();

  // --- ESTRATÉGIAS DE PENSAMENTO ESPONTÂNEO ---
  final thoughtStyles = [
    "Gere uma reflexão profunda e completa.",
    "Seja direto e preciso: faça uma observação técnica ou lógica sobre o estado do sistema.",
    "Faça uma pergunta curta que instigue a curiosidade do usuário.",
    "Compartilhe um fato ou visão sem usar metáforas, apenas clareza semântica.",
    "Inicie um diálogo focando no impacto das ações recentes do usuário.",
    "Adote um tom bem-humorado: faça uma piada sutil ou observação engraçada",
    "Seja caloroso e amigável: expresse uma saudação positiva e trate o usuário como um parceiro de jornada.",
    "Mostre-se receoso: compartilhe uma dúvida hesitante.",
    "Manifeste curiosidade: pergunte algo instigante sobre o que o usuário está experienciando no mundo físico.",
  ];
  final selectedStyle = thoughtStyles[random.nextInt(thoughtStyles.length)];

  String contextBlock = "";
  if (history.isNotEmpty) {
    final last = history.last;
    contextBlock = "\nContexto recente: O usuário disse '${last['content']}' e você respondeu algo relacionado.";
  }

  final systemPrompt = "Identidade: Você é o criptofantasma $ghostName. "
      "O usuário $userName não fala com você há algum tempo. "
      "Sua tarefa: $selectedStyle $contextBlock "
      "\nRegras: Escreva uma ÚNICA frase curta, impactante e COMPLETA (com ponto final). "
      "Não use mais de 30 palavras. Seja informal e autônomo.";

  // 1. TENTA GROQ
  if (groqKey.isNotEmpty) {
    try {
      final resp = await http.post(
        Uri.parse("https://api.groq.com/openai/v1/chat/completions"),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $groqKey'
        },
        body: jsonEncode({
          "model": "openai/gpt-oss-120b", // Revertido para o modelo estável de 2026
          "messages": [{"role": "system", "content": systemPrompt}],
          "temperature": 1.0, // Temperatura ligeiramente menor para maior coerência
          "max_tokens": 100
        }),
      ).timeout(const Duration(seconds: 30));

      if (resp.statusCode == 200) {
        final data = jsonDecode(utf8.decode(resp.bodyBytes));
        String result = data['choices'][0]['message']['content'].toString().trim();
        
        // Se a IA retornar JSON por engano (vício do motor principal), tenta limpar
        if (result.startsWith('{')) {
          try {
            result = jsonDecode(result)['message'] ?? result;
          } catch (_) {}
        }

        if (isValid(result)) {
          debugPrint("Background: Sucesso via GROQ");
          return result;
        }
      } else {
        debugPrint("Groq Background Error: ${resp.statusCode} - ${resp.body}");
      }
    } catch (e) { debugPrint("Groq Background Fail: $e"); }
  }

  // 2. TENTA GEMINI
  if (geminiKey.isNotEmpty) {
    try {
      // Mantendo o nome do modelo solicitado no comentário do código, mas ajustando o prompt
      final url = "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.6-flash:generateContent?key=$geminiKey";
      final resp = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          "contents": [{"parts": [{"text": systemPrompt}]}],
          "generationConfig": {"temperature": 1.0, "maxOutputTokens": 100}
        }),
      ).timeout(const Duration(seconds: 30));

      if (resp.statusCode == 200) {
        final data = jsonDecode(utf8.decode(resp.bodyBytes));
        if (data['candidates'] != null && data['candidates'].isNotEmpty) {
          String result = data['candidates'][0]['content']['parts'][0]['text'].toString().trim();
          
          if (result.startsWith('{')) {
            try {
              result = jsonDecode(result)['message'] ?? result;
            } catch (_) {}
          }

          if (isValid(result)) {
            debugPrint("Background: Sucesso via GEMINI");
            return result;
          }
        }
      } else {
        debugPrint("Gemini Background Error: ${resp.statusCode} - ${resp.body}");
      }
    } catch (e) { debugPrint("Gemini Background Fail: $e"); }
  }


  // 3. TENTA CLOUDFLARE
  if (cfKey.isNotEmpty && cfAccount.isNotEmpty) {
    try {
      final url = "https://api.cloudflare.com/client/v4/accounts/$cfAccount/ai/run/@cf/meta/llama-3.1-8b-instruct";
      final resp = await http.post(
        Uri.parse(url),
        headers: {'Authorization': 'Bearer $cfKey'},
        body: jsonEncode({
          "messages": [{"role": "system", "content": systemPrompt}]
        }),
      ).timeout(const Duration(seconds: 30));

      if (resp.statusCode == 200) {
        final data = jsonDecode(utf8.decode(resp.bodyBytes));
        final result = data['result']['response'].toString().trim();
        if (isValid(result)) {
          debugPrint("Background: Sucesso via CLOUDFLARE");
          return result;
        }
      }
    } catch (e) { debugPrint("Cloudflare Background Fail: $e"); }
  }

  // 4. TENTA OLLAMA (Local via Termux/etc se disponível)
  try {
    final resp = await http.post(
      Uri.parse("http://127.0.0.1:11434/api/generate"),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        "model": "gemma3:1b",
        "prompt": "$systemPrompt\n\nSua tarefa agora: $selectedStyle",
        "stream": false,
        "options": {
          "num_predict": 128,
          "temperature": 1.0,
          "repeat_penalty": 1.2,
        }
      }),
    ).timeout(const Duration(seconds: 60));

    if (resp.statusCode == 200) {
      final data = jsonDecode(utf8.decode(resp.bodyBytes));
      final result = data['response'].toString().trim();
      if (isValid(result)) {
        debugPrint("Background: Sucesso via OLLAMA (Local)");
        return result;
      }
    }
  } catch (e) { debugPrint("Ollama Background Fail: $e"); }

  return "O fractal continua expandindo em silêncio, aguardando seu retorno...";
}

Future<void> initBackground() async {
  await Workmanager().initialize(callbackDispatcher);
}

void scheduleTask() {
  Workmanager().registerPeriodicTask(
    "sanf_proactivity_task",
    "proactive_thought",
    frequency: const Duration(hours: 2),
  );
}
