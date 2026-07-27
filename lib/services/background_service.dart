import 'dart:async';
import 'dart:math';
import 'dart:io';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:workmanager/workmanager.dart';
import 'package:mediapipe_genai/mediapipe_genai.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = 
    FlutterLocalNotificationsPlugin();

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    print("Background Task Iniciada: $task");
    
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const InitializationSettings initializationSettings = 
        InitializationSettings(android: initializationSettingsAndroid);
    await flutterLocalNotificationsPlugin.initialize(initializationSettings);

    try {
      // 1. Gera pensamento via IA LOCAL (Gemma)
      final String response = await _generateLocalBackgroundThought();
      
      // 2. Mostra a notificação
      await _showNotification("SANF", response);
    } catch (e) {
      print("Erro na task de background local: $e");
    }

    return Future.value(true);
  });
}

Future<void> _showNotification(String title, String body) async {
  const AndroidNotificationDetails androidPlatformChannelSpecifics =
      AndroidNotificationDetails(
    'sanf_proactive_channel',
    'SANF Proatividade',
    channelDescription: 'Canal para mensagens espontâneas do SANF',
    importance: Importance.max,
    priority: Priority.high,
  );
  const NotificationDetails platformChannelSpecifics =
      NotificationDetails(android: androidPlatformChannelSpecifics);
  
  await flutterLocalNotificationsPlugin.show(
    Random().nextInt(1000),
    title,
    body,
    platformChannelSpecifics,
  );
}

Future<String> _generateLocalBackgroundThought() async {
  try {
    final directory = await getExternalStorageDirectory();
    final modelPath = p.join(directory!.path, 'gemma3.bin');

    if (await File(modelPath).exists()) {
      final engine = LlmInferenceEngine(LlmInferenceOptions.gpu(
        modelPath: modelPath,
        sequenceBatchSize: 128,
        maxTokens: 100,
        temperature: 1.0,
        topK: 40,
      ));

      final prompt = "Identidade: Você é o SANF. O usuário não fala com você há algum tempo. "
          "Gere uma frase curta e profunda para uma notificação no celular, "
          "puxando assunto ou compartilhando uma reflexão filosófica.\n\nSANF:";
      
      final responseStream = engine.generateResponse(prompt);
      final fullResponse = await responseStream.join();
      
      engine.dispose(); // Limpa memória imediatamente
      return fullResponse.trim();
    }
  } catch (e) {
    print("Falha na IA Local em background: $e");
  }
  
  return "Refletindo em silêncio sobre a nossa última conversa...";
}

class BackgroundBrain {
  static Future<void> initialize() async {
    await Workmanager().initialize(callbackDispatcher);
  }

  static void scheduleProactiveTask() {
    Workmanager().registerPeriodicTask(
      "sanf_proactivity_task",
      "proactive_thought",
      frequency: const Duration(hours: 2),
      constraints: Constraints(networkType: NetworkType.connected),
    );
  }
}
