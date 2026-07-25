import 'dart:convert';
import 'dart:math';
import 'package:hive/hive.dart';
import '../models/event.dart';
import '../services/cognitive_bus.dart';
import '../core/kernel.dart';
import '../core/config.dart';
import '../core/workspace.dart';
import 'package:uuid/uuid.dart';

class Episode {
  final String identifier;
  final Event event;
  final double salience;
  final DateTime recordedAt;

  Episode({
    required this.identifier,
    required this.event,
    required this.salience,
    required this.recordedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'identifier': identifier,
      'salience': salience,
      'recorded_at': recordedAt.toIso8601String(),
      'event': {
        'name': event.name,
        'source': event.source,
        'data': event.data,
        'confidence': event.confidence,
        'novelty': event.novelty,
        'priority': event.priority,
        'energy_cost': event.energyCost,
        'decay': event.decay,
        'occurred_at': event.occurredAt.toIso8601String(),
      }
    };
  }
}

class EpisodicMemory extends LifecycleComponent {
  @override
  final String name = "episodic_memory";

  final CognitiveBus _bus;
  final EpisodicMemoryConfig _config;
  late Box _box;

  EpisodicMemory(this._bus, {EpisodicMemoryConfig? config})
      : _config = config ?? EpisodicMemoryConfig();

  @override
  void initialize() async {
    _box = await Hive.openBox('episodic_memory_store');
    _bus.subscribe("workspace.updated", handleEvent);
    _bus.subscribe("cognition.learning.fact", handleEvent);
  }

  void handleEvent(Event event) {
    if (event.name == "cognition.learning.fact") {
      _storeEpisode(event, 1.0);
      return;
    }

    if (event.name != "workspace.updated" || event.data is! WorkspaceItem) return;
    final item = event.data as WorkspaceItem;
    if (item.event.source == name) return;

    _storeEpisode(item.event, item.salience);
  }

  void _storeEpisode(Event event, double salience) {
    final episode = Episode(
      identifier: const Uuid().v4(),
      event: event,
      salience: salience,
      recordedAt: DateTime.now(),
    );

    _box.add(episode.toMap());
    
    // Trim logic (Hive specific)
    if (_box.length > _config.capacity) {
      _box.deleteAt(0);
    }

    _bus.publish(Event(
      name: "memory.episodic.stored",
      source: name,
      data: episode,
      confidence: event.confidence,
      novelty: event.novelty,
      priority: salience.clamp(0.0, 1.0),
    ));
  }

  @override
  void update(double deltaTime) {}

  @override
  void shutdown() {
    _bus.unsubscribe("workspace.updated", handleEvent);
    _bus.unsubscribe("cognition.learning.fact", handleEvent);
  }
}
