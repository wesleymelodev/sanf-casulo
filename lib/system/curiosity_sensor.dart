import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:html/parser.dart' show parse;
import 'package:html/dom.dart';
import '../models/event.dart';
import '../services/cognitive_bus.dart';
import '../core/kernel.dart';

class CuriositySensor extends LifecycleComponent {
  @override
  final String name = "curiosity_sensor";

  final CognitiveBus _bus;
  bool _isSearching = false;
  DateTime _lastSearchTime = DateTime.fromMillisecondsSinceEpoch(0);

  CuriositySensor(this._bus);

  @override
  void initialize() {
    debugPrint("CuriositySensor inicializado.");
    // Ouve apenas solicitações explícitas de busca
    _bus.subscribe("curiosity.request", handleEvent);
  }

  void handleEvent(Event event) {
    if (event.name == "curiosity.request" && !_isSearching) {
      final query = event.data.toString();
      _performSearch(query);
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
  void update(double deltaTime) {}

  @override
  void shutdown() {
    _bus.unsubscribe("curiosity.request", handleEvent);
  }
}
