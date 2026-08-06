import 'dart:async';
import 'dart:io';
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
  bool _bootReady = false;
  bool _isAIBusy = false; // Flag para evitar conflito de rede

  // --- FILA DE SINCRONIZAÇÃO DE SAÍDA (DEBOUNCE) ---
  final Map<String, dynamic> _episodicQueue = {};
  final Map<String, dynamic> _semanticQueue = {};
  Timer? _syncTimer;

  CloudSyncService(this._bus, {this._semanticMemory});

  @override
  void initialize() {
    _authSubscription = _auth.authStateChanges().listen((user) {
      if (user != null) {
        if (_userId == user.uid) return;
        _userId = user.uid;
        debugPrint("CloudSync: Usuário autenticado: $_userId");
        
        // NO WINDOWS: DESATIVADO PULL AUTOMÁTICO PARA TESTE DE ESTABILIDADE
        if (Platform.isAndroid || Platform.isIOS) {
          Future.delayed(const Duration(seconds: 15), () => _pullMemoriesFromCloud());
        }

        // Habilita o PUSH apenas após 30 segundos de boot estável
        Future.delayed(const Duration(seconds: 30), () {
          _bootReady = true;
          debugPrint("CloudSync: Sistema de PUSH (Saída) pronto.");
        });
      } else {
        _signInAnonymously();
      }
    });

    _bus.subscribe("memory.episodic.stored", _onEpisodicStored);
    _bus.subscribe("memory.semantic.consolidated", _onSemanticConsolidated);
    
    // Escuta o estado da IA para evitar "fogo cruzado" na rede do Windows
    _bus.subscribe("cognition.thinking.start", (e) => _isAIBusy = true);
    _bus.subscribe("cognition.thinking.stop", (e) => _isAIBusy = false);
  }

  Future<void> _signInAnonymously() async {
    try {
      await _auth.signInAnonymously();
    } catch (e) {
      debugPrint("CloudSync: Erro ao entrar anonimamente: $e");
    }
  }

  void _onEpisodicStored(Event event) {
    if (_userId == null || !_bootReady) return;
    final dynamic episode = event.data;
    try {
      final data = episode.toRawMap();
      _episodicQueue[data['identifier']] = data;
      _triggerDelayedSync();
    } catch (e) {
      debugPrint("CloudSync: Erro ao enfileirar episódio: $e");
    }
  }

  void _onSemanticConsolidated(Event event) {
    if (_userId == null || !_bootReady) return;
    final dynamic concept = event.data;
    try {
      final data = concept.toRawMap();
      _semanticQueue[data['identifier']] = data;
      _triggerDelayedSync();
    } catch (e) {
      debugPrint("CloudSync: Erro ao enfileirar conceito: $e");
    }
  }

  void _triggerDelayedSync() {
    _syncTimer?.cancel();
    _syncTimer = Timer(const Duration(seconds: 5), () => _processQueues());
  }

  Future<void> _processQueues() async {
    if (_userId == null || !_bootReady) return;

    // REGRA DE OURO: Se a IA estiver pensando ou o barramento estiver cheio, 
    // adiamos a sincronização para evitar crash de sockets no Windows.
    if (_isAIBusy || _bus.pendingCount > 0) {
      debugPrint("CloudSync: Rede ocupada (IA pensando). Adiado em 10s...");
      _syncTimer?.cancel();
      _syncTimer = Timer(const Duration(seconds: 10), () => _processQueues());
      return;
    }

    try {
      final Map<String, dynamic> updates = {};

      if (_episodicQueue.isNotEmpty) {
        debugPrint("CloudSync: Preparando batch de episódios...");
        final batch = Map<String, dynamic>.from(_episodicQueue);
        _episodicQueue.clear();
        batch.forEach((id, data) {
          updates["episodic/$id"] = data;
        });
      }

      if (_semanticQueue.isNotEmpty) {
        debugPrint("CloudSync: Preparando batch de conceitos...");
        final batch = Map<String, dynamic>.from(_semanticQueue);
        _semanticQueue.clear();
        batch.forEach((id, data) {
          // Se for marcado como lixo pelo usuário, removemos do Firebase
          if (data['is_garbage'] == true) {
            updates["semantic/$id"] = null; 
            debugPrint("CloudSync: Removendo conceito deletado do Firebase: $id");
          } else {
            updates["semantic/$id"] = data;
          }
        });
      }

      if (updates.isNotEmpty) {
        debugPrint("CloudSync: Batch preparado. Aguardando respiro de rede...");
        await Future.delayed(const Duration(seconds: 1));
        
        debugPrint("CloudSync: Enviando batch atômico para o Firebase (${updates.length} itens)...");
        await _db.ref("users/$_userId").update(updates).timeout(const Duration(seconds: 15));
        debugPrint("CloudSync: Batch enviado com sucesso.");
      }
    } catch (e) {
      debugPrint("CloudSync Batch Error: $e");
      // Se falhar, as filas já foram limpas para evitar loops de crash
    }
  }

  Future<void> _pullMemoriesFromCloud() async {
    if (_userId == null) return;
    try {
      final episodicSnap = await _db.ref("users/$_userId/episodic").limitToLast(50).get();
      if (episodicSnap.exists) {
        final box = await Hive.openBox('episodic_memory_store');
        final Map<dynamic, dynamic> cloudData = episodicSnap.value as Map;
        cloudData.forEach((key, value) {
          if (!box.containsKey(key)) {
            box.put(key, Map<String, dynamic>.from(value as Map));
          }
        });
      }
    } catch (e) {
      debugPrint("CloudSync: Pull error: $e");
    }
  }

  @override
  void update(double deltaTime) {}

  @override
  void shutdown() {
    _syncTimer?.cancel();
    _authSubscription?.cancel();
    _bus.unsubscribe("memory.episodic.stored", _onEpisodicStored);
    _bus.unsubscribe("memory.semantic.consolidated", _onSemanticConsolidated);
  }
}
