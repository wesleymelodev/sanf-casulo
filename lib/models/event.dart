import 'dart:math';

class Event {
  final String name;
  final String source;
  final dynamic data;
  final double confidence;
  final double novelty;
  final double priority;
  final double energyCost;
  final double decay;
  final List<double>? embedding;
  final DateTime occurredAt;
  final Map<String, dynamic> metadata;

  Event({
    required this.name,
    required this.source,
    this.data,
    this.confidence = 1.0,
    this.novelty = 0.5,
    this.priority = 0.5,
    this.energyCost = 0.1,
    this.decay = 0.02,
    this.embedding,
    DateTime? occurredAt,
    this.metadata = const {},
  })  : occurredAt = occurredAt ?? DateTime.now(),
        assert(confidence >= 0.0 && confidence <= 1.0),
        assert(novelty >= 0.0 && novelty <= 1.0),
        assert(priority >= 0.0 && priority <= 1.0),
        assert(energyCost >= 0.0 && energyCost <= 1.0),
        assert(decay >= 0.0 && decay <= 1.0);

  double calculateCognitiveScore({DateTime? now}) {
    final effectiveNow = now ?? DateTime.now();
    final elapsed = max(0.0, effectiveNow.difference(occurredAt).inMilliseconds / 1000.0);
    final freshness = max(0.0, 1.0 - elapsed * decay);
    
    return (0.35 * priority) +
           (0.30 * confidence) +
           (0.20 * novelty) +
           (0.15 * freshness) -
           energyCost;
  }
}
