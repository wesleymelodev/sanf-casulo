enum CognitiveEventType {
  homeostasisChanged,
  attentionFocusChanged,
  cognitionResponse,
  metricsUpdated,
  sensoryInput,
  internalReflection
}

class CognitiveEvent {
  final CognitiveEventType type;
  final String name;
  final dynamic data;
  final double priority;
  final DateTime timestamp;

  CognitiveEvent({
    required this.type,
    required this.name,
    required this.data,
    this.priority = 0.0,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  @override
  String toString() => "Event: $name ($type) - Priority: $priority";
}
