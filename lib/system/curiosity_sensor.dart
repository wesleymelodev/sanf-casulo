import 'dart:async';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:html/parser.dart' show parse;
import '../models/event.dart';
import '../services/cognitive_bus.dart';
import '../core/kernel.dart';

class CuriositySensor extends LifecycleComponent {
  @override
  final String name = "curiosity_sensor";

  final CognitiveBus _bus;
  bool _isSearching = false;
  DateTime _lastSearchTime = DateTime.fromMillisecondsSinceEpoch(0);
  
  // --- Curiosity State ---
  double _curiosityAccumulator = 0.0;
  double _proactivityLevel = 0.6;
  final List<String> _recentTopics = [];
  final Random _random = Random();

  CuriositySensor(this._bus);

  @override
  void initialize() {
    debugPrint("CuriositySensor inicializado.");
    // Ouve solicitações explícitas e também eventos de percepção para "aprender" tópicos
    _bus.subscribe("curiosity.request", handleEvent);
    _bus.subscribe("perception.salient", _collectTopics);
    _bus.subscribe("sensor.vision", _collectTopics);
    _bus.subscribe("system.config.proactivity_changed", (e) {
      _proactivityLevel = (e.data as double);
    });
  }

  void handleEvent(Event event) {
    if (event.name == "curiosity.request" && !_isSearching) {
      final query = event.data.toString();
      _performSearch(query);
    }
  }

  void _collectTopics(Event event) {
    final text = event.data.toString();
    // Extração de tópicos: palavras com mais de 5 letras, ignorando pontuação básica
    final words = text.split(RegExp(r'[^a-zA-Záàâãéèêíïóôõöúç]+'))
        .where((w) => w.length > 5 && !w.contains("http"))
        .take(5);
    
    for (var word in words) {
      final cleanWord = word.toLowerCase();
      if (!_recentTopics.contains(cleanWord)) {
        _recentTopics.add(cleanWord);
        if (_recentTopics.length > 15) _recentTopics.removeAt(0);
      }
    }
  }

  @override
  void update(double deltaTime) {
    if (_isSearching) return;

    // Acumula curiosidade baseado no nível de proatividade
    // Se proactivity for 1.0, acumula 0.01 por segundo (100s para atingir 1.0)
    // Se proactivity for 0.1, acumula 0.001 por segundo (1000s para atingir 1.0)
    _curiosityAccumulator += (0.005 + (0.01 * _proactivityLevel)) * deltaTime;

    // Verifica se "bateu a curiosidade" (entre 0.8 e 1.5 para imprevisibilidade)
    final threshold = 0.8 + (_random.nextDouble() * 0.7);

    if (_curiosityAccumulator >= threshold) {
      _curiosityAccumulator = 0.0; // Reset imediato
      
      if (_recentTopics.isNotEmpty) {
        // Escolha ponderada: 40% de chance de pesquisar algo aleatório se estiver "muito curioso"
        final topic = _recentTopics[_random.nextInt(_recentTopics.length)];
        
        // Formata a busca para ser mais exploratória
        final searchQueries = [
          topic,
          "o que é $topic",
          "curiosidades sobre $topic",
          "novidades $topic 2026",
          "significado de $topic"
        ];
        
        final finalQuery = searchQueries[_random.nextInt(searchQueries.length)];
        
        debugPrint("Curiosity: Spontaneous desire to know about '$finalQuery'");
        _performSearch(finalQuery);
      }
    }
  }

  Future<void> _performSearch(String query) async {
    // 1. Filtro Meta-cognitivo: Ignora perguntas sobre o próprio robô
    final lowerQuery = query.toLowerCase();
    if (lowerQuery.startsWith("você") || 
        lowerQuery.startsWith("voce") || 
        lowerQuery.startsWith("consegue") || 
        lowerQuery.startsWith("quem é")) {
      debugPrint("Ignorando busca meta-cognitiva: $query");
      return;
    }

    // 2. Throttling: Impede buscas muito frequentes (mínimo 30 segundos entre buscas)
    final now = DateTime.now();
    if (now.difference(_lastSearchTime).inSeconds < 30) {
      debugPrint("Busca ignorada por throttling (frequência alta).");
      return;
    }

    _isSearching = true;
    _lastSearchTime = now;
    debugPrint("Buscando na web: '$query'");

    try {
      // Usando uma busca simplificada via DuckDuckGo (HTML ou Lite)
      // Nota: No Flutter nativo, o ideal é usar uma API ou scraper leve
      final response = await http.get(
        Uri.parse("https://duckduckgo.com/html/?q=${Uri.encodeComponent(query)}"),
        headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36'
        },
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final document = parse(response.body);
        
        // Seleciona os containers de resultados do DuckDuckGo HTML Lite
        final results = document.querySelectorAll('.result__body');
        
        if (results.isEmpty) {
          debugPrint("Curiosity: Nenhum resultado textual encontrado na página.");
          return;
        }

        StringBuffer knowledgeBuffer = StringBuffer();
        knowledgeBuffer.writeln("Informações recuperadas da web sobre: '$query':\n");

        // Pega os 3 primeiros resultados para não sobrecarregar o contexto
        for (var i = 0; i < results.length && i < 3; i++) {
          final title = results[i].querySelector('.result__title')?.text.trim() ?? "Sem título";
          final snippet = results[i].querySelector('.result__snippet')?.text.trim() ?? "Sem descrição";
          
          knowledgeBuffer.writeln("- $title: $snippet");
        }

        final extractedKnowledge = knowledgeBuffer.toString();
        
        // Dispara evento de conhecimento real ingerido
        _bus.publish(Event(
          name: "sensor.knowledge_ingested",
          source: name,
          data: extractedKnowledge,
          confidence: 0.8,
          priority: 0.6,
          novelty: 1.0,
          metadata: {
            "query": query, 
            "source_type": "web",
            "engine": "DuckDuckGo HTML"
          }
        ));
        
        debugPrint("Busca concluída e conhecimento REAL injetado.");
      }
    } catch (e) {
      debugPrint("Erro na busca web: $e");
    } finally {
      _isSearching = false;
    }
  }

  @override
  void shutdown() {
    _bus.unsubscribe("curiosity.request", handleEvent);
  }
}
