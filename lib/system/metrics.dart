import '../models/event.dart';
import '../services/cognitive_bus.dart';
import '../core/kernel.dart';

class Metrics extends LifecycleComponent {
  @override
  final String name = "metrics";

  final CognitiveBus _bus;
  final int publishIntervalCycles;
  
  int _kernelCycles = 0;
  int _dispatchedTotal = 0;
  final Map<String, int> _dispatchByType = {};
  late DateTime _startedAt;

  Metrics(this._bus, {this.publishIntervalCycles = 100});

  @override
  void initialize() {
    _startedAt = DateTime.now();
    _bus.subscribe("*", _onEventDispatched);
  }

  void _onEventDispatched(Event event) {
    if (event.source == name) return;
    _dispatchedTotal++;
    _dispatchByType[event.name] = (_dispatchByType[event.name] ?? 0) + 1;
  }

  @override
  void update(double deltaTime) {
    _kernelCycles++;
    if (_kernelCycles % publishIntervalCycles == 0) {
      _publishMetrics();
    }
  }

  void _publishMetrics() {
    final uptime = DateTime.now().difference(_startedAt).inSeconds.toDouble();
    
    _bus.publish(Event(
      name: "system.metrics.updated",
      source: name,
      data: {
        'kernel_cycles': _kernelCycles,
        'events_dispatched_total': _dispatchedTotal,
        'queue_pressure': _bus.pendingCount,
        'uptime': uptime,
      },
      priority: 0.1,
      energyCost: 0.01,
    ));
  }

  @override
  void shutdown() {
    _bus.unsubscribe("*", _onEventDispatched);
  }
}
