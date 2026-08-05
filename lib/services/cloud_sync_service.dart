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
  bool _isSyncing = false;

  CloudSyncService(this._bus, {this._semanticMemory});

  @override
  void initialize() {
    _authSubscription = _auth.authStateChanges().listen((user) {
      if (user != null) {
        if (_userId == user.uid) return; // Evita re-triggering no Windows
        _userId = user.uid;
        debugPrint("CloudSync: Usuário autenticado: $_userId");
        
        // DESATIVADO TOTALMENTE NO BOOT PARA GARANTIR ESTABILIDADE NO WINDOWS
        // Future.delayed(const Duration(seconds: 10), () => _pullMemoriesFromCloud());
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
    if (_userId == null || _isSyncing) return;
    _isSyncing = true;
    debugPrint("CloudSync: Iniciando sincronização inteligente...");

    try {
      // 1. Puxar Semântica (Otimizado)
      final semanticBox = await Hive.openBox('semantic_memory_store');
      
      if (semanticBox.length > 5000) {
        debugPrint("CloudSync: Memória local muito robusta (${semanticBox.length} itens). Pulando sincronização semântica para estabilidade.");
      } else {
        final semanticSnap = await _db.ref("users/$_userId/semantic").limitToLast(200).get();
        if (semanticSnap.exists) {
          final dynamic rawData = semanticSnap.value;
          if (rawData is Map) {
            int news = 0;
            rawData.forEach((key, value) {
              if (!semanticBox.containsKey(key)) {
                semanticBox.put(key, Map<String, dynamic>.from(value as Map));
                news++;
              }
            });
            if (news > 0) debugPrint("CloudSync: $news novos conceitos recuperados.");
          }
        }
      }

      // 2. Puxar Episódica (Otimizado com containsKey O(1))
      debugPrint("CloudSync: Buscando memórias episódicas...");
      final episodicSnap = await _db.ref("users/$_userId/episodic").limitToLast(100).get();
      
      if (episodicSnap.exists) {
        final episodicBox = await Hive.openBox('episodic_memory_store');
        final dynamic rawData = episodicSnap.value;
        int news = 0;
        
        void processItem(String key, dynamic value) {
          if (value is Map && !episodicBox.containsKey(key)) {
            episodicBox.put(key, Map<String, dynamic>.from(value));
            news++;
          }
        }

        if (rawData is Map) {
          rawData.forEach((key, value) => processItem(key.toString(), value));
        } else if (rawData is List) {
          for (var i = 0; i < rawData.length; i++) {
            if (rawData[i] != null) processItem(i.toString(), rawData[i]);
          }
        }

        if (news > 0) debugPrint("CloudSync: $news episódios recuperados.");
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
    } finally {
      _isSyncing = false;
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
