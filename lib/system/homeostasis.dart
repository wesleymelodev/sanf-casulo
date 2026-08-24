import 'dart:math';
import '../models/bot_expression.dart';
import '../models/event.dart';
import '../services/cognitive_bus.dart';
import '../core/kernel.dart';
import '../core/config.dart';

enum RegulationMode { balanced, protective, restorative }

class HomeostaticState {
  final double energy;
  final double cognitiveLoad;
  final RegulationMode mode;

  HomeostaticState({
    required this.energy,
    required this.cognitiveLoad,
    required this.mode,
  });

  Map<String, dynamic> toMap() {
    return {
      'energy': energy,
      'cognitive_load': cognitiveLoad,
      'mode': mode.name,
    };
  }
}

class Homeostasis extends LifecycleComponent {
  @override
  final String name = "homeostasis";

  final CognitiveBus _bus;
  final HomeostasisConfig _config;
  bool _isThinking = false;
  
  HomeostaticState state = HomeostaticState(
    energy: 1.0, 
    cognitiveLoad: 0.0, 
    mode: RegulationMode.balanced
  );

  Homeostasis(this._bus, {HomeostasisConfig? config})
      : _config = config ?? HomeostasisConfig();

  @override
  void initialize() {
    _bus.subscribe("cognition.thinking.start", (e) => _isThinking = true);
    _bus.subscribe("cognition.thinking.stop", (e) => _isThinking = false);
    _bus.subscribe("sensor.battery.level", _onBatteryChanged);
    _bus.subscribe("sensor.light", _onLightChanged);
  }

  double _batteryLevel = 1.0;
  double _environmentalLux = 500.0;

  void _onBatteryChanged(Event event) {
    _batteryLevel = (event.data as num).toDouble() / 100.0;
  }

  void _onLightChanged(Event event) {
    _environmentalLux = (event.data as num).toDouble();
  }

  @override
  void update(double deltaTime) {
    double load = _bus.pendingCount / _config.queuePressureThreshold;
    if (_isThinking) load = max(load, 0.7); // Boost load when thinking
    load = min(1.0, load);
    
    // Fator de exaustão baseado em bateria física
    double batteryDrainFactor = 1.0;
    if (_batteryLevel < 0.2) {
      batteryDrainFactor = 2.5; // Drena muito mais rápido se a bateria estiver crítica
    }

    // Fator de luz: Ambientes muito escuros induzem "sono" (perda de energia lenta)
    double lightFactor = 1.0;
    if (_environmentalLux < 5.0 && !_isThinking) {
      lightFactor = 1.5; 
    }

    final energyDelta = (
      _config.energyRecoveryPerSecond * (1.0 - load) -
      _config.energyDrainPerSecond * load * batteryDrainFactor * lightFactor
    ) * deltaTime;

    // Se bateria estiver crítica, energia máxima é limitada
    double maxEnergy = _batteryLevel < 0.15 ? 0.3 : 1.0;

    final energy = (state.energy + energyDelta).clamp(0.0, maxEnergy);
    final mode = _selectMode(energy, load);
    
    final nextState = HomeostaticState(energy: energy, cognitiveLoad: load, mode: mode);
    
    if (_stateChanged(nextState)) {
      state = nextState;
      _bus.publish(Event(
        name: "system.homeostasis.changed",
        source: name,
        data: nextState.toMap(),
        confidence: 1.0,
        novelty: 0.0,
        priority: max(load, 1.0 - energy),
      ));

      // Mapeamento automático de estado homeostático para expressão visual
      BotExpression? autoExpression;
      if (energy < 0.2) {
        autoExpression = BotExpression.exhausted;
      } else if (load > 0.8) {
        autoExpression = BotExpression.thinking;
      } else if (mode == RegulationMode.protective) {
        autoExpression = BotExpression.alert;
      }

      if (autoExpression != null) {
        _bus.publish(Event(
          name: "ui.expression.changed",
          source: name,
          data: autoExpression,
          priority: 0.6,
        ));
      }
    }
  }

  RegulationMode _selectMode(double energy, double load) {
    if (energy <= _config.protectiveEnergyThreshold || load >= 1.0) {
      return RegulationMode.protective;
    }
    if (load == 0.0 && energy < 0.95) {
      return RegulationMode.restorative;
    }
    return RegulationMode.balanced;
  }

  bool _stateChanged(HomeostaticState next) {
    return next.mode != state.mode ||
           (next.energy - state.energy).abs() >= 0.01 ||
           (next.cognitiveLoad - state.cognitiveLoad).abs() >= 0.01;
  }

  @override
  void shutdown() {}
}
