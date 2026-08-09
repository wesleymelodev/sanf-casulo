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
  
  FirebaseAuth? _auth;
  FirebaseDatabase? _db;
  
  StreamSubscription? _authSubscription;
  String? _userId;
  bool _bootReady = false;
  bool _isAIBusy = false;
  bool _isSpeaking = false;
  DateTime _lastActivity = DateTime.now(); // Rastreador de inércia

  // --- FILA DE SINCRONIZAÇÃO DE SAÍDA (DEBOUNCE) ---
  final Map<String, dynamic> _episodicQueue = {};
  final Map<String, dynamic> _semanticQueue = {};
  Timer? _syncTimer;

  CloudSyncService(this._bus, {this._semanticMemory});

  @override
  void initialize() {
    try {
      // Lazy access to Firebase instances to prevent crash if not initialized
      _auth = FirebaseAuth.instance;
      _db = FirebaseDatabase.instance;
    } catch (e) {
      debugPrint("CloudSync: Firebase not available, disabling sync. $e");
      return;
    }

    _authSubscription = _auth?.authStateChanges().listen((user) {
      if (user != null) {
        if (_userId == user.uid) return;
        _userId = user.uid;
        debugPrint("CloudSync: Usuário autenticado: $_userId");
        
        // NO WINDOWS/WEB: DESATIVADO PULL AUTOMÁTICO PARA TESTE DE ESTABILIDADE
        if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
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
    
    // Escuta o estado da IA e da fala para atualizar a última atividade
    _bus.subscribe("cognition.thinking.start", (e) {
      _isAIBusy = true;
      _lastActivity = DateTime.now();
    });
    _bus.subscribe("cognition.thinking.stop", (e) {
      _isAIBusy = false;
      _lastActivity = DateTime.now();
    });
    
    _bus.subscribe("cognition.speaking.start", (e) {
      _isSpeaking = true;
      _lastActivity = DateTime.now();
    });
    _bus.subscribe("cognition.speaking.stop", (e) {
      _isSpeaking = false;
      _lastActivity = DateTime.now();
    });
  }

  Future<void> _signInAnonymously() async {
    try {
      await _auth?.signInAnonymously();
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

    final now = DateTime.now();
    final secondsSinceActivity = now.difference(_lastActivity).inSeconds;

    // REGRA DE OURO REFORÇADA: O sistema precisa estar em repouso TOTAL 
    // (sem IA, sem fala e sem eventos recentes) por pelo menos 3 segundos.
    if (_isAIBusy || _isSpeaking || _bus.pendingCount > 0 || secondsSinceActivity < 3) {
      debugPrint("CloudSync: Sistema ainda instável ou ocupado. Adiado em 10s...");
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
        
        debugPrint("CloudSync: Enviando dados para o Firebase (${updates.length} itens)...");

        if (!kIsWeb && Platform.isWindows) {
          // No Windows, enviamos um por um com pequeno intervalo para máxima estabilidade
          for (var entry in updates.entries) {
            try {
              await _db?.ref("users/$_userId/${entry.key}").set(entry.value).timeout(const Duration(seconds: 5));
              await Future.delayed(const Duration(milliseconds: 200));
            } catch (e) {
              debugPrint("CloudSync Single Update Error: $e");
            }
          }
        } else {
          // No Android/iOS e Web usamos o update atômico que é mais performático
          await _db?.ref("users/$_userId").update(updates).timeout(const Duration(seconds: 15));
        }

        debugPrint("CloudSync: Sincronização concluída.");
      }
    } catch (e) {
      debugPrint("CloudSync Batch Error: $e");
      // Se falhar, as filas já foram limpas para evitar loops de crash
    }
  }

  Future<void> _pullMemoriesFromCloud() async {
    if (_userId == null) return;
    try {
      final episodicSnap = await _db?.ref("users/$_userId/episodic").limitToLast(50).get();
      if (episodicSnap != null && episodicSnap.exists) {
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
