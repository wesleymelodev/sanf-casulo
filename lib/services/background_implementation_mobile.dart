import 'dart:async';
import 'dart:math';
import 'dart:io';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:workmanager/workmanager.dart';
import 'package:mediapipe_genai/mediapipe_genai.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const InitializationSettings initializationSettings = 
        InitializationSettings(android: initializationSettingsAndroid);
    await _notificationsPlugin.initialize(initializationSettings);

    try {
      final response = await _generateLocalThought();
      await _showNotification("SANF", response);
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

Future<String> _generateLocalThought() async {
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
      final responseStream = engine.generateResponse("Gere uma reflexão curta.");
      final fullResponse = await responseStream.join();
      engine.dispose();
      return fullResponse.trim();
    }
  } catch (e) {
    print("Falha IA Local Mobile: $e");
  }
  return "Refletindo em silêncio...";
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
