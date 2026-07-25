import 'dart:async';
import 'dart:collection';
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
    // Sort by saliency (descending)
    _queue.sort((a, b) => b.calculateCognitiveScore().compareTo(a.calculateCognitiveScore()));
  }

  Event? nextEvent() {
    if (_queue.isEmpty) return null;
    return _queue.removeAt(0);
  }

  int dispatch(Event event) {
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
  }

  int get pendingCount => _queue.length;

  List<Event> get history => _history.toList();
}
