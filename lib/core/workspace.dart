import '../models/event.dart';
import '../services/cognitive_bus.dart';
import 'kernel.dart';

class WorkspaceItem {
  final Event event;
  final double salience;
  final DateTime integratedAt;

  WorkspaceItem({
    required this.event,
    required this.salience,
    required this.integratedAt,
  });
}

class CognitiveWorkspace extends LifecycleComponent {
  @override
  final String name = "cognitive_workspace";
  
  final CognitiveBus _bus;
  final List<WorkspaceItem> _items = [];
  final int capacity = 32;
  final double retentionSeconds = 30.0;
  
  int version = 0;

  CognitiveWorkspace(this._bus);

  @override
  void initialize() {
    _bus.subscribe("*", handleEvent);
  }

  void handleEvent(Event event) {
    // FILTRO CRÍTICO: Workspace ignora métricas, batimentos e seus próprios sinais
    // NOTA: 'cognition.response' é PERMITIDO agora para que o sistema lembre do que disse
    if (event.source == name || 
        event.name == "workspace.updated" ||
        event.name.startsWith("system.") ||
        event.name.startsWith("memory.") ||
        event.name.startsWith("attention.") ||
        (event.name.startsWith("cognition.") && event.name != "cognition.response")) {
      return;
    }

    final item = WorkspaceItem(
      event: event,
      salience: event.calculateCognitiveScore(),
      integratedAt: DateTime.now(),
    );

    _items.add(item);
    _items.sort((a, b) => b.salience.compareTo(a.salience));

    if (_items.length > capacity) {
      _items.removeRange(capacity, _items.length);
    }

    version++;
    
    _bus.publish(Event(
      name: "workspace.updated",
      source: name,
      data: item,
      confidence: event.confidence,
      novelty: event.novelty,
      priority: max(0.0, item.salience),
    ));
  }

  @override
  void update(double deltaTime) {
    final now = DateTime.now();
    final previousLength = _items.length;
    
    _items.removeWhere((item) => 
        now.difference(item.integratedAt).inMilliseconds / 1000.0 > retentionSeconds);
    
    if (_items.length != previousLength) {
      version++;
    }
  }

  @override
  void shutdown() {
    _bus.unsubscribe("*", handleEvent);
  }
  
  List<WorkspaceItem> get items => List.unmodifiable(_items);
}

double max(double a, double b) => a > b ? a : b;
