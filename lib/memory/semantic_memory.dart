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

  Map<String, dynamic> toRawMap() {
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
    
    // Recovery
    try {
       _loadFromStorage();
    } catch (e) {
      print("Semantic Box corrupted, clearing...");
      await _box.clear();
    }
    
    _bus.subscribe("memory.episodic.stored", handleEvent);
  }

  void _loadFromStorage() {
    for (var key in _box.keys) {
      final rawData = _box.get(key);
      if (rawData == null) continue;
      final data = Map<String, dynamic>.from(rawData);
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
    _box.put(id, concept.toRawMap());

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

  List<SemanticConcept> recall(String query, {int limit = 5}) {
    final terms = query.toLowerCase().split(RegExp(r'\W+')).where((t) => t.isNotEmpty).toSet();
    
    final ranked = _concepts.values.toList();
    ranked.sort((a, b) {
      double scoreA = _calculateRelevance(a, terms);
      double scoreB = _calculateRelevance(b, terms);
      return scoreB.compareTo(scoreA);
    });

    return ranked.take(limit).toList();
  }

  double _calculateRelevance(SemanticConcept concept, Set<String> queryTerms) {
    if (queryTerms.isEmpty) return concept.confidence;
    
    final conceptTerms = concept.label.toLowerCase().split(RegExp(r'\W+')).toSet();
    final intersection = queryTerms.intersection(conceptTerms);
    
    double overlap = intersection.length / (queryTerms.isEmpty ? 1 : queryTerms.length);
    double evidenceFactor = (concept.evidenceCount / 5).clamp(0.0, 1.0);
    
    return (0.55 * overlap) + (0.30 * concept.confidence) + (0.15 * evidenceFactor);
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
