import 'dart:async';
import 'dart:math';
import '../models/event.dart';
import '../core/kernel.dart';
import 'cognitive_bus.dart';

class ProactivityEngine extends LifecycleComponent {
  @override
  final String name = "proactivity_engine";
  
  final CognitiveBus _bus;
  final double proactivityLevel; // 0.0 a 1.0
  final Random _random = Random();

  DateTime _lastInteraction = DateTime.now();
  String _lastVisionDesc = "";
  
  // Limiar de tédio dinâmico (entre 2 a 10 minutos baseado no nível e random)
  double _currentIdleThreshold = 0.0;

  ProactivityEngine(this._bus, {this.proactivityLevel = 0.5});

  @override
  void initialize() {
    _resetIdleThreshold();
    
    // Inscreve-se em eventos que resetam o tédio ou disparam proatividade
    _bus.subscribe("user.input", handleEvent);
    _bus.subscribe("cognition.response", handleEvent);
    _bus.subscribe("sensor.vision", handleEvent);
    _bus.subscribe("sensor.audio", handleEvent);
  }

  void handleEvent(Event event) {
    if (event.name == "user.input" || event.name == "cognition.response") {
      _lastInteraction = DateTime.now();
      _resetIdleThreshold();
    } else if (event.name == "sensor.vision") {
      _checkVisionProactivity(event.data.toString());
    }
  }

  @override
  void update(double deltaTime) {
    final now = DateTime.now();
    final idleTime = now.difference(_lastInteraction).inSeconds;

    if (idleTime > _currentIdleThreshold) {
      _triggerProactiveThought("tédio_cognitivo");
      _lastInteraction = now; // Evita repetição imediata
      _resetIdleThreshold();
    }
  }

  void _checkVisionProactivity(String description) {
    if (_lastVisionDesc.isEmpty) {
      _lastVisionDesc = description;
      return;
    }

    // Se detectou um humano que não estava lá antes
    if (description.toLowerCase().contains("humano") && 
        !_lastVisionDesc.toLowerCase().contains("humano")) {
      _triggerProactiveThought("presença_detectada");
      _lastInteraction = DateTime.now();
    }
    
    _lastVisionDesc = description;
  }

  void _triggerProactiveThought(String triggerType) {
    _bus.publish(Event(
      name: "cognition.proactive_thought",
      source: name,
      data: {"trigger": triggerType},
      priority: 0.6,
      novelty: 0.8,
    ));
  }

  void _resetIdleThreshold() {
    // Base: 300 segundos (5 min). Varia com o nível e um fator random.
    double base = 86400 / (proactivityLevel + 0.1);
    // Adiciona uma variação aleatória de +/- 30% para não ser robótico
    double variance = (base * 0.3) * (_random.nextDouble() * 2 - 1);
    _currentIdleThreshold = base + variance;
  }

  @override
  void shutdown() {
    _bus.unsubscribe("user.input", handleEvent);
    _bus.unsubscribe("cognition.response", handleEvent);
    _bus.unsubscribe("sensor.vision", handleEvent);
    _bus.unsubscribe("sensor.audio", handleEvent);
  }
}
