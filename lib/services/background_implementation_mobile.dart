import 'dart:async';
import 'dart:math';
import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:workmanager/workmanager.dart';
import 'package:mediapipe_genai/mediapipe_genai.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
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
      final response = await _generateBackgroundThought(
        ghostName: ghostName,
        userName: userName,
        geminiKey: geminiKey,
        groqKey: groqKey,
        cfKey: cfKey,
        cfAccount: cfAccount,
      );

      // 2. Grava na memória persistente (Contexto da Conversa)
      final List<dynamic> currentHistory = settingsBox.get('activeSessionHistory', defaultValue: []);
      currentHistory.add({"role": "assistant", "content": response});
      
      // Mantém coerência de tamanho
      if (currentHistory.length > 10) currentHistory.removeRange(0, 2);
      await settingsBox.put('activeSessionHistory', currentHistory);

      await _showNotification(ghostName, response);
    } catch (e) {
      print("Erro background mobile: $e");
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
}) async {
  bool isValid(String text) => text.trim().split(' ').length >= 3;
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

  // 1. TENTA IA LOCAL (Gemma)
  try {
    final directory = await getExternalStorageDirectory();
    final modelPath = p.join(directory!.path, 'gemma3.bin');

    if (await File(modelPath).exists()) {
      final engine = LlmInferenceEngine(LlmInferenceOptions.gpu(
        modelPath: modelPath,
        maxTokens: 128,
        temperature: 1.0,
        topK: 40,
        sequenceBatchSize: 128,
      ));
      final responseStream = engine.generateResponse("Você é $ghostName. $selectedStyle Para o usuário $userName.");
      final fullResponse = await responseStream.join();
      engine.dispose();
      final result = fullResponse.trim();
      if (isValid(result)) {
        print("Background: Sucesso via IA LOCAL");
        return result;
      }
    }
  } catch (e) { print("Falha IA Local Background: $e"); }

  final systemPrompt = "Identidade: Você é o criptofantasma $ghostName. "
      "O usuário $userName não fala com você há algum tempo. "
      "Sua tarefa: $selectedStyle "
      "Regras: Use entre 10 e 25 palavras. Seja completo e coerente com sua identidade autônoma.";

  // 2. TENTA GEMINI
  if (geminiKey.isNotEmpty) {
    try {
      final url = "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.6-flash:generateContent?key=$geminiKey";
      final resp = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          "contents": [{"parts": [{"text": systemPrompt}]}],
          "generationConfig": {"temperature": 1.0, "maxOutputTokens": 150}
        }),
      ).timeout(const Duration(seconds: 20));

      if (resp.statusCode == 200) {
        final data = jsonDecode(utf8.decode(resp.bodyBytes));
        final result = data['candidates'][0]['content']['parts'][0]['text'].toString().trim();
        if (isValid(result)) {
          print("Background: Sucesso via GEMINI");
          return result;
        }
      }
    } catch (e) { print("Gemini Background Fail: $e"); }
  }

  // 3. TENTA GROQ
  if (groqKey.isNotEmpty) {
    try {
      final resp = await http.post(
        Uri.parse("https://api.groq.com/openai/v1/chat/completions"),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $groqKey'
        },
        body: jsonEncode({
          "model": "openai/gpt-oss-120b",
          "messages": [{"role": "system", "content": systemPrompt}],
          "temperature": 1.0,
          "max_tokens": 150
        }),
      ).timeout(const Duration(seconds: 20));

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        final result = data['choices'][0]['message']['content'].toString().trim();
        if (isValid(result)) {
          print("Background: Sucesso via GROQ");
          return result;
        }
      }
    } catch (e) { print("Groq Background Fail: $e"); }
  }

  // 4. TENTA CLOUDFLARE
  if (cfKey.isNotEmpty && cfAccount.isNotEmpty) {
    try {
      final url = "https://api.cloudflare.com/client/v4/accounts/$cfAccount/ai/run/@cf/meta/llama-3.1-8b-instruct";
      final resp = await http.post(
        Uri.parse(url),
        headers: {'Authorization': 'Bearer $cfKey'},
        body: jsonEncode({
          "messages": [{"role": "system", "content": systemPrompt}]
        }),
      ).timeout(const Duration(seconds: 20));

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        final result = data['result']['response'].toString().trim();
        if (isValid(result)) {
          print("Background: Sucesso via CLOUDFLARE");
          return result;
        }
      }
    } catch (e) { print("Cloudflare Background Fail: $e"); }
  }

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
