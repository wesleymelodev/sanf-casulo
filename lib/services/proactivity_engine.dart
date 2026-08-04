import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import '../models/event.dart';
import '../core/kernel.dart';
import 'cognitive_bus.dart';

class ProactivityEngine extends LifecycleComponent {
  @override
  final String name = "proactivity_engine";
  
  final CognitiveBus _bus;
  double proactivityLevel; // 0.0 a 1.0
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
    
    // Escuta mudanças dinâmicas no nível de proatividade
    _bus.subscribe("system.config.proactivity_changed", (e) {
      proactivityLevel = (e.data as double);
      _resetIdleThreshold();
      debugPrint("Proatividade ajustada: $proactivityLevel. Próximo tédio em: ${_currentIdleThreshold.toInt()}s");
    });
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
    // 1.0 -> Janela de [60s até 60s] (ou até um max curto, ex: 5 min)
    // 0.0 -> Janela de [60s até 24 horas]

    double minSeconds = 60.0; // 1 minuto

    // Define o limite superior da fatia baseado no proactivityLevel
    double maxSeconds = 60.0 + (86400.0 - 60.0) * (1.0 - proactivityLevel);

    // Sorteia QUALQUER valor dentro de toda a fatia [minSeconds ... maxSeconds]
    double range = maxSeconds - minSeconds;
    _currentIdleThreshold = minSeconds + (_random.nextDouble() * range);
  }

  @override
  void shutdown() {
    _bus.unsubscribe("user.input", handleEvent);
    _bus.unsubscribe("cognition.response", handleEvent);
    _bus.unsubscribe("sensor.vision", handleEvent);
    _bus.unsubscribe("sensor.audio", handleEvent);
  }
}
