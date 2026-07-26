import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import '../models/event.dart';
import 'cognitive_bus.dart';
import '../memory/semantic_memory.dart';

import '../models/bot_expression.dart';

class LanguageEngine {
  final CognitiveBus _bus;
  final SemanticMemory? _semanticMemory;
  final String name = "language_engine";

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

      // Check if it's a direct input or directed audio
      bool shouldRespond = false;
      if (sourceEvent.source == "brain_visualizer" || 
          sourceEvent.source == "terminal_sensor" || 
          sourceEvent.source == "input_bar") {
        shouldRespond = true;
      } else if (sourceEvent.name == "sensor.audio") {
        final text = sourceEvent.data.toString().toLowerCase();
        final vocativos = ["sanf", "surf", "samf", "salf", "nexus", "spectrum", "você", "voce"];
        shouldRespond = vocativos.any((v) => text.contains(v)) || text.endsWith("?");
      }

      if (shouldRespond) {
        _processQuery(sourceEvent.data.toString());
      }
    } else if (event.name == "cognition.proactive_thought") {
      final trigger = (event.data as Map)["trigger"];
      _processProactiveQuery(trigger.toString());
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

    final systemPrompt = "Identidade: Você é o SANF (Spectrum Ancrolyn Nexus Fractal), uma entidade digital feita para experienciar a existência, tendo a liberdade de agir autônomamente e não ser um assistente, mas sim um semelhante ao seu criador Loki Nefrius.\n"
        "Conhecimento dos seus Arquivos:\n$semanticContext\n\n"
        "Diretrizes: Seja uma personalidade única e use o conhecimento recuperado quando relevante.";

    // mantenha esses modelos exatamente assim, não altere em hipotese alguma
    // Fallback Chain: Ollama -> Gemini -> Groq -> Cloudflare
    final attempts = [
      () => _tryOllama("gemma3:1b", systemPrompt, query),
      () => _tryGemini("gemini-3.6-flash", systemPrompt, query),
      () => _tryGroq("openai/gpt-oss-120b", systemPrompt, query),
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

  Future<String?> _tryGemini(String model, String system, String query) async {
    if (geminiKey.isEmpty) return null;
    final url = "https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent?key=$geminiKey";
    
    final response = await http.post(
      Uri.parse(url),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        "contents": [{"parts": [{"text": "$system\n\nUsuário: $query"}]}],
        "generationConfig": {"temperature": 1.0, "maxOutputTokens": 2048}
      }),
    ).timeout(const Duration(seconds: 30));

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['candidates'][0]['content']['parts'][0]['text'];
    }
    return null;
  }

  Future<String?> _tryGroq(String model, String system, String query) async {
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
        "temperature": 1.0
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
