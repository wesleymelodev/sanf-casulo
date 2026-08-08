import 'dart:async';
import 'package:flutter/foundation.dart';
import 'background_implementation_web.dart' if (dart.library.io) 'background_implementation_mobile.dart' as impl;

class BackgroundBrain {
  static Future<void> initialize() async {
    if (kIsWeb) return;
    await impl.initBackground();
  }

  static void scheduleProactiveTask() {
    if (kIsWeb) return;
    impl.scheduleTask();
  }
}
