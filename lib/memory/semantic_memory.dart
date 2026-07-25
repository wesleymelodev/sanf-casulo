import 'dart:convert';
import 'package:hive/hive.dart';
import '../models/event.dart';
import '../services/cognitive_bus.dart';
import '../core/kernel.dart';
import '../core/config.dart';
import 'episodic_memory.dart';

class SemanticConcept {
  final String identifier;
  final String label;
  int evidenceCount;
  double confidence;
  DateTime lastConfirmedAt;

  SemanticConcept({
    required this.identifier,
    required this.label,
    required this.evidenceCount,
    required this.confidence,
    required this.lastConfirmedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'identifier': identifier,
      'label': label,
      'evidence_count': evidenceCount,
      'confidence': confidence,
      'last_confirmed_at': lastConfirmedAt.toIso8601String(),
    };
  }
}

class SemanticMemory extends LifecycleComponent {
  @override
  final String name = "semantic_memory";

  final CognitiveBus _bus;
  final SemanticMemoryConfig _config;
  late Box _box;
  final Map<String, SemanticConcept> _concepts = {};

  SemanticMemory(this._bus, {SemanticMemoryConfig? config})
      : _config = config ?? SemanticMemoryConfig();

  @override
  void initialize() async {
    _box = await Hive.openBox('semantic_memory_store');
    _loadFromStorage();
    _bus.subscribe("memory.episodic.stored", handleEvent);
  }

  void _loadFromStorage() {
    for (var key in _box.keys) {
      final data = Map<String, dynamic>.from(_box.get(key));
      final concept = SemanticConcept(
        identifier: data['identifier'],
        label: data['label'],
        evidenceCount: data['evidence_count'],
        confidence: data['confidence'],
        lastConfirmedAt: DateTime.parse(data['last_confirmed_at']),
      );
      _concepts[concept.identifier] = concept;
    }
  }

  void handleEvent(Event event) {
    if (event.name != "memory.episodic.stored" || event.data is! Episode) return;
    
    final Episode episode = event.data;
    final identity = _conceptIdentity(episode.event);
    final id = identity.item1;
    final label = identity.item2;

    final existing = _concepts[id];
    final evidenceCount = (existing?.evidenceCount ?? 0) + 1;
    final prevConfidence = existing?.confidence ?? 0.0;
    final confidence = 1.0 - (1.0 - prevConfidence) * (1.0 - episode.event.confidence);

    final concept = SemanticConcept(
      identifier: id,
      label: label,
      evidenceCount: evidenceCount,
      confidence: confidence,
      lastConfirmedAt: DateTime.now(),
    );

    _concepts[id] = concept;
    _box.put(id, concept.toMap());

    if (evidenceCount >= _config.minimumEvidence) {
      _bus.publish(Event(
        name: "memory.semantic.consolidated",
        source: name,
        data: concept,
        confidence: confidence,
        novelty: 0.0,
        priority: confidence,
      ));
    }
  }

  Tuple2<String, String> _conceptIdentity(Event event) {
    String label = event.data?.toString() ?? event.name;
    String normalized = label.toLowerCase().replaceAll(RegExp(r'[^\w\s]'), '');
    return Tuple2("${event.name}:$normalized", label);
  }

  @override
  void update(double deltaTime) {}

  @override
  void shutdown() {
    _bus.unsubscribe("memory.episodic.stored", handleEvent);
  }
}

class Tuple2<T1, T2> {
  final T1 item1;
  final T2 item2;
  Tuple2(this.item1, this.item2);
}
