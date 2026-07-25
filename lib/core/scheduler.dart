import 'dart:math';
import '../services/cognitive_bus.dart';
import 'kernel.dart';

class SchedulerPolicy {
  final int maxEventsPerCycle;
  final double timeBudgetSeconds;

  SchedulerPolicy({
    this.maxEventsPerCycle = 32,
    this.timeBudgetSeconds = 0.010,
  });
}

class Scheduler extends LifecycleComponent {
  @override
  final String name = "scheduler";
  
  final CognitiveBus _bus;
  final SchedulerPolicy _policy;
  
  int dispatchedEvents = 0;
  int lastCycleEvents = 0;

  Scheduler(this._bus, {SchedulerPolicy? policy}) 
      : _policy = policy ?? SchedulerPolicy();

  @override
  void initialize() {
    lastCycleEvents = 0;
  }

  @override
  void update(double deltaTime) {
    final stopwatch = Stopwatch()..start();
    int processed = 0;

    while (processed < _policy.maxEventsPerCycle) {
      if (stopwatch.elapsedMilliseconds / 1000.0 >= _policy.timeBudgetSeconds) {
        break;
      }

      final event = _bus.nextEvent();
      if (event == null) break;

      _bus.dispatch(event);
      processed++;
    }

    lastCycleEvents = processed;
    dispatchedEvents += processed;
  }

  @override
  void shutdown() {}
}
