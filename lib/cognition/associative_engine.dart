import 'dart:math';
import '../models/event.dart';
import '../services/cognitive_bus.dart';
import '../core/kernel.dart';
import '../core/workspace.dart';

class Association {
  final String source;
  final String target;
  final double strength;
  final int observations;
  final DateTime lastObservedAt;

  Association({
    required this.source,
    required this.target,
    required this.strength,
    required this.observations,
    required this.lastObservedAt,
  });
}

class AssociativeEngine extends LifecycleComponent {
  @override
  final String name = "associative_engine";

  final CognitiveBus _bus;
  final Map<String, Association> _associations = {};
  String? _previousKey;
  final double learningRate = 0.20;
  final int capacity = 2048;

  AssociativeEngine(this._bus);

  @override
  void initialize() {
    _bus.subscribe("workspace.updated", handleEvent);
  }

  void handleEvent(Event event) {
    if (event.name != "workspace.updated" || event.data is! WorkspaceItem) return;

    final String currentKey = _contentKey(event.data.event);
    if (_previousKey != null && _previousKey != currentKey) {
      final association = _reinforce(_previousKey!, currentKey, event.data.salience);
      _bus.publish(Event(
        name: "cognition.association.updated",
        source: name,
        data: association,
        confidence: association.strength.clamp(0.0, 1.0),
        novelty: 1.0 / association.observations,
        priority: association.strength,
      ));
    }
    _previousKey = currentKey;
  }

  Association _reinforce(String source, String target, double salience) {
    final key = "$source->$target";
    final previous = _associations[key];
    final observations = (previous?.observations ?? 0) + 1;
    final priorStrength = previous?.strength ?? 0.0;
    final gain = learningRate * salience.clamp(0.0, 1.0);
    
    final association = Association(
      source: source,
      target: target,
      strength: priorStrength + (1.0 - priorStrength) * gain,
      observations: observations,
      lastObservedAt: DateTime.now(),
    );

    _associations[key] = association;
    _trimToCapacity();
    return association;
  }

  void _trimToCapacity() {
    if (_associations.length <= capacity) return;
    final sortedKeys = _associations.keys.toList()
      ..sort((a, b) => _associations[a]!.strength.compareTo(_associations[b]!.strength));
    
    final toRemove = _associations.length - capacity;
    for (var i = 0; i < toRemove; i++) {
      _associations.remove(sortedKeys[i]);
    }
  }

  String _contentKey(Event event) {
    final data = event.data?.toString() ?? event.name;
    return data.toLowerCase().replaceAll(RegExp(r'[^\w\s]'), '').trim();
  }

  @override
  void update(double deltaTime) {}

  @override
  void shutdown() {
    _bus.unsubscribe("workspace.updated", handleEvent);
  }
}
