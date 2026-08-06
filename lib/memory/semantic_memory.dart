import 'dart:io';

import 'package:hive/hive.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../models/event.dart';
import '../services/cognitive_bus.dart';
import '../core/kernel.dart';
import '../core/config.dart';
import 'episodic_memory.dart';

class SemanticConcept {
  final String identifier;
  final String label;
  int evidenceCount;
  double confidence;
  DateTime lastConfirmedAt;
  bool isProtected; // Flag de proteção
  bool isGarbage;   // Flag para priorizar exclusão

  SemanticConcept({
    required this.identifier,
    required this.label,
    required this.evidenceCount,
    required this.confidence,
    required this.lastConfirmedAt,
    this.isProtected = false,
    this.isGarbage = false,
  });

  Map<String, dynamic> toRawMap() {
    return {
      'identifier': identifier,
      'label': label,
      'evidence_count': evidenceCount,
      'confidence': confidence,
      'last_confirmed_at': lastConfirmedAt.toIso8601String(),
      'is_protected': isProtected,
      'is_garbage': isGarbage,
    };
  }
}

class SemanticMemory extends LifecycleComponent {
  @override
  final String name = "semantic_memory";

  final CognitiveBus _bus;
  final SemanticMemoryConfig _config;
  late Box _box;
  final Map<String, SemanticConcept> _concepts = {};
  
  bool _isPruning = false;
  static const int maxConceptLimit = 10000; // Teto para evitar crash no Windows

  SemanticMemory(this._bus, {SemanticMemoryConfig? config})
      : _config = config ?? SemanticMemoryConfig();

  @override
  void initialize() async {
    _box = await Hive.openBox('semantic_memory_store');
    
    // Recovery
    try {
       refreshActiveMemory();
    } catch (e) {
      print("Semantic Box corrupted, clearing...");
      await _box.clear();
    }
    
    // GATILHO DE FAXINA NO BOOT: Se a base estiver inchada, limpa logo após abrir
    // AUMENTADO PARA 120s PARA EVITAR QUALQUER CONFLITO COM O BOOT/CHAT INICIAL
    if (_box.length > maxConceptLimit) {
      Future.delayed(const Duration(seconds: 120), () => _runSelectiveForget());
    }
    
    _bus.subscribe("memory.episodic.stored", handleEvent);
  }

  /// Recarrega o mapa de conceitos em tempo real a partir do disco de forma otimizada
  void refreshActiveMemory() {
    _concepts.clear();
    
    final int totalKeys = _box.length;
    if (totalKeys > 2000) {
      debugPrint("SemanticMemory: Base massiva detectada ($totalKeys itens). Carregando apenas o núcleo ativo.");
      // Pega as últimas 2000 chaves sem converter tudo para lista primeiro
      if (!Platform.isWindows) {
        for (int i = totalKeys - 1; i >= totalKeys - 2000; i--) {
          final key = _box.keyAt(i);
          _loadSingleConcept(key);
        }
      }
    } else {
      for (var key in _box.keys) {
        _loadSingleConcept(key);
      }
    }
    debugPrint("SemanticMemory: ${_concepts.length} conceitos ativos na consciência.");
  }

  void _loadSingleConcept(dynamic key) {
    final rawData = _box.get(key);
    if (rawData == null) return;
    final data = Map<String, dynamic>.from(rawData);
    final concept = SemanticConcept(
      identifier: data['identifier'],
      label: data['label'],
      evidenceCount: data['evidence_count'],
      confidence: data['confidence'],
      lastConfirmedAt: DateTime.parse(data['last_confirmed_at']),
      isProtected: data['is_protected'] ?? false,
      isGarbage: data['is_garbage'] ?? false,
    );
    _concepts[concept.identifier] = concept;
  }

  void handleEvent(Event event) {
    if (event.name != "memory.episodic.stored" || event.data is! Episode) return;
    
    final Episode episode = event.data;
    
    // FILTRO SEMÂNTICO: Consolida fatos de aprendizado. 
    // Diálogos são ignorados no Windows para evitar crash de I/O em base massiva.
    bool shouldIndex = episode.event.name.contains("learning.fact");
    if (!shouldIndex && !Platform.isWindows) {
      shouldIndex = episode.event.name.contains("user.input") || 
                    episode.event.name.contains("cognition.response");
    }

    if (!shouldIndex) return;

    final identity = _conceptIdentity(episode.event);
    final id = sha256.convert(utf8.encode(identity.item1)).toString();
    final label = identity.item2;

    // Detecta comando de proteção ou descarte
    final String rawText = episode.event.data.toString().toLowerCase();
    
    bool shouldProtect = rawText.startsWith("lembre-se") ||
                         rawText.startsWith("grave isso") ||
                         rawText.startsWith("memorize isso");
                         
    bool shouldDiscard = rawText.startsWith("delete isso") ||
                         rawText.startsWith("esqueça isso") ||
                         rawText.startsWith("remova isso");

    final existing = _concepts[id];
    final evidenceCount = (existing?.evidenceCount ?? 0) + 1;
    final prevConfidence = existing?.confidence ?? 0.0;
    final confidence = shouldDiscard ? 0.0 : 1.0 - (1.0 - prevConfidence) * (1.0 - episode.event.confidence);

    final concept = SemanticConcept(
      identifier: id,
      label: label,
      evidenceCount: evidenceCount,
      confidence: confidence,
      lastConfirmedAt: DateTime.now(),
      isProtected: (existing?.isProtected ?? false) || shouldProtect,
      isGarbage: (existing?.isGarbage ?? false) || shouldDiscard,
    );

    _concepts[id] = concept;
    _box.put(id, concept.toRawMap());

    // Gatilho de Memória Seletiva (GC Cognitivo)
    if (_box.length > maxConceptLimit && !_isPruning) {
      _runSelectiveForget();
    }

    if (evidenceCount >= _config.minimumEvidence) {
      _bus.publish(Event(
        name: "memory.semantic.consolidated",
        source: name,
        data: concept,
        confidence: confidence,
        novelty: 0.0,
        priority: confidence,
      ));
    }
  }

