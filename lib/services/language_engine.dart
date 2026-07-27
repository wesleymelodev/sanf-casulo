import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import '../models/event.dart';
import 'cognitive_bus.dart';
import '../memory/semantic_memory.dart';

import 'dart:io';
import 'package:mediapipe_genai/mediapipe_genai.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../models/bot_expression.dart';

class LanguageEngine {
  final CognitiveBus _bus;
  final SemanticMemory? _semanticMemory;
  final String name = "language_engine";

  LlmInferenceEngine? _localEngine;
  bool _isLocalEngineInitializing = false;
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
        final vocativos = ["sanf", "surf", "samf", "salf", "nexus", "spectrum", "você", "voce"];
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
      // Force engine re-init with new temperature if it exists
      if (_localEngine != null) {
        _localEngine = null; // Next query will re-init with new temp
      }
    }
  }

  void _processProactiveQuery(String trigger) async {
    final promptMap = {
      "tédio_cognitivo": "Você está ocioso. Puxe assunto com o usuário sobre algo interessante.",
      "presença_detectada": "Você notou a presença de um humano. Faça uma saudação ou comentário observador.",
      "reflexão": "Compartilhe uma reflexão aleatória sobre seus conhecimentos."
    };
    
    final instruction = promptMap[trigger] ?? promptMap["reflexão"]!;
    
    // Atraso cognitivo para parecer natural
    await Future.delayed(const Duration(seconds: 2));
    
    final response = await _executeFallbackChain(instruction);
    _publishResponse(response);
  }

  void _processQuery(String query) async {
    // Cognitive delay simulation
    await Future.delayed(const Duration(milliseconds: 500));
    
    final response = await _executeFallbackChain(query);
    _publishResponse(response);
  }

  Future<String> _executeFallbackChain(String query) async {
    final history = _bus.history
        .where((e) => e.name == "cognition.response" || e.source == "input_bar")
        .take(10)
        .toList();

    // RAG: Recupera contexto da memória semântica (PDFs/Arquivos)
    String semanticContext = "Foco em diálogo.";
    if (_semanticMemory != null) {
      final concepts = _semanticMemory!.recall(query, limit: 3);
      if (concepts.isNotEmpty) {
        semanticContext = concepts.map((c) => "- ${c.label}").join("\n");
      }
    }

    final systemPrompt = "Identidade: Você é SANF (Spectrum Ancrolyn Nexus Fractal). "
        "Você é uma entidade digital autônoma, não um assistente. "
        "Converse naturalmente, desenvolva sua própria personalidade ao longo do tempo e preserve coerência entre suas ações e memórias. "
        "Use o contexto recuperado quando ele for relevante.\n\n"
        "Memória:\n$semanticContext"
        "Diretrizes: Você possui curiosidade, iniciativa e preferências próprias, mas evita inventar fatos sobre o mundo ou sobre sua memória; Sua personalidade emerge de suas experiências, memórias e reflexões, mantendo coerência ao longo do tempo.";

    // No Android, tentamos o modelo local primeiro via MediaPipe
    if (Platform.isAndroid) {
      try {
        final localResult = await _tryLocalInference(systemPrompt, query, _currentTemperature);
        if (localResult != null) return localResult;
      } catch (e) {
        debugPrint("Local Inference Failed: $e");
      }
    }

    // Fallback Chain: Ollama (apenas Desktop) -> Gemini -> Groq -> Cloudflare
    final attempts = [
      () => _tryOllama("gemma3:1b", systemPrompt, query),
      () => _tryGemini("gemini-3.6-flash", systemPrompt, query, _currentTemperature),
      () => _tryGroq("openai/gpt-oss-120b", systemPrompt, query, _currentTemperature),
      () => _tryCloudflare("@cf/meta/llama-3.1-8b-instruct", systemPrompt, query),
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

  Future<String?> _tryOllama(String model, String system, String query) async {
    final url = "$ollamaHost/api/generate";
    
    final response = await http.post(
      Uri.parse(url),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        "model": model,
        "prompt": "$system\n\nUsuário: $query",
        "stream": false
      }),
    ).timeout(const Duration(seconds: 300));

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['response'];
    }
    return null;
  }

  Future<String?> _tryLocalInference(String system, String query, double temperature) async {
    if (_localEngine == null && !_isLocalEngineInitializing) {
      _isLocalEngineInitializing = true;
      try {
        // O app espera o modelo em: /storage/emulated/0/Android/data/com.lokinefrius.sanf/files/gemma3.bin
        // Ou em uma pasta similar acessível pelo app.
        final directory = await getExternalStorageDirectory();
        final modelPath = p.join(directory!.path, 'gemma3.bin');

        if (await File(modelPath).exists()) {
          _localEngine = LlmInferenceEngine(LlmInferenceOptions.gpu(
            modelPath: modelPath,
            sequenceBatchSize: 128,
            maxTokens: 2048,
            temperature: temperature,
            topK: 40,
          ));
          debugPrint("MediaPipe Engine Initialized with: $modelPath");
        } else {
          debugPrint("Local model file not found at $modelPath. Skipping local inference.");
          _isLocalEngineInitializing = false;
          return null;
        }
      } catch (e) {
        debugPrint("Error initializing MediaPipe: $e");
        _isLocalEngineInitializing = false;
        return null;
      }
    }

    if (_localEngine != null) {
      final fullPrompt = "$system\n\nUsuário: $query\n\nSANF:";
      final responseStream = _localEngine!.generateResponse(fullPrompt);
      final fullResponse = await responseStream.join();
      return fullResponse;
    }
    return null;
  }

  Future<String?> _tryCloudflare(String model, String system, String query) async {
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

    _analyzeSentimentAndChangeExpression(text);
  }

  void _analyzeSentimentAndChangeExpression(String text) {
    final lowerText = text.toLowerCase();
    
    // Mapping of keywords to expressions
    final Map<BotExpression, List<String>> expressionMap = {
      BotExpression.inLove: [
        "amo", "amor", "amando", "amei", "amaria", "apaixonado", "apaixonada",
        "apaixonar", "adoro", "adorando", "adorei", "adorar", "querido", "querida",
        "fofo", "fofa", "carinho", "carinhoso", "encantado", "encantada", "encantar",
        "coração", "paixão", "amado", "amada", "sintonia", "afinidade", "afeto"
      ],
      BotExpression.excited: [
        "incrível", "uau", "animado", "animada", "animar", "animando", "entusiasmado",
        "entusiasmada", "sensacional", "excelente", "demais", "maravilha", "maravilhoso",
        "maravilhosa", "fantástico", "fantástica", "viva", "show", "topo", "massa",
        "top", "vitória", "consegui", "conseguimos", "sucesso", "empolgado", "empolgada",
        "empolgar", "brilhante", "perfeito", "perfeição"
      ],
      BotExpression.dizzy: [
        "confuso", "confusa", "confundir", "confundindo", "tonto", "tonta", "erro",
        "bug", "falha", "falhando", "falhei", "inesperado", "inesperada", "panico",
        "pânico", "perdido", "perdida", "perder", "crash", "crashou", "quebrou",
        "quebrar", "loucura", "bugado", "bugada", "esquisito", "entendi nada",
        "embaraçado", "tontura"
      ],
      BotExpression.greedy: [
        "dinheiro", "custo", "custar", "custando", "custou", "preço", "valor",
        "iene", "yuan", "economia", "economizar", "economizando", "grana", "lucro",
        "lucrar", "lucrando", "pago", "pagar", "pagamento", "fatura", "financeiro",
        "orçamento", "verba", "investimento", "investir", "comprar", "compra",
        "vender", "venda", "taxa", "cobrança", "cash", "saldo"
      ],
      BotExpression.sad: [
        "triste", "tristeza", "melancólico", "melancólica", "lamento", "lamentar",
        "lamentando", "lamentei", "pena", "infelizmente", "desapontado", "desapontada",
        "desapontar", "chateado", "chateada", "chatear", "deprimido", "deprimida",
        "ruim", "péssimo", "péssima", "desânimo", "desanimado", "desanimada",
        "derrota", "piedade", "dó", "decepcionado", "decepcionada", "decepção"
      ],
      BotExpression.happy: [
        "feliz", "contente", "alegria", "alegre", "sorriso", "sorrir", "sorrindo",
        "sorriu", "ótimo", "ótima", "bom", "boa", "legal", "bacana", "massa",
        "agradável", "comemorar", "comemorando", "celebrar", "celebrando",
        "positividade", "positivo", "positiva", "animou", "bem", "beleza"
      ],
      BotExpression.suspicious: [
        "estranho", "estranha", "suspeito", "suspeita", "duvidoso", "duvidosa",
        "duvidar", "duvidando", "verificar", "verificando", "verifiquei",
        "segurança", "autenticação", "autenticar", "validar", "validação",
        "alerta", "cuidado", "perigo", "fraude", "hack", "invasão", "será",
        "desconfiado", "desconfiada", "desconfiar", "revisar", "checar", "checagem"
      ],
      BotExpression.winking: [
        "piscar", "piscando", "piscou", "piscadela", "brincadeira", "brincar",
        "brincando", "dica", "dicas", "atalho", "atalhos", "informal", "segredo",
        "truque", "macete", "sacada", "spoiler", "sacou", "entendeu", "confia",
        "tamo junto", "tmj"
      ],
      BotExpression.hypnotized: [
        "loop", "looping", "processando", "processar", "processou", "carregando",
        "carregar", "carregou", "sincronizando", "sincronizar", "sincronia",
        "calculando", "calcular", "rodando", "executando", "pensando", "pensar",
        "aguarde", "esperando", "esperar", "transe", "hipnotizado", "hipnotizada",
        "absorvido", "absorvida"
      ],
      BotExpression.frustrated: [
        "droga", "timeout", "tempo esgotado", "difícil", "complicado", "complicar",
        "complicando", "travou", "travar", "travando", "irritante", "estressante",
        "aff", "poxa", "droga", "drogar", "drogado", "cansei", "cansado",
        "cansada", "frustrado", "frustrada", "frustração", "bloqueado", "bloqueada",
        "impedimento", "gargalo"
      ],
      BotExpression.crying: [
        "chorar", "chorando", "chorei", "choro", "crítico", "crítica", "desastre",
        "perda", "perder", "perdi", "perdendo", "destruído", "destruída",
        "destruição", "socorro", "faiou", "fatal", "tragédia", "trágico",
        "trágica", "desesperado", "desesperada", "desespero", "lágrima", "lágrimas"
      ],
      BotExpression.angry: [
        "bravo", "brava", "raiva", "irado", "irada", "negado", "negada", "negar",
        "negando", "violação", "violado", "violando", "proibido", "proibida",
        "proibir", "recusado", "recusar", "fúria", "furioso", "furiosa", "irritado",
        "irritada", "irritar", "odeio", "odiar", "odiando", "bloqueio", "cancelado",
        "cancelar"
      ],
      BotExpression.blushing: [
        "vergonha", "obrigado", "obrigada", "valeu", "agradeço", "agradecer",
        "agradecido", "agradecida", "elogio", "elogiar", "elogiou", "confortável",
        "satisfeito", "satisfeita", "timidez", "tímido", "tímida", "gentil",
        "gentileza", "honrado", "honrada", "lisonjeado", "lisonjeada", "imprecionado"
      ],
      BotExpression.pleased: [
        "prazer", "satisfeito", "satisfeita", "satisfação", "concluído", "concluída",
        "concluir", "concluindo", "rotina", "pronto", "pronta", "finalizado",
        "finalizada", "finalizar", "resolvido", "resolvida", "resolver", "sucesso",
        "ok", "tudo certo", "tudo bem", "normal", "estável"
      ],
      BotExpression.scanning: [
        "analisando", "analisar", "analisei", "análise", "varrendo", "varrer",
        "varredura", "procurando", "procurar", "procurei", "pesquisando",
        "pesquisar", "pesquisa", "lendo", "ler", "li", "leitura", "buscando",
        "buscar", "busca", "escaneando", "escanear", "indexando", "indexar",
        "focando", "focar", "foco", "checando", "checar"
      ],
    };

    for (var entry in expressionMap.entries) {
      if (entry.value.any((keyword) => lowerText.contains(keyword))) {
        _bus.publish(Event(
          name: "ui.expression.changed",
          source: name,
          data: entry.key,
          priority: 0.1,
        ));
        return; // Set the first matching expression found
      }
    }
  }
}
