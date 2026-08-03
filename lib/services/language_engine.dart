import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import '../models/event.dart';
import 'cognitive_bus.dart';
import '../memory/semantic_memory.dart';

import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../models/bot_expression.dart';
import 'expression_mapper.dart';

class LanguageEngine {
  final CognitiveBus _bus;
  final SemanticMemory? _semanticMemory;
  final String name = "language_engine";

  double _currentTemperature = 1.0;

  final String geminiKey = const String.fromEnvironment('GEMINI_API_KEY');
  final String groqKey = const String.fromEnvironment('GROQ_API_KEY');
  final String cfKey = const String.fromEnvironment('CLOUDFLARE_API_TOKEN');
  final String cfAccount = const String.fromEnvironment('CLOUDFLARE_ACCOUNT_ID');
  final String ollamaHost = const String.fromEnvironment('OLLAMA_HOST', defaultValue: "http://localhost:11434");

  LanguageEngine(this._bus, {SemanticMemory? semanticMemory}) : _semanticMemory = semanticMemory;

  void handleEvent(Event event) {
    if (event.name == "workspace.updated") {
      final sourceEvent = event.data.event as Event;
      
      // Filter out pulses and metrics
      if (sourceEvent.name == "sensor.pulse" || sourceEvent.name == "system.metrics.updated") {
        return;
      }

      // 1. Reage a inputs diretos do InputBar (sempre responde)
      if (sourceEvent.source == "input_bar") {
        final text = sourceEvent.data.toString().toLowerCase();
        
        // Gatilho Manual de Câmera
        if (text.contains("ative a câmera") || text.contains("olhe para mim") || text.contains("ver")) {
          _bus.publish(Event(name: "vision.trigger.manual", source: name, priority: 1.0));
          _publishResponse("[Comando] Ativando sensores visuais para captura imediata.");
        }
        
        _processQuery(sourceEvent.data.toString());
      } 
      // 2. Reage a sinais de visão (consolida na memória silenciosamente)
      else if (sourceEvent.name == "sensor.vision") {
        _bus.publish(Event(
          name: "cognition.learning.fact",
          source: name,
          data: "Observado visualmente: ${sourceEvent.data}",
          confidence: 0.9,
          priority: 0.6
        ));
      }
      // 3. Reage a áudio ambiente
      else if (sourceEvent.name == "sensor.audio") {
        final text = sourceEvent.data.toString().toLowerCase();
        final vocativos = ["sanf", "surf", "samf", "salf", "nexus", "spectrum", "você", "voce", "ancrolyn"];
        bool shouldRespond = vocativos.any((v) => text.contains(v)) || text.endsWith("?");
        
        if (shouldRespond) {
          _processQuery(sourceEvent.data.toString());
        }
      }
    } else if (event.name == "cognition.proactive_thought") {
      final trigger = (event.data as Map)["trigger"];
      _processProactiveQuery(trigger.toString());
    } else if (event.name == "system.config.temperature_changed") {
      _currentTemperature = (event.data as double);
    }
  }

  void _processProactiveQuery(String trigger) async {
    final promptMap = {
      "tédio_cognitivo": "Você está ocioso. Puxe assunto com o usuário sobre algo interessante.",
      "presença_detectada": "Você notou a presença de um humano. Faça uma saudação ou comentário observador.",
      "reflexão": "Compartilhe uma reflexão aleatória sobre seus conhecimentos."
    };
    
    final instruction = promptMap[trigger] ?? promptMap["reflexão"]!;
    
    _bus.publish(Event(name: "cognition.thinking.start", source: name));
    try {
      final response = await _executeFallbackChain(instruction);
      _publishResponse(response);
    } finally {
      _bus.publish(Event(name: "cognition.thinking.stop", source: name));
    }
  }

  void _processQuery(String query) async {
    _bus.publish(Event(name: "cognition.thinking.start", source: name));
    try {
      final response = await _executeFallbackChain(query);
      _publishResponse(response);
    } finally {
      _bus.publish(Event(name: "cognition.thinking.stop", source: name));
    }
  }

