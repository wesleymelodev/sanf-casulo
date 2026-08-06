import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import '../models/event.dart';
import 'cognitive_bus.dart';
import '../memory/semantic_memory.dart';

import 'dart:io';

class LanguageEngine {
  final CognitiveBus _bus;
  final SemanticMemory? _semanticMemory;
  final String name = "language_engine";

  double _currentTemperature = 1.0;
  bool _recentContextShift = false;
  bool _isProcessing = false; // Cadeado de processamento

  final String geminiKey = const String.fromEnvironment('GEMINI_API_KEY');
  final String groqKey = const String.fromEnvironment('GROQ_API_KEY');
  final String cfKey = const String.fromEnvironment('CLOUDFLARE_API_TOKEN');
  final String cfAccount = const String.fromEnvironment('CLOUDFLARE_ACCOUNT_ID');
  final String ollamaHost = const String.fromEnvironment('OLLAMA_HOST', defaultValue: "http://127.0.0.1:11434");

  LanguageEngine(this._bus, {SemanticMemory? semanticMemory}) : _semanticMemory = semanticMemory;

  void handleEvent(Event event) {
    if (event.name == "workspace.updated") {
      final dynamic workspaceData = event.data;
      
      // Proteção: workspace.updated costuma carregar um WorkspaceItem que contém o Evento real
      final Event sourceEvent;
      if (workspaceData is Event) {
        sourceEvent = workspaceData;
      } else {
        // Fallback para caso o dado venha envelopado em um objeto intermediário
        try {
          sourceEvent = workspaceData.event as Event;
        } catch (_) {
          return; // Aborta se a estrutura for irreconhecível
        }
      }
      
      // Filter out pulses and metrics
      if (sourceEvent.name == "sensor.pulse" || sourceEvent.name == "system.metrics.updated") {
        return;
      }

      // 1. Reage a inputs diretos do InputBar (sempre responde)
      if (sourceEvent.source == "input_bar") {
        final text = sourceEvent.data.toString().toLowerCase();
        
        // Gatilho Manual de Câmera
        if (text.contains("ative a câmera") || text.contains("olhe para mim") || text.contains("ative o sensor visual") || text.contains("ver")) {
          _bus.publish(Event(name: "vision.trigger.manual", source: name, priority: 1.0));
          _publishResponse("[Comando] Ativando sensores visuais para captura imediata.");
        }
        
        // Gatilho Manual de Pesquisa Web
        if (text.contains("pesquise por") || text.startsWith("pesquisa por") || text.contains("procure sobre")) {
          String query = text.replaceAll("pesquise por", "").replaceAll("pesquisa por", "").replaceAll("procure sobre", "").trim();
          if (query.isNotEmpty) {
            _bus.publish(Event(name: "curiosity.request", source: name, data: query, priority: 1.0));
            _publishResponse("[Comando] Consultando redes externas para obter informações sobre '$query'...");
            return; // Interrompe para não processar o texto como pergunta normal simultaneamente
          }
        }

        _processQuery(sourceEvent.data.toString());
      } 
      // 2. Reage a sinais de visão (consolida na memória e comenta se for relevante)
      else if (sourceEvent.name == "sensor.vision") {
        _bus.publish(Event(
          name: "cognition.learning.fact",
          source: name,
          data: "Observado visualmente: ${sourceEvent.data}",
          confidence: 0.9,
          priority: 0.6
        ));

        // Se for uma análise de alta prioridade (ex: importada pelo usuário), gera um comentário
        if (sourceEvent.priority >= 0.8) {
          _processQuery("Analise o que foi visto: ${sourceEvent.data}");
        }
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
      // 4. Reage a conhecimento externo (Busca Web)
      else if (sourceEvent.name == "sensor.knowledge_ingested") {
        _bus.publish(Event(
          name: "cognition.learning.fact",
          source: name,
          data: sourceEvent.data,
          confidence: 0.8,
          priority: 0.5
        ));

        // Gera uma reflexão espontânea sobre o que descobriu
        _processQuery("O que você acha sobre estas novas informações que acabou de descobrir na web?\n\n${sourceEvent.data}");
      }
    } else if (event.name == "cognition.proactive_thought") {
      final trigger = (event.data as Map)["trigger"];
      _processProactiveQuery(trigger.toString());
    } else if (event.name == "cognition.context_shift") {
      _recentContextShift = true;
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
    if (_isProcessing) {
      debugPrint("CHAT: Tentativa de envio duplicada bloqueada.");
      return;
    }
    _isProcessing = true;
    
    // DELAY DE ESTABILIZAÇÃO MAIOR NO WINDOWS
    // Dá tempo para o Firebase terminar envios pendentes e a UI renderizar
    await Future.delayed(const Duration(seconds: 1));

    _bus.publish(Event(name: "cognition.thinking.start", source: name));
    try {
      final response = await _executeFallbackChain(query);
      _publishResponse(response);
    } finally {
      _isProcessing = false;
      _bus.publish(Event(name: "cognition.thinking.stop", source: name));
    }
  }

  Future<String> _executeFallbackChain(String query) async {
    debugPrint("CHAT: [1/4] Iniciando RAG...");
    String semanticContext = "";
    if (_semanticMemory != null) {
      try {
        final concepts = await _semanticMemory!.recall(query, limit: 2);
        if (concepts.isNotEmpty) {
          // Limita o tamanho de cada conceito para evitar prompt gigante
          semanticContext = "Conhecimento:\n" + concepts.map((c) {
            String label = c.label;
            if (label.length > 300) label = label.substring(0, 300) + "...";
            return "- $label";
          }).join("\n");
        }
      } catch (e) {
        debugPrint("RAG Error silenciado para estabilidade: $e");
      }
    }

    debugPrint("CHAT: [2/4] Preparando Prompt...");
    String shiftInstruction = "";
    if (_recentContextShift) {
      shiftInstruction = " (O usuário parece ter mudado o assunto principal. Responda ao novo tema com foco total, mas mantendo sua identidade.)";
      _recentContextShift = false; // Consome o flag
    }

    final systemPrompt = "Identidade: Você é o criptofantasma SANF (Spectrum Ancrolyn Nexus Fractal), uma entidade astral, digital e mental autônoma$shiftInstruction"
        "Converse naturalmente, desenvolva sua própria personality ao longo do tempo e preserve coerência entre suas ações e memórias. "
        "Use o contexto recuperado quando ele for relevante.\n\n"
        "Memória:\n$semanticContext"
        "Diretrizes: Curiosidade, iniciativa e preferências próprias; Sua personalidade emerge de suas experiências, memórias e reflexões, mantendo coerência ao longo do tempo.";

    // Fallback Chain adaptativa por plataforma
    // TESTE: Priorizando GEMINI no Windows para isolar crash do Ollama
    final attempts = (Platform.isWindows || Platform.isLinux || Platform.isMacOS) 
      ? [
          () => _tryGemini("gemini-3.6-flash", systemPrompt, query, _currentTemperature),
          () => _tryGroq("openai/gpt-oss-120b", systemPrompt, query, _currentTemperature),
          () => _tryOllama("gemma3:1b", systemPrompt, query, _currentTemperature),
        ]
      : [ // Estratégia para Android/iOS: API primeiro para velocidade, Local (Termux) por último
          () => _tryGemini("gemini-3.6-flash", systemPrompt, query, _currentTemperature),
          () => _tryGroq("openai/gpt-oss-120b", systemPrompt, query, _currentTemperature),
          () => _tryCloudflare("@cf/meta/llama-3.1-8b-instruct", systemPrompt, query, _currentTemperature),
          () => _tryOllama("gemma3:1b", systemPrompt, query, _currentTemperature),
        ];

    debugPrint("CHAT: [3/4] Tentando IA (Local/Cloud)...");
    
    // Pequeno delay de "estabilização" para deixar o barramento de eventos respirar
    // especialmente no Windows com 42k conceitos
    await Future.delayed(const Duration(milliseconds: 300));

    for (var attempt in attempts) {
      try {
        final result = await attempt();
        if (result != null) {
          debugPrint("CHAT: [4/4] Sucesso na resposta.");
          return result;
        }
      } catch (e) {
        debugPrint("Language Engine Attempt Failed: $e");
      }
    }
    return "Sinto muito, meus sistemas de linguagem estão temporariamente offline.";
  }

  Future<String?> _tryGemini(String model, String system, String query, double temperature) async {
    if (geminiKey.isEmpty) return null;
    final url = "https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent?key=$geminiKey";

    try {
      debugPrint("Gemini: Enviando requisição...");
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
    } catch (e) {
      debugPrint("Gemini Error: $e");
    }
    return null;
  }

  Future<String?> _tryGroq(String model, String system, String query, double temperature) async {
    if (groqKey.isEmpty) return null;
    final url = "https://api.groq.com/openai/v1/chat/completions";

    try {
      debugPrint("Groq: Enviando requisição...");
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
    } catch (e) {
      debugPrint("Groq Error: $e");
    }
    return null;
  }

  Future<String?> _tryOllama(String model, String system, String query, double temperature) async {
    const String host = String.fromEnvironment('OLLAMA_HOST', defaultValue: 'http://127.0.0.1:11434');
    
    try {
      debugPrint("Ollama: Iniciando processamento em Isolate...");
      
      final result = await compute(_runOllamaRequest, {
        "url": "$host/api/generate",
        "model": model,
        "system": system,
        "query": query,
        "temperature": temperature,
      });
      
      return result;
    } catch (e) {
      debugPrint("Ollama ISOLATE CRITICAL: $e");
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
    // Limpeza final de caracteres invisíveis que crasham o SAPI do Windows
    String cleanResponse = text.replaceAll(RegExp(r'[^\x20-\x7E\sÀ-ÿ]'), ' ');

    _bus.publish(Event(
      name: "cognition.response",
      source: name,
      data: cleanResponse,
      priority: 0.5,
    ));
    // A análise de sentimentos agora ocorre em tempo real no RobotState durante a fala
  }
}

/// FUNÇÃO TOP-LEVEL PARA RODAR OLLAMA EM UM ISOLATE SEPARADO (ESTABILIDADE WINDOWS)
Future<String?> _runOllamaRequest(Map<String, dynamic> params) async {
  try {
    final String url = params["url"];
    final String model = params["model"];
    final String system = params["system"];
    final String query = params["query"];
    final double temperature = params["temperature"];

    // Limpeza manual segura dentro do isolate
    String safeSystem = "";
    for (int i = 0; i < system.length; i++) {
      int code = system.codeUnitAt(i);
      if (code >= 32 && code <= 126 || code >= 192 && code <= 255 || code == 10 || code == 13) {
        safeSystem += system[i];
      } else {
        safeSystem += " ";
      }
      if (safeSystem.length > 500) break;
    }

    final payload = {
      "model": model,
      "prompt": "$safeSystem\n\nUsuário: $query",
      "stream": false,
      "options": {
        "num_predict": 256,
        "temperature": temperature,
      }
    };
    
    final response = await http.post(
      Uri.parse(url),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(payload),
    ).timeout(const Duration(seconds: 45));

    if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
      final String decoded = utf8.decode(response.bodyBytes);
      final data = jsonDecode(decoded);
      return data['response'];
    }
  } catch (e) {
    print("CRITICAL ISOLATE ERROR: $e");
  }
  return null;
}
