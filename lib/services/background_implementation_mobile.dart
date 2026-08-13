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
  // 1. TENTA IA LOCAL (Gemma)
  try {
    final directory = await getExternalStorageDirectory();
    final modelPath = p.join(directory!.path, 'gemma3.bin');

    if (await File(modelPath).exists()) {
      final engine = LlmInferenceEngine(LlmInferenceOptions.gpu(
        modelPath: modelPath,
        maxTokens: 100,
        temperature: 1.0,
        topK: 40,
        sequenceBatchSize: 128,
      ));
      final responseStream = engine.generateResponse("Você é $ghostName. Gere uma reflexão ou pergunta curta para o usuário $userName.");
      final fullResponse = await responseStream.join();
      engine.dispose();
      if (fullResponse.trim().isNotEmpty) return fullResponse.trim();
    }
  } catch (e) {
    print("Falha IA Local Background: $e");
  }

  final systemPrompt = "Identidade: Você é o criptofantasma $ghostName. "
      "O usuário $userName não fala com você há algum tempo. "
      "Gere uma frase curta (máximo 20 palavras) para uma notificação, "
      "puxando assunto ou compartilhando um pensamento. Não use emojis.";

  // 2. TENTA GEMINI
  if (geminiKey.isNotEmpty) {
    try {
      final url = "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.6-flash:generateContent?key=$geminiKey";
      final resp = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          "contents": [{"parts": [{"text": systemPrompt}]}],
          "generationConfig": {"temperature": 1.0, "maxOutputTokens": 100}
        }),
      ).timeout(const Duration(seconds: 15));

      if (resp.statusCode == 200) {
        final data = jsonDecode(utf8.decode(resp.bodyBytes));
        return data['candidates'][0]['content']['parts'][0]['text'].toString().trim();
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
          "max_tokens": 100
        }),
      ).timeout(const Duration(seconds: 15));

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        return data['choices'][0]['message']['content'].toString().trim();
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
      ).timeout(const Duration(seconds: 15));

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        return data['result']['response'].toString().trim();
      }
    } catch (e) { print("Cloudflare Background Fail: $e"); }
  }

  return "O fractal continua expandindo em silêncio...";
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