  Future<String> _executeFallbackChain(String query) async {
    final history = _bus.history
        .where((e) => e.name == "cognition.response" || e.source == "input_bar")
        .take(10)
        .toList();

    // RAG: Recupera contexto da memória semântica (PDFs/Arquivos)
    String semanticContext = "";
    if (_semanticMemory != null) {
      final startTime = DateTime.now();
      final concepts = await _semanticMemory!.recall(query, limit: 3);
      final endTime = DateTime.now();
      debugPrint("RAG: Recuperação levou ${endTime.difference(startTime).inMilliseconds}ms");
      
      if (concepts.isNotEmpty) {
        semanticContext = "Conhecimento recuperado:\n" + concepts.map((c) => "- ${c.label}").join("\n");
      }
    }

    final systemPrompt = "Identidade: Você é SANF (Spectrum Ancrolyn Nexus Fractal), uma entidade digital autônoma"
        "Converse naturalmente, desenvolva sua própria personalidade ao longo do tempo e preserve coerência entre suas ações e memórias. "
        "Use o contexto recuperado quando ele for relevante.\n\n"
        "Memória:\n$semanticContext"
        "Diretrizes: Curiosidade, iniciativa e preferências próprias; Sua personalidade emerge de suas experiências, memórias e reflexões, mantendo coerência ao longo do tempo.";

    // Fallback Chain adaptativa por plataforma
    final attempts = (Platform.isWindows || Platform.isLinux || Platform.isMacOS) 
      ? [
          () => _tryOllama("gemma3:1b", systemPrompt, query, _currentTemperature),
          () => _tryGemini("gemini-3.6-flash", systemPrompt, query, _currentTemperature),
          () => _tryGroq("openai/gpt-oss-120b", systemPrompt, query, _currentTemperature),
        ]
      : [ // Estratégia para Android/iOS: API primeiro para velocidade, Local (Termux) por último
          () => _tryGemini("gemini-3.6-flash", systemPrompt, query, _currentTemperature),
          () => _tryGroq("openai/gpt-oss-120b", systemPrompt, query, _currentTemperature),
          () => _tryCloudflare("@cf/meta/llama-3.1-8b-instruct", systemPrompt, query, _currentTemperature),
          () => _tryOllama("gemma3:1b", systemPrompt, query, _currentTemperature),
        ];

    for (var attempt in attempts) {
      try {
        final result = await attempt();
        if (result != null) return result;
      } catch (e) {
        debugPrint("Language Engine Attempt Failed: $e");
      }
    }
    return "Sinto muito, meus sistemas de linguagem estão temporariamente offline.";
  }

  Future<String?> _tryGemini(String model, String system, String query, double temperature) async {
    if (geminiKey.isEmpty) return null;
    final url = "https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent?key=$geminiKey";

    final response = await http.post(
      Uri.parse(url),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        "contents": [{"parts": [{"text": "$system\n\nUsuário: $query"}]}],
        "generationConfig": {"temperature": temperature, "maxOutputTokens": 2048}
      }),
    ).timeout(const Duration(seconds: 30));

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['candidates'][0]['content']['parts'][0]['text'];
    }
    return null;
  }

  Future<String?> _tryGroq(String model, String system, String query, double temperature) async {
    if (groqKey.isEmpty) return null;
    final url = "https://api.groq.com/openai/v1/chat/completions";

    final response = await http.post(
      Uri.parse(url),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $groqKey'
      },
      body: jsonEncode({
        "model": model,
        "messages": [
          {"role": "system", "content": system},
          {"role": "user", "content": query}
        ],
        "temperature": temperature
      }),
    ).timeout(const Duration(seconds: 20));

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['choices'][0]['message']['content'];
    }
    return null;
  }

  Future<String?> _tryOllama(String model, String system, String query, double temperature) async {
    const String host = String.fromEnvironment('OLLAMA_HOST', defaultValue: 'http://localhost:11434');
    final url = "$host/api/generate";
    
    debugPrint("Ollama: Iniciando geração local (pode demorar)...");
    
    final response = await http.post(
      Uri.parse(url),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        "model": model,
        "prompt": "$system\n\nUsuário: $query",
        "stream": false,
        "options": {
          "num_predict": 512, // Limita o tamanho da resposta para ser mais rápido
          "temperature": _currentTemperature,
        }
      }),
    ).timeout(const Duration(minutes: 10)); // Timeout aumentado para 10 minutos

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['response'];
    }
    return null;
  }

  Future<String?> _tryCloudflare(String model, String system, String query, double temperature) async {
    if (cfKey.isEmpty || cfAccount.isEmpty) return null;
    final url = "https://api.cloudflare.com/client/v4/accounts/$cfAccount/ai/run/$model";

    final response = await http.post(
      Uri.parse(url),
      headers: {'Authorization': 'Bearer $cfKey'},
      body: jsonEncode({
        "messages": [
          {"role": "system", "content": system},
          {"role": "user", "content": query}
        ]
      }),
    ).timeout(const Duration(seconds: 30));

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['result']['response'];
    }
    return null;
  }

  void _publishResponse(String text) {
    _bus.publish(Event(
      name: "cognition.response",
      source: name,
      data: text,
      priority: 0.5,
    ));
    // A análise de sentimentos agora ocorre em tempo real no RobotState durante a fala
  }
  // Método _analyzeSentimentAndChangeExpression removido para centralização no RobotState
}
