import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/event.dart';
import '../core/kernel.dart';
import '../services/cognitive_bus.dart';
import '../memory/episodic_memory.dart';

class ConsolidationEngine extends LifecycleComponent {
  @override
  final String name = "consolidation_engine";

  final CognitiveBus _bus;
  final EpisodicMemory _episodicMemory;
  
  String? _lastSessionId;
  DateTime _lastCheck = DateTime.now();

  ConsolidationEngine(this._bus, this._episodicMemory);

  @override
  void initialize() {
    _bus.subscribe("memory.episodic.session_started", (e) {
      final newSessionId = e.data.toString();
      if (_lastSessionId != null && _lastSessionId != newSessionId) {
        _triggerConsolidation(_lastSessionId!);
      }
      _lastSessionId = newSessionId;
    });
  }

  @override
  void update(double deltaTime) {
    // Verificação periódica para sessões que nunca iniciaram uma nova (ex: app fechado e reaberto)
    final now = DateTime.now();
    if (now.difference(_lastCheck).inMinutes > 5) {
      _lastCheck = now;
      // Poderia haver uma lógica aqui para consolidar a sessão atual se estiver inativa por muito tempo
    }
  }

  Future<void> _triggerConsolidation(String sessionId) async {
    debugPrint("ConsolidationEngine: Solicitando consolidação para a sessão $sessionId");
    
    // Pequeno delay para garantir que todos os episódios da sessão anterior foram gravados
    await Future.delayed(const Duration(seconds: 2));

    final episodes = _episodicMemory.getSessionEpisodes(sessionId);
    if (episodes.isEmpty) return;

    // Converte episódios em um formato legível para o LanguageEngine
    final List<Map<String, dynamic>> dialogueTurns = [];
    for (var ep in episodes) {
      if (ep.event.name == "user.input" || ep.event.name == "cognition.response") {
        dialogueTurns.add({
          "role": ep.event.name == "user.input" ? "user" : "assistant",
          "content": ep.event.data.toString(),
          "time": ep.recordedAt.toIso8601String(),
        });
      }
    }

    if (dialogueTurns.length < 2) {
      debugPrint("ConsolidationEngine: Sessão muito curta para consolidar.");
      return;
    }

    _bus.publish(Event(
      name: "memory.episodic.session_finalized",
      source: name,
      data: dialogueTurns,
      priority: 0.4,
    ));
  }

  @override
  void shutdown() {}
}
