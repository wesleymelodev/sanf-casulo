import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import '../services/websocket_service.dart';
import '../services/api_service.dart';

class RobotState extends ChangeNotifier {
  double energy = 1.0;
  bool isAlert = false;
  double cognitiveLoad = 0.0;
  String homeostaticMode = "Equilibrado";
  String attentionFocus = "Nenhum";
  bool isSpeaking = false;
  bool isListening = false;
  List<Map<String, String>> chatHistory = [];

  late WebSocketService _wsService;
  final ApiService _apiService = ApiService();
  final SpeechToText _speechToText = SpeechToText();
  bool _speechEnabled = false;

  RobotState() {
    _wsService = WebSocketService(onMessage: _handleWebSocketMessage);
    _wsService.connect();
    _initSpeech();
  }

  void _initSpeech() async {
    _speechEnabled = await _speechToText.initialize(
      onError: (error) => debugPrint("Speech Error: $error"),
      onStatus: (status) {
        debugPrint("Speech Status: $status");
        isListening = status == 'listening';
        notifyListeners();
      },
    );
  }

  void toggleListening() async {
    if (!_speechEnabled) return;

    if (isListening) {
      await _speechToText.stop();
    } else {
      await _speechToText.listen(
        onResult: (result) {
          if (result.finalResult) {
            sendMessage(result.recognizedWords);
          }
        },
        localeId: 'pt_BR', // Targeted for the project language
      );
    }
  }

  void _handleWebSocketMessage(dynamic message) {
    try {
      // 1. Decodifica a mensagem JSON vinda do Python
      final Map<String, dynamic> response = jsonDecode(message);

      // 2. No Python, usamos a chave "name" para o tipo do evento
      final String eventName = response['name'] ?? '';

      // 3. No Python, o conteúdo está na chave "data"
      final dynamic rawData = response['data'];

      debugPrint("Recebido evento: $eventName");

      switch (eventName) {
        case 'system.homeostasis.changed':
          if (rawData is Map) {
            // O Python envia 'balanced', 'protective', etc.
            String mode = rawData['mode']?.toString() ?? "balanced";

            // Tradução simples para o seu StatusPanel (ou use os termos em inglês lá)
            if (mode == 'balanced') homeostaticMode = "Equilibrado";
            else if (mode == 'protective') homeostaticMode = "Protetor";
            else if (mode == 'restorative') homeostaticMode = "Regenerativo";
            else homeostaticMode = mode;

            // No Python, os valores já são 0.0 a 1.0
            energy = (rawData['energy'] ?? 1.0).toDouble();
            cognitiveLoad = (rawData['cognitive_load'] ?? 0.0).toDouble();

            debugPrint("Homeostase atualizada: Energia $energy, Modo $homeostaticMode");
          }
          notifyListeners();
          break;

        case 'attention.focus.changed':
          if (rawData is Map) {
            // No Python, o dado está em data -> item -> event -> data
            var focusData = rawData['item']?['event']?['data'];
            attentionFocus = focusData?.toString() ?? "Em reflexão";

            // Se for um foco de alta prioridade (> 0.8), marca como alerta
            double priority = (rawData['item']?['event']?['priority'] ?? 0.0).toDouble();
            isAlert = priority > 0.8;
          }
          notifyListeners();
          break;

        case 'cognition.response':
        // O dado aqui é a string direta da resposta
          String text = rawData.toString();
          addMessage("SANF", text);
          isSpeaking = true;
          notifyListeners();

          // Calcula tempo de fala baseado no tamanho do texto (aprox 15 caracteres por segundo)
          int duration = (text.length / 15).clamp(3, 15).toInt();
          Future.delayed(Duration(seconds: duration), () {
            isSpeaking = false;
            notifyListeners();
          });
          break;

        case 'system.metrics.updated':
          if (rawData is Map) {
            // Opcional: usar a pressão da fila para carga cognitiva visual
            int pending = rawData['queue_pressure'] ?? 0;
            cognitiveLoad = (pending / 50.0).clamp(0.0, 1.0);
          }
          notifyListeners();
          break;
      }
    } catch (e) {
      debugPrint("Erro ao processar mensagem do WebSocket: $e");
    }
  }

  void addMessage(String sender, String text) {
    chatHistory.add({"sender": sender, "text": text});
    notifyListeners();
  }

  Future<void> sendMessage(String text) async {
    addMessage("Você", text);
    try {
      await _apiService.interact(text);
    } catch (e) {
      addMessage("Erro", "Falha ao enviar mensagem.");
    }
  }

  @override
  void dispose() {
    _wsService.disconnect();
    super.dispose();
  }
}
