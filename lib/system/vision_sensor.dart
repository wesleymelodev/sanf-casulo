import 'dart:async';
import 'dart:convert';
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
  bool _isCapturing = false;

  final String geminiKey = const String.fromEnvironment('GEMINI_API_KEY');

  VisionSensor(this._bus);

  @override
  void initialize() {
    debugPrint("VisionSensor inicializado (Modo Econômico/Privacidade).");
    // Ouve solicitações de visão
    _bus.subscribe("vision.trigger.manual", (e) => _captureAndAnalyze());
  }

  Future<void> _captureAndAnalyze() async {
    if (_isCapturing) return;
    _isCapturing = true;

    CameraController? controller;

    try {
      debugPrint("Vision: Ativando câmera...");
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        debugPrint("Nenhuma câmera encontrada.");
        return;
      }

      controller = CameraController(
        cameras.first,
        ResolutionPreset.medium,
        enableAudio: false,
      );

      await controller.initialize();
      
      // Captura alguns frames para ajuste automático de exposição
      await Future.delayed(const Duration(milliseconds: 500));
      
      debugPrint("Vision: Capturando quadro...");
      final XFile image = await controller.takePicture();
      
      // DESLIGA A CÂMERA IMEDIATAMENTE APÓS O CLIQUE
      await controller.dispose();
      controller = null;
      debugPrint("Vision: Câmera desligada.");

      final bytes = await image.readAsBytes();
      final base64Image = base64Encode(bytes);

      debugPrint("Vision: Analisando com Gemini...");
      final description = await _getGeminiDescription(base64Image);
      
      if (description != null) {
        _publishVisionEvent(description);
      }
    } catch (e) {
      debugPrint("Erro na captura de visão: $e");
    } finally {
      _isCapturing = false;
      // Garante o fechamento em caso de erro
      if (controller != null) {
        await controller.dispose();
      }
    }
  }

  Future<String?> _getGeminiDescription(String base64Image) async {
    if (geminiKey.isEmpty) return null;

    const model = "gemini-1.5-flash"; 
    final url = "https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent?key=$geminiKey";

    try {
      final response = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          "contents": [{
            "parts": [
              {"text": "Descreva detalhadamente o que você vê nesta imagem para minha memória."},
              {"inline_data": {"mime_type": "image/jpeg", "data": base64Image}}
            ]
          }]
        }),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['candidates'][0]['content']['parts'][0]['text'];
      }
    } catch (e) {
      debugPrint("Falha na API Vision: $e");
    }
    return null;
  }

  void _publishVisionEvent(String description) {
    _bus.publish(Event(
      name: "sensor.vision",
      source: name,
      data: description,
      priority: 0.8,
      confidence: 0.9,
      novelty: 0.7,
    ));
  }

  @override
  void update(double deltaTime) {}

  @override
  void shutdown() {}
}
