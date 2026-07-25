import '../models/event.dart';
import '../services/cognitive_bus.dart';
import '../core/kernel.dart';
import '../core/workspace.dart';

class AttentionFocus {
  final WorkspaceItem item;
  final double score;
  AttentionFocus(this.item, this.score);
}

class AttentionController extends LifecycleComponent {
  @override
  final String name = "attention";

  final CognitiveBus _bus;
  AttentionFocus? _focus;
  final double focusChangeThreshold = 0.05;

  AttentionController(this._bus);

  @override
  void initialize() {
    _bus.subscribe("workspace.updated", handleEvent);
  }

  void handleEvent(Event event) {
    if (event.name != "workspace.updated" || event.data is! WorkspaceItem) return;

    final WorkspaceItem item = event.data;
    final double score = item.salience;

    if (_focus != null && score < _focus!.score + focusChangeThreshold) {
      return;
    }

    final candidate = AttentionFocus(item, score);
    _focus = candidate;

    _bus.publish(Event(
      name: "attention.focus.changed",
      source: name,
      data: candidate,
      confidence: item.event.confidence,
      novelty: item.event.novelty,
      priority: score.clamp(0.0, 1.0),
    ));
  }

  @override
  void update(double deltaTime) {}

  @override
  void shutdown() {
    _bus.unsubscribe("workspace.updated", handleEvent);
  }

  AttentionFocus? get focus => _focus;
}
