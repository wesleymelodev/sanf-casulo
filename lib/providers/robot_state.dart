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
      final data = jsonDecode(message);
      final event = data['type'];
      final payload = data['payload'];

      switch (event) {
        case 'system.homeostasis.changed':
          homeostaticMode = payload['mode'] ?? homeostaticMode;
          energy = (payload['energy'] ?? 100) / 100.0;
          notifyListeners();
          break;
        case 'attention.focus.changed':
          attentionFocus = payload['focus'] ?? attentionFocus;
          isAlert = payload['urgency'] == 'high';
          notifyListeners();
          break;
        case 'cognition.response':
          addMessage("SANF", payload['text']);
          isSpeaking = true;
          notifyListeners();
          // Simulate speaking end after some time
          Future.delayed(Duration(seconds: 3), () {
            isSpeaking = false;
            notifyListeners();
          });
          break;
        case 'status.update':
          cognitiveLoad = (payload['load'] ?? 0) / 100.0;
          notifyListeners();
          break;
      }
    } catch (e) {
      debugPrint("Error parsing WS message: $e");
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
