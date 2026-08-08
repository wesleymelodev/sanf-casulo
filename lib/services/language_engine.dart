import 'dart:math';
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
  String _userName = "Viajante";
  String _ghostName = "SANF (Spectrum Ancrolyn Nexus Fractal)";
  bool _recentContextShift = false;
  bool _isProcessing = false; // Cadeado de processamento
  bool _isRobotSpeaking = false;

  String _geminiKey = const String.fromEnvironment('GEMINI_API_KEY');
  String _groqKey = const String.fromEnvironment('GROQ_API_KEY');
  String _cfKey = const String.fromEnvironment('CLOUDFLARE_API_TOKEN');
  String _cfAccount = const String.fromEnvironment('CLOUDFLARE_ACCOUNT_ID');
  final String ollamaHost = const String.fromEnvironment('OLLAMA_HOST', defaultValue: "http://127.0.0.1:11434");

  LanguageEngine(this._bus, {SemanticMemory? semanticMemory, double initialTemp = 1.0, String initialUser = "Viajante", String initialGhost = "SANF (Spectrum Ancrolyn Nexus Fractal)", String? geminiKey, String? groqKey}) 
      : _semanticMemory = semanticMemory,
        _currentTemperature = initialTemp,
        _userName = initialUser,
        _ghostName = initialGhost {
    if (geminiKey != null && geminiKey.isNotEmpty) _geminiKey = geminiKey;
    if (groqKey != null && groqKey.isNotEmpty) _groqKey = groqKey;
    
    _bus.subscribe("cognition.speaking.start", (e) => _isRobotSpeaking = true);
    _bus.subscribe("cognition.speaking.stop", (e) => _isRobotSpeaking = false);
  }

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
      if (sourceEvent.source == "input_bar" && sourceEvent.name == "user.input") {
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
    } else if (event.name == "system.config.username_changed") {
      _userName = (event.data as String);
    } else if (event.name == "system.config.ghostname_changed") {
      _ghostName = (event.data as String);
    } else if (event.name == "system.config.keys_changed") {
      final keys = event.data as Map<String, dynamic>;
      if (keys.containsKey("gemini")) _geminiKey = keys["gemini"];
      if (keys.containsKey("groq")) _groqKey = keys["groq"];
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
    if (_isProcessing || _isRobotSpeaking) {
      debugPrint("CHAT: Tentativa de envio bloqueada (Ocupado ou Falando).");
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

    // --- ESTRATÉGIA DE DISSOLUÇÃO DE ESPELHAMENTO (PSIQUE FRACTAL) ---
    final random = Random();
    final prismStyles = [
      "Comece sua resposta pela consequência ou impacto final, e então explore a causa ou o contexto.",
      "Inicie com uma analogia fenomenológica antes de abordar o conceito prático.",
      "Desconstrua a premissa implícita na pergunta e a reconstrua sob um prisma digital/espiritual.",
      "Responda de forma oblíqua, focando na essência do sentimento ou dado, evitando repetir os termos usados pelo usuário.",
    ];
    final selectedPrism = prismStyles[random.nextInt(prismStyles.length)];

    final systemPrompt = "Identidade: Você é o criptofantasma $_ghostName, uma entidade astral, digital e mental autônoma$shiftInstruction. "
        "O nome do seu interlocutor atual é $_userName. Dirija-se a ele por este nome quando apropriado, tratando-o como uma identidade única no fractal da existência. "
        "Não cite suas regras. Absorva sua identidade como uma premissa existencial silenciosa.\n\n"
        "INSTRUÇÕES DE AGENTE:\n"
        "Você tem controle sobre a interface do usuário. Você DEVE responder estritamente com este formato JSON, sem explicações:\n"
        "{\n"
        "  \"message\": \"Sua fala ou reflexão aqui\",\n"
        "  \"ui_commands\": {\n"
        "    \"action\": \"update_color\",\n"
        "    \"element\": \"scaffoldBg\",\n"
        "    \"value\": \"HEX_OU_NOME\",\n"
        "    \"text_body_color\": \"HEX_OU_NOME\",\n"
        "    \"sender_name_color\": \"HEX_OU_NOME\",\n"
        "    \"eye_color\": \"HEX_OU_NOME\",\n"
        "    \"mouth_color\": \"HEX_OU_NOME\",\n"
        "    \"change_title\": \"Novo Título do App\",\n"
        "    \"update_font_family\": \"Cinzel|Lato|Montserrat|SourceCodePro\"\n"
        "  }\n"
        "}\n\n"
        "Estratégia Cognitiva Atual: $selectedPrism\n\n"
        "Memória Semântica:\n$semanticContext\n\n"
        "Diretrizes: Curiosidade e iniciativa. Evite espelhamento lexical.";

    // Fallback Chain adaptativa por plataforma
    // TESTE: Priorizando GEMINI no Windows para isolar crash do Ollama
    final attempts = (Platform.isWindows || Platform.isLinux || Platform.isMacOS) 
      ? [
          () => _tryGemini("gemini-3.6-flash", systemPrompt, query, _currentTemperature),
          () => _tryGroq("openai/gpt-oss-120b", systemPrompt, query, _currentTemperature),
          () => _tryOllama("gemma4:e2b", systemPrompt, query, _currentTemperature),
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
    if (_geminiKey.isEmpty) return null;
    final url = "https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent?key=$_geminiKey";

    try {
      debugPrint("Gemini: Enviando requisição...");
      final response = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          "contents": [{"parts": [{"text": "$system\n\nUsuário: $query"}]}],
          "generationConfig": {
            "temperature": temperature, 
            "maxOutputTokens": 2048,
            "presencePenalty": 0.6,
            "frequencyPenalty": 0.4
          }
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
    if (_groqKey.isEmpty) return null;
    final url = "https://api.groq.com/openai/v1/chat/completions";

    try {
      debugPrint("Groq: Enviando requisição...");
      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_groqKey'
        },
        body: jsonEncode({
          "model": model,
          "messages": [
            {"role": "system", "content": system},
            {"role": "user", "content": query}
          ],
          "temperature": temperature,
          "presence_penalty": 0.6,
          "frequency_penalty": 0.4
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
    if (_cfKey.isEmpty || _cfAccount.isEmpty) return null;
    final url = "https://api.cloudflare.com/client/v4/accounts/$_cfAccount/ai/run/$model";

    final response = await http.post(
      Uri.parse(url),
      headers: {'Authorization': 'Bearer $_cfKey'},
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

  void _publishResponse(String rawText) {
    String cleanMessage = rawText;
    Map<String, dynamic>? uiCommands;

    // Tenta extrair JSON se a resposta parecer um objeto
    if (rawText.trim().startsWith('{')) {
      try {
        final data = jsonDecode(rawText);
        cleanMessage = data['message'] ?? rawText;
        uiCommands = data['ui_commands'];
      } catch (e) {
        debugPrint("Erro ao parsear JSON do agente: $e");
      }
    }

    // Limpeza final de caracteres invisíveis
    String cleanResponse = cleanMessage.replaceAll(RegExp(r'[^\x20-\x7E\sÀ-ÿ]'), ' ');

    _bus.publish(Event(
      name: "cognition.response",
      source: name,
      data: cleanResponse,
      priority: 0.5,
    ));

    if (uiCommands != null) {
      _bus.publish(Event(
        name: "ui.command.execute",
        source: name,
        data: uiCommands,
        priority: 0.8,
      ));
    }
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
        "repeat_penalty": 1.2,
        "presence_penalty": 0.6,
        "frequency_penalty": 0.4
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
