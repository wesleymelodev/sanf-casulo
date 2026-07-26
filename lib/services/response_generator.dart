import '../models/event.dart';
import '../models/bot_expression.dart';
import '../services/cognitive_bus.dart';
import '../core/kernel.dart';
import '../cognition/attention.dart';

class ResponseGenerator extends LifecycleComponent {
  @override
  final String name = "response_generator";

  final CognitiveBus _bus;
  DateTime _lastHomeostasisNotif = DateTime.fromMillisecondsSinceEpoch(0);
  BotExpression _currentExpression = BotExpression.idle;

  ResponseGenerator(this._bus);

  @override
  void initialize() {
    _bus.subscribe("attention.focus.changed", handleEvent);
    _bus.subscribe("system.homeostasis.changed", handleEvent);
    _bus.subscribe("cognition.response", handleEvent);
    _bus.subscribe("cognition.reasoning.concluded", handleEvent);
  }

  void handleEvent(Event event) {
    if (event.name == "attention.focus.changed") {
      final focus = event.data;
      if (focus is AttentionFocus) {
        if (focus.item.event.name == "sensor.pulse") return;
        
        // Se o sistema foca em algo, muda expressão para focado ou curioso
        _setExpression(BotExpression.scanning);
        
        final content = focus.item.event.data?.toString() ?? focus.item.event.name;
        _publishResponse("[Atenção] Focando no processamento de: '$content'");
      }
    } else if (event.name == "system.homeostasis.changed") {
      final now = DateTime.now();
      final mode = event.data['mode']?.toString() ?? "balanced";

      if (mode == "protective") {
        _setExpression(BotExpression.annoyed);
      } else if (mode == "restorative") {
        _setExpression(BotExpression.sleeping);
      }

      if (now.difference(_lastHomeostasisNotif).inMinutes < 3) return;

      if (mode != "balanced") {
        _publishResponse("[Estado] Estabilizando sistemas. Modo ${mode.toUpperCase()} ativado.");
      } else {
        _publishResponse("[Estado] Equilíbrio restaurado. Sistemas em modo nominal.");
        _setExpression(BotExpression.idle);
      }
      _lastHomeostasisNotif = now;
    } else if (event.name == "cognition.response") {
      _setExpression(BotExpression.happy);
      // Volta para idle depois de um tempo
      Future.delayed(const Duration(seconds: 5), () => _setExpression(BotExpression.idle));
    } else if (event.name == "cognition.reasoning.concluded") {
      _setExpression(BotExpression.pleased);
    }
  }

  void _setExpression(BotExpression expression) {
    if (_currentExpression == expression) return;
    _currentExpression = expression;
    _bus.publish(Event(
      name: "ui.expression.changed",
      source: name,
      data: expression,
      priority: 0.1,
    ));
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
    _bus.unsubscribe("cognition.response", handleEvent);
    _bus.unsubscribe("cognition.reasoning.concluded", handleEvent);
  }
}