  Future<List<SemanticConcept>> recall(String query, {int limit = 3}) async {
    if (_concepts.isEmpty) return [];

    final terms = query.toLowerCase().split(RegExp(r'\W+')).where((t) => t.length > 3).toSet();
    if (terms.isEmpty) return [];

    // Offload search and ranking to a background isolate to keep UI thread fluid on Windows
    return await compute(_backgroundRecall, _RecallPayload(_concepts.values.toList(), terms, limit));
  }

  static List<SemanticConcept> _backgroundRecall(_RecallPayload payload) {
    final List<SemanticConcept> candidates = [];
    
    for (var concept in payload.concepts) {
      if (payload.terms.any((term) => concept.label.toLowerCase().contains(term))) {
        candidates.add(concept);
      }
      if (candidates.length >= 50) break;
    }

    if (candidates.isEmpty) return [];

    candidates.sort((a, b) {
      double scoreA = _staticCalculateRelevance(a, payload.terms);
      double scoreB = _staticCalculateRelevance(b, payload.terms);
      return scoreB.compareTo(scoreA);
    });

    return candidates.take(payload.limit).toList();
  }

  /// Algoritmo de Esquecimento Seletivo: Remove o que é irrelevante ou pouco reforçado
  Future<void> _runSelectiveForget() async {
    if (_isPruning) return;
    _isPruning = true;
    debugPrint("SemanticMemory: Iniciando Pruning Cognitivo (Faxina de Boot)...");

    try {
      final int totalItems = _box.length;
      final int targetSize = maxConceptLimit;
      
      // 1. Coleta apenas os metadados essenciais para economizar RAM
      final List<MapEntry<dynamic, double>> scores = [];
      
      for (var key in _box.keys) {
        final v = _box.get(key);
        if (v == null) continue;
        
        // Critério de Importância simplificado: Frequência + Confiança
        double evidence = (v['evidence_count'] ?? 0).toDouble();
        double confidence = (v['confidence'] ?? 0.0).toDouble();
        bool isProtected = v['is_protected'] ?? false;
        bool isGarbage = v['is_garbage'] ?? false;

        // Score de decisão: Lixo vai pra -999k, Protegido pra +999k
        double score = isProtected ? 999999.0 : 
                       isGarbage ? -999999.0 : 
                       (evidence * 0.5) + (confidence * 0.5);
        
        scores.add(MapEntry(key, score));
        
        // Pequena pausa a cada 1000 itens para o Windows não achar que o app travou
        if (scores.length % 1000 == 0) {
          await Future.delayed(const Duration(milliseconds: 10));
        }
      }

      // 2. Ordena por relevância (piores primeiro)
      scores.sort((a, b) => a.value.compareTo(b.value));

      // 3. Remove o excesso (de 42k para 10k)
      int removeCount = totalItems - targetSize;
      if (removeCount <= 0) removeCount = (totalItems * 0.2).toInt();

      debugPrint("SemanticMemory: Deletando $removeCount itens irrelevantes...");
      
      for (int i = 0; i < removeCount; i++) {
        final key = scores[i].key;
        await _box.delete(key);
        _concepts.remove(key);
        
        if (i % 500 == 0) {
          await Future.delayed(const Duration(milliseconds: 5));
        }
      }

      debugPrint("SemanticMemory: Faxina concluída. Memória otimizada para $targetSize itens.");
      refreshActiveMemory(); // Recarrega a consciência com os dados limpos
    } catch (e) {
      debugPrint("SemanticMemory Error no GC: $e");
    } finally {
      _isPruning = false;
    }
  }

  static double _staticCalculateRelevance(SemanticConcept concept, Set<String> queryTerms) {
    if (queryTerms.isEmpty) return concept.confidence;
    
    final conceptTerms = concept.label.toLowerCase().split(RegExp(r'\W+')).toSet();
    final intersection = queryTerms.intersection(conceptTerms);
    
    double overlap = intersection.length / (queryTerms.isEmpty ? 1 : queryTerms.length);
    double evidenceFactor = (concept.evidenceCount / 5).clamp(0.0, 1.0);
    
    return (0.55 * overlap) + (0.30 * concept.confidence) + (0.15 * evidenceFactor);
  }

  Tuple2<String, String> _conceptIdentity(Event event) {
    String label = event.data?.toString() ?? event.name;
    String normalized = label.toLowerCase().replaceAll(RegExp(r'[^\w\s]'), '');
    return Tuple2("${event.name}:$normalized", label);
  }

  @override
  void update(double deltaTime) {}

  @override
  void shutdown() {
    _bus.unsubscribe("memory.episodic.stored", handleEvent);
  }
}

class Tuple2<T1, T2> {
  final T1 item1;
  final T2 item2;
  Tuple2(this.item1, this.item2);
}

class _RecallPayload {
  final List<SemanticConcept> concepts;
  final Set<String> terms;
  final int limit;
  _RecallPayload(this.concepts, this.terms, this.limit);
}
