import 'dart:async';
import 'package:flutter/foundation.dart';
import '../services/cognitive_bus.dart';

abstract class LifecycleComponent {
  String get name;
  void initialize();
  void update(double deltaTime);
  void shutdown();
}

class Kernel {
  final List<LifecycleComponent> _components = [];
  bool running = false;
  int cycle = 0;
  DateTime? startedAt;
  Timer? _timer;
  
  final double targetCycleSeconds;

  Kernel({this.targetCycleSeconds = 0.01});

  void register(LifecycleComponent component) {
    if (_components.any((c) => c.name == component.name)) {
      throw Exception("Component ${component.name} already registered.");
    }
    _components.add(component);
  }

  void initialize() {
    for (var component in _components) {
      component.initialize();
    }
  }

  void update(double deltaTime) {
    for (var component in _components) {
      component.update(deltaTime);
    }
  }

  void shutdown() {
    _timer?.cancel();
    for (var component in _components.reversed) {
      component.shutdown();
    }
  }

  void run() {
    running = true;
    startedAt = DateTime.now();
    initialize();

    DateTime previous = startedAt!;
    _timer = Timer.periodic(Duration(milliseconds: (targetCycleSeconds * 1000).toInt()), (timer) {
      final now = DateTime.now();
      final deltaTime = now.difference(previous).inMilliseconds / 1000.0;
      update(deltaTime);
      previous = now;
      cycle++;
    });
  }

  void stop() {
    running = false;
    shutdown();
  }
}
