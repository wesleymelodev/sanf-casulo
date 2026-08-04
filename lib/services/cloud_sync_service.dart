import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import '../models/event.dart';
import 'cognitive_bus.dart';
import '../core/kernel.dart';
import '../memory/semantic_memory.dart';

class CloudSyncService extends LifecycleComponent {
  @override
  final String name = "cloud_sync";

  final CognitiveBus _bus;
  final SemanticMemory? _semanticMemory; // Referência para refresh
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseDatabase _db = FirebaseDatabase.instance;
  
  StreamSubscription? _authSubscription;
  String? _userId;

  CloudSyncService(this._bus, {this._semanticMemory});

  @override
  void initialize() {
    _authSubscription = _auth.authStateChanges().listen((user) {
      if (user != null) {
        _userId = user.uid;
        debugPrint("CloudSync: Usuário autenticado: $_userId");
        _pullMemoriesFromCloud();
      } else {
        _signInAnonymously();
      }
    });

    // Inscreve-se em eventos de persistência para espelhar na nuvem
    _bus.subscribe("memory.episodic.stored", _onEpisodicStored);
    _bus.subscribe("memory.semantic.consolidated", _onSemanticConsolidated);
  }

  Future<void> _signInAnonymously() async {
    try {
      await _auth.signInAnonymously();
    } catch (e) {
      debugPrint("CloudSync: Erro ao entrar anonimamente: $e");
    }
  }

  void _onEpisodicStored(Event event) {
    if (_userId == null) return;
    
    // O dado do episódio está em event.data (classe Episode)
    // Usamos toRawMap para garantir compatibilidade com JSON/Firebase
    final dynamic episode = event.data;
    try {
      final data = episode.toRawMap();
      _db.ref("users/$_userId/episodic/${data['identifier']}").set(data);
    } catch (e) {
      debugPrint("CloudSync: Erro ao sincronizar episódio: $e");
    }
  }

  void _onSemanticConsolidated(Event event) {
    if (_userId == null) return;

    final dynamic concept = event.data;
    try {
      final data = concept.toRawMap();
      _db.ref("users/$_userId/semantic/${data['identifier']}").set(data);
    } catch (e) {
      debugPrint("CloudSync: Erro ao sincronizar conceito: $e");
    }
  }

  Future<void> _pullMemoriesFromCloud() async {
    if (_userId == null) return;
    debugPrint("CloudSync: Sincronizando memórias da nuvem...");

    try {
      // 1. Puxar Semântica
      final semanticSnap = await _db.ref("users/$_userId/semantic").get();
      if (semanticSnap.exists) {
        final box = await Hive.openBox('semantic_memory_store');
        final Map<dynamic, dynamic> cloudData = semanticSnap.value as Map;
        
        cloudData.forEach((key, value) {
          if (!box.containsKey(key)) {
            box.put(key, Map<String, dynamic>.from(value as Map));
            debugPrint("CloudSync: Novo conceito recuperado: $key");
          }
        });
      }

      // 2. Puxar Episódica (Limitado aos últimos 100 para performance)
      final episodicSnap = await _db.ref("users/$_userId/episodic").limitToLast(100).get();
      if (episodicSnap.exists) {
        final box = await Hive.openBox('episodic_memory_store');
        final Map<dynamic, dynamic> cloudData = episodicSnap.value as Map;

        cloudData.forEach((key, value) {
          // Firebase keys são strings, mas no Hive Episodic usamos auto-increment (add)
          // Verificamos se o identificador único já existe na lista
          final exists = box.values.any((v) => v['identifier'] == key);
          if (!exists) {
            box.add(Map<String, dynamic>.from(value as Map));
            debugPrint("CloudSync: Novo episódio recuperado: $key");
          }
        });
      }

      debugPrint("CloudSync: Sincronização concluída.");
      
      // FORÇA O REFRESH DA MEMÓRIA ATIVA
      _semanticMemory?.refreshActiveMemory();
      
      // Notifica o sistema que a memória foi atualizada
      _bus.publish(Event(
        name: "memory.cloud.synced",
        source: name,
        priority: 0.3,
      ));
      
    } catch (e) {
      debugPrint("CloudSync: Erro ao puxar dados: $e");
    }
  }

  @override
  void update(double deltaTime) {}

  @override
  void shutdown() {
    _authSubscription?.cancel();
    _bus.unsubscribe("memory.episodic.stored", _onEpisodicStored);
    _bus.unsubscribe("memory.semantic.consolidated", _onSemanticConsolidated);
  }
}
