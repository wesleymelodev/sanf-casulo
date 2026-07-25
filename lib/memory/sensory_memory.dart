import '../models/event.dart';
import '../services/cognitive_bus.dart';
import '../core/kernel.dart';
import '../core/config.dart';

class SensoryTrace {
  final Event event;
  final double salience;
  final DateTime receivedAt;
  SensoryTrace(this.event, this.salience, this.receivedAt);
}

class SensoryMemory extends LifecycleComponent {
  @override
  final String name = "sensory_memory";
  
  final CognitiveBus _bus;
  final SensoryMemoryConfig _config;
  final List<SensoryTrace> _traces = [];

  SensoryMemory(this._bus, {SensoryMemoryConfig? config}) 
      : _config = config ?? SensoryMemoryConfig();

  @override
  void initialize() {
    _bus.subscribe("sensor.*", handleEvent);
  }

  void handleEvent(Event event) {
    if (!event.name.startsWith("sensor.")) return;

    final salience = event.calculateCognitiveScore();
    final trace = SensoryTrace(event, salience, DateTime.now());
    
    _traces.add(trace);
    if (_traces.length > _config.capacity) {
      _traces.removeAt(0);
    }

    if (salience >= _config.salienceThreshold) {
      _bus.publish(Event(
        name: "perception.salient",
        source: name,
        data: event.data,
        confidence: event.confidence,
        novelty: event.novelty,
        priority: salience,
        metadata: {
          "sensor_event": event.name,
          "sensor_source": event.source
        },
      ));
    }
  }

  @override
  void update(double deltaTime) {
    final now = DateTime.now();
    _traces.removeWhere((t) => 
      now.difference(t.receivedAt).inMilliseconds / 1000.0 > _config.retentionSeconds);
  }

  @override
  void shutdown() {
    _bus.unsubscribe("sensor.*", handleEvent);
  }
}
