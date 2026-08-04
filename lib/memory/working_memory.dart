import 'package:flutter/foundation.dart';
import '../models/event.dart';
import '../services/cognitive_bus.dart';
import '../core/kernel.dart';
import '../core/config.dart';
import '../core/workspace.dart';

class MemoryItem {
  final Event event;
  final DateTime storedAt;
  final double salience;
  MemoryItem(this.event, this.storedAt, this.salience);
}

class WorkingMemory extends LifecycleComponent {
  @override
  final String name = "working_memory";

  final CognitiveBus _bus;
  final WorkingMemoryConfig _config;
  final List<MemoryItem> _items = [];

  WorkingMemory(this._bus, {WorkingMemoryConfig? config})
      : _config = config ?? WorkingMemoryConfig();

  @override
  void initialize() {
    _bus.subscribe("workspace.updated", handleEvent);
  }

  void handleEvent(Event event) {
    if (event.name != "workspace.updated" || event.data is! WorkspaceItem) return;
    
    final WorkspaceItem workspaceItem = event.data;
    if (workspaceItem.event.source == name) return;

    // SENSITIVITY FILTER: Detect topic shifts
    if (workspaceItem.event.source == "input_bar") {
      final query = workspaceItem.event.data.toString();
      _detectContextShift(query);
    }

    final item = MemoryItem(workspaceItem.event, DateTime.now(), workspaceItem.salience);
    _items.add(item);
    _items.sort((a, b) => b.salience.compareTo(a.salience));

    if (_items.length > _config.capacity) {
      _items.removeRange(_config.capacity, _items.length);
    }

    _bus.publish(Event(
      name: "memory.working.stored",
      source: name,
      data: item,
      confidence: item.event.confidence,
      novelty: item.event.novelty,
      priority: item.salience.clamp(0.0, 1.0),
    ));
  }

  void _detectContextShift(String query) {
    if (_items.isEmpty) return;

    final terms = query.toLowerCase().split(RegExp(r'\W+')).where((t) => t.length > 3).toSet();
    if (terms.isEmpty) return;

    // Compara com as últimas 3 interações
    final recentContext = _items
        .take(3)
        .map((i) => i.event.data.toString().toLowerCase())
        .join(" ");
    
    final recentTerms = recentContext.split(RegExp(r'\W+')).toSet();
    
    // Intersecção de termos relevantes
    final overlap = terms.intersection(recentTerms).length;
    
    // Se não houver nenhum termo em comum em uma frase longa, pode ser um shift
    if (overlap == 0 && terms.length > 3) {
      debugPrint("Sensibilidade Contextual: Possível mudança de assunto detectada.");
      _bus.publish(Event(
        name: "cognition.context_shift",
        source: name,
        data: "MUDANÇA_ASSUNTO",
        priority: 0.7,
      ));
    }
  }

  List<MemoryItem> recall({int limit = 5}) {
    return _items.take(limit).toList();
  }

  @override
  void update(double deltaTime) {
    final now = DateTime.now();
    _items.removeWhere((item) => 
      now.difference(item.storedAt).inMilliseconds / 1000.0 > _config.retentionSeconds);
  }

  @override
  void shutdown() {
    _bus.unsubscribe("workspace.updated", handleEvent);
  }
}
