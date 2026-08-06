import 'dart:math';
import 'package:flutter/cupertino.dart';
import 'package:hive/hive.dart';
import '../models/event.dart';
import '../services/cognitive_bus.dart';
import '../core/kernel.dart';
import '../core/config.dart';
import '../core/workspace.dart';
import 'package:uuid/uuid.dart';

class Episode {
  final String identifier;
  final String sessionId;
  final Event event;
  final double salience;
  final DateTime recordedAt;

  Episode({
    required this.identifier,
    required this.sessionId,
    required this.event,
    required this.salience,
    required this.recordedAt,
  });

  // STRICTLY PRIMITIVE MAP
  Map<String, dynamic> toRawMap() {
    return {
      'identifier': identifier,
      'session_id': sessionId,
      'salience': salience,
      'recorded_at': recordedAt.toIso8601String(),
      'event_name': event.name,
      'event_source': event.source,
      'event_data': event.data?.toString() ?? "", // Force String to avoid type errors
      'confidence': event.confidence,
      'novelty': event.novelty,
      'priority': event.priority,
    };
  }
}

class EpisodicMemory extends LifecycleComponent {
  @override
  final String name = "episodic_memory";

  final CognitiveBus _bus;
  final EpisodicMemoryConfig _config;
  late Box _box;

  String? _currentSessionId;
  DateTime? _lastActivityAt;

  EpisodicMemory(this._bus, {EpisodicMemoryConfig? config})
      : _config = config ?? EpisodicMemoryConfig();

  @override
  void initialize() async {
    _box = await Hive.openBox('episodic_memory_store');
    
    // Recovery: if box is corrupted with old complex types, clear it
    try {
      if (_box.isNotEmpty) {
        final lastEntry = _box.values.last;
        _currentSessionId = lastEntry['session_id'];
        _lastActivityAt = DateTime.parse(lastEntry['recorded_at']);
      }
    } catch (e) {
      print("Episodic Box corrupted or incompatible, clearing...");
      await _box.clear();
    }

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
    final now = DateTime.now();

    // TEMPORAL FRAGMENTATION LOGIC
    // Evita resetar a sessão se o robô estiver "ocupado" (ex: mandando mensagem ou pensando)
    bool isSystemBusy = event.source == "input_bar" || event.name.contains("thinking");

    if (_currentSessionId == null || 
        _lastActivityAt == null || 
        (!isSystemBusy && now.difference(_lastActivityAt!).inMinutes > _config.sessionIdleThresholdMinutes)) {
      _currentSessionId = const Uuid().v4();
      debugPrint("Fragmentação Temporal: Iniciando nova sessão ID: $_currentSessionId");
      
      _bus.publish(Event(
        name: "memory.episodic.session_started",
        source: name,
        data: _currentSessionId,
        priority: 0.3,
      ));
    }

    _lastActivityAt = now;

    final episode = Episode(
      identifier: const Uuid().v4(),
      sessionId: _currentSessionId!,
      event: event,
      salience: salience,
      recordedAt: now,
    );

    // CRITICAL: store with UUID as key for instant lookup
    _box.put(episode.identifier, episode.toRawMap());
    
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
