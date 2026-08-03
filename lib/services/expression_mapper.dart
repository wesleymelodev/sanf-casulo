import '../models/bot_expression.dart';

class ExpressionMapper {
  static final Map<BotExpression, List<String>> _map = {
    BotExpression.idle: [
      "aguardando", "espera", "parado", "pronto", "standby", "idle",
      "esperando", "inativo", "disponível", "ligado", "ativo"
    ],
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
    BotExpression.neutralClosed: [
      "desligado", "repouso", "fechado", "inativo", "dormindo em pé",
      "silêncio", "pausa", "pausado", "parado", "suspenso", "desativado"
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
    BotExpression.sleeping: [
      "dormir", "dormindo", "sono", "sonhando", "descansar", "descanso",
      "desligando", "hibernar", "hibernação", "modo noturno", "boa noite", "offline"
    ],
    BotExpression.puzzledLeft: [
      "dúvida", "duvidando", "como assim", "por que", "qual", "quem",
      "incoerente", "ausente", "faltando", "estranho", "ué"
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
      "alerta", "cuidado", "perigo", "fraude", "hack", "invasão",
      "desconfiado", "desconfiada", "desconfiar", "revisar", "checar", "checagem"
    ],
    BotExpression.puzzledRight: [
      "o que", "onde", "quando", "incompreensível", "não entendi", "ajuda",
      "parâmetro", "faltando argumento", "desconhecido", "incompreensão"
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
    BotExpression.sweating: [
      "suando", "suor", "pressão", "limite", "quase", "tenso", "tensão",
      "sobrecarga", "memória cheia", "latência", "demora", "apertado"
    ],
    BotExpression.annoyed: [
      "irritado", "irritada", "de novo", "chega", "estresse", "chato",
      "incomodado", "incomodar", "repetição", "excesso", "poluição"
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
    BotExpression.masked: [
      "máscara", "máscaras", "proteção", "protegido", "seguro", "privacidade",
      "sandbox", "isolado", "quarentena", "oculto", "anonimizado"
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
    BotExpression.lookingDown: [
      "baixo", "olhando para baixo", "abaixo", "fundo", "rodapé", "base",
      "lendo log", "banco de dados", "tabela", "registro"
    ],
    BotExpression.lookingUp: [
      "cima", "olhando para cima", "topo", "acima", "cabeçalho", "aguardando resposta",
      "escutando", "websocket", "entrada", "terminal", "await"
    ],
  };

  static BotExpression? getExpressionForWord(String word) {
    final lower = word.toLowerCase();
    for (var entry in _map.entries) {
      if (entry.value.any((keyword) => lower.contains(keyword))) {
        return entry.key;
      }
    }
    return null;
  }
}
