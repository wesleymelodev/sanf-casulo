import '../models/event.dart';
import '../services/cognitive_bus.dart';
import '../core/kernel.dart';
import '../core/workspace.dart';

class ReasoningConclusion {
  final String context;
  final String conclusion;
  final double confidence;
  final List<String> evidence;
  final DateTime generatedAt;

  ReasoningConclusion({
    required this.context,
    required this.conclusion,
    required this.confidence,
    required this.evidence,
    required this.generatedAt,
  });
}

class ReasoningEngine extends LifecycleComponent {
  @override
  final String name = "reasoning";

  final CognitiveBus _bus;

  ReasoningEngine(this._bus);

  @override
  void initialize() {
    _bus.subscribe("workspace.updated", handleEvent);
  }

  void handleEvent(Event event) {
    if (event.name != "workspace.updated" || event.data is! WorkspaceItem) return;

    final WorkspaceItem item = event.data;
    final context = _contextFrom(item.event);

    // Simplificação do raciocínio: vincula contexto observado a uma "conclusão" lógica
    final conclusion = ReasoningConclusion(
      context: context,
      conclusion: "O contexto '$context' foi integrado para processamento deliberativo.",
      confidence: item.event.confidence,
      evidence: [context],
      generatedAt: DateTime.now(),
    );

    _bus.publish(Event(
      name: "cognition.reasoning.concluded",
      source: name,
      data: conclusion,
      confidence: conclusion.confidence,
      novelty: item.event.novelty,
      priority: conclusion.confidence,
    ));
  }

  String _contextFrom(Event event) {
    final raw = event.data?.toString() ?? event.name;
    return raw.toLowerCase().trim();
  }

  @override
  void update(double deltaTime) {}

  @override
  void shutdown() {
    _bus.unsubscribe("workspace.updated", handleEvent);
  }
}
