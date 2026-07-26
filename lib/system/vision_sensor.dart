import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import '../models/event.dart';
import '../services/cognitive_bus.dart';
import '../core/kernel.dart';

class VisionSensor extends LifecycleComponent {
  @override
  final String name = "vision_sensor";

  final CognitiveBus _bus;
  CameraController? _controller;
  bool _isInitialized = false;
  bool _isCapturing = false;

  final String geminiKey = const String.fromEnvironment('GEMINI_API_KEY');

  VisionSensor(this._bus);

  @override
  void initialize() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        debugPrint("Nenhuma câmera encontrada.");
        return;
      }

      _controller = CameraController(
        cameras.first,
        ResolutionPreset.medium,
        enableAudio: false,
      );

      await _controller!.initialize();
      _isInitialized = true;
      debugPrint("VisionSensor inicializado e aguardando comandos.");

      // Ouve solicitações de visão (ex: "ative a câmera")
      _bus.subscribe("vision.trigger.manual", (e) => _captureAndAnalyze());
    } catch (e) {
      debugPrint("Erro ao inicializar VisionSensor: $e");
    }
  }

  Future<void> _captureAndAnalyze() async {
    if (!_isInitialized || _isCapturing) return;
    _isCapturing = true;

    try {
      debugPrint("Vision: Capturando imagem...");
      final XFile image = await _controller!.takePicture();
      final bytes = await image.readAsBytes();
      final base64Image = base64Encode(bytes);

      debugPrint("Vision: Enviando para Gemini...");
      final description = await _getGeminiDescription(base64Image);
      
      if (description != null) {
        _publishVisionEvent(description);
      }
    } catch (e) {
      debugPrint("Erro na captura de visão: $e");
    } finally {
      _isCapturing = false;
    }
  }

  Future<String?> _getGeminiDescription(String base64Image) async {
    if (geminiKey.isEmpty) {
      debugPrint("Erro: GEMINI_API_KEY não configurada.");
      return null;
    }

    // Nota: Usamos 1.5-flash como o modelo estável mais atualizado compatível com visão
    // Mantenha este se o 3.6 não estiver disponível no seu nível de API
    const model = "gemini-3.6-flash";
    final url = "https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent?key=$geminiKey";

    try {
      final response = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          "contents": [{
            "parts": [
              {"text": "Descreva detalhadamente o que você vê nesta imagem. Foco em pessoas, objetos e ambiente para minha memória de longo prazo."},
              {"inline_data": {"mime_type": "image/jpeg", "data": base64Image}}
            ]
          }]
        }),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['candidates'][0]['content']['parts'][0]['text'];
      } else {
        debugPrint("Gemini Vision Error: ${response.body}");
      }
    } catch (e) {
      debugPrint("Falha ao chamar Gemini Vision: $e");
    }
    return null;
  }

  void _publishVisionEvent(String description) {
    _bus.publish(Event(
      name: "sensor.vision",
      source: name,
      data: description,
      priority: 0.8, // Prioridade alta por ser estímulo externo direto
      confidence: 0.9,
      novelty: 0.7,
    ));
    debugPrint("VISÃO: $description");
  }

  @override
  void update(double deltaTime) {}

  @override
  void shutdown() {
    _controller?.dispose();
  }
}
