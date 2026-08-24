import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class BackgroundBrain {
  static const platform = MethodChannel('com.lokinefrius.sanf/settings');

  static Future<void> initialize() async {
    // A inicialização nativa agora é feita no MainActivity
  }

  static void scheduleProactiveTask() {
    if (kIsWeb) return;
    try {
      platform.invokeMethod('scheduleWorker');
    } catch (e) {
      debugPrint("Error scheduling native worker: $e");
    }
  }
}
