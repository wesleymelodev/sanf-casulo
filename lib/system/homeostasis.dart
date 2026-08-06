import 'dart:math';
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
  }

  @override
  void update(double deltaTime) {
    double load = _bus.pendingCount / _config.queuePressureThreshold;
    if (_isThinking) load = max(load, 0.7); // Boost load when thinking
    load = min(1.0, load);
    
    final energyDelta = (
      _config.energyRecoveryPerSecond * (1.0 - load) -
      _config.energyDrainPerSecond * load
    ) * deltaTime;

    final energy = (state.energy + energyDelta).clamp(0.0, 1.0);
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
