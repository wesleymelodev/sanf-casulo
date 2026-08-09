import 'dart:async';
import 'dart:io';
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

  Future<void> initialize() async {
    for (var component in _components) {
      try {
        debugPrint("Kernel Component: Inicializando ${component.name}...");
        component.initialize();
        // Delay de segurança entre componentes para evitar pico de I/O no Windows
        if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
          await Future.delayed(const Duration(milliseconds: 300));
        }
      } catch (e) {
        debugPrint("ERRO CRÍTICO no componente ${component.name}: $e");
      }
    }
  }

  void update(double deltaTime) {
    for (var component in _components) {
      try {
        component.update(deltaTime);
      } catch (e) {
        debugPrint("ERRO DE CICLO no componente ${component.name}: $e");
      }
    }
  }

  void shutdown() {
    _timer?.cancel();
    for (var component in _components.reversed) {
      component.shutdown();
    }
  }

  void run() async {
    running = true;
    startedAt = DateTime.now();
    
    // Aguarda inicialização sequencial estável
    await initialize();

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
