import 'dart:async';
import 'dart:collection';
import 'package:flutter/foundation.dart';
import '../models/event.dart';

typedef EventHandler = void Function(Event event);

class CognitiveBus {
  static final CognitiveBus _instance = CognitiveBus._internal();
  factory CognitiveBus() => _instance;
  CognitiveBus._internal();

  final Map<String, List<EventHandler>> _listeners = {};
  final List<Event> _queue = [];
  final ListQueue<Event> _history = ListQueue<Event>();
  static const int _historyLimit = 500;

  void subscribe(String eventName, EventHandler handler) {
    _listeners.putIfAbsent(eventName, () => []).add(handler);
  }

  void unsubscribe(String eventName, EventHandler handler) {
    _listeners[eventName]?.remove(handler);
  }

  void publish(Event event) {
    _queue.add(event);
  }

  Event? nextEvent() {
    if (_queue.isEmpty) return null;

    // Filtro de segurança para ordenação no Windows
    try {
      if (_queue.length > 1) {
        _queue.sort((a, b) {
          final scoreA = a.calculateCognitiveScore();
          final scoreB = b.calculateCognitiveScore();
          return scoreB.compareTo(scoreA);
        });
      }
    } catch (e) {
      debugPrint("BUS: Erro na ordenação de eventos (silenciado): $e");
    }

    return _queue.removeAt(0);
  }

  int _dispatchRecursionLevel = 0;
  static const int _maxRecursion = 10;

  int dispatch(Event event) {
    if (_dispatchRecursionLevel > _maxRecursion) {
      debugPrint("BUS CRITICAL: Recursão infinita detectada no evento ${event.name}! Bloqueando.");
      return 0;
    }

    _dispatchRecursionLevel++;
    try {
      final handlers = [
        ...(_listeners[event.name] ?? []),
        ...(_listeners['*'] ?? []),
      ];

      _history.addLast(event);
      if (_history.length > _historyLimit) {
        _history.removeFirst();
      }

      for (var handler in handlers) {
        handler(event);
      }
      return handlers.length;
    } finally {
      _dispatchRecursionLevel--;
    }
  }

  int get pendingCount => _queue.length;

  List<Event> get history => _history.toList();
}
