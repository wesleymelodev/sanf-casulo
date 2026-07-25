import '../models/event.dart';
import '../services/cognitive_bus.dart';
import '../core/kernel.dart';
import 'attention.dart';

class ResponseGenerator extends LifecycleComponent {
  @override
  final String name = "response_generator";

  final CognitiveBus _bus;
  DateTime _lastHomeostasisNotif = DateTime.fromMillisecondsSinceEpoch(0);

  ResponseGenerator(this._bus);

  @override
  void initialize() {
    _bus.subscribe("attention.focus.changed", handleEvent);
    _bus.subscribe("system.homeostasis.changed", handleEvent);
  }

  void handleEvent(Event event) {
    if (event.name == "attention.focus.changed") {
      final AttentionFocus focus = event.data;
      if (focus.item.event.name == "sensor.pulse") return;

      final content = focus.item.event.data?.toString() ?? focus.item.event.name;
      _publishResponse("[Atenção] Focando no processamento de: '$content'");
      
    } else if (event.name == "system.homeostasis.changed") {
      final now = DateTime.now();
      if (now.difference(_lastHomeostasisNotif).inMinutes < 3) return;

      final mode = event.data['mode']?.toString() ?? "balanced";
      if (mode != "balanced") {
        _publishResponse("[Estado] Estabilizando sistemas. Modo ${mode.toUpperCase()} ativado.");
      } else {
        _publishResponse("[Estado] Equilíbrio restaurado. Sistemas em modo nominal.");
      }
      _lastHomeostasisNotif = now;
    }
  }

  void _publishResponse(String text) {
    _bus.publish(Event(
      name: "cognition.response",
      source: name,
      data: text,
      priority: 0.5,
    ));
  }

  @override
  void update(double deltaTime) {}

  @override
  void shutdown() {
    _bus.unsubscribe("attention.focus.changed", handleEvent);
    _bus.unsubscribe("system.homeostasis.changed", handleEvent);
  }
}
