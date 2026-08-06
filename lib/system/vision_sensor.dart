import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_object_detection/google_mlkit_object_detection.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../models/event.dart';
import '../services/cognitive_bus.dart';
import '../core/kernel.dart';

class VisionSensor extends LifecycleComponent {
  @override
  final String name = "vision_sensor";

  final CognitiveBus _bus;
  bool _isCapturing = false;
  ObjectDetector? _objectDetector;

  VisionSensor(this._bus);

  @override
  void initialize() {
    if (Platform.isWindows) {
      debugPrint("VisionSensor: Desativado no Windows por compatibilidade.");
      return;
    }
    debugPrint("VisionSensor inicializado (Modo Local/Privacidade).");
    _initDetector();
    _bus.subscribe("vision.trigger.manual", (e) => _captureAndAnalyze());
    _bus.subscribe("vision.analyze_file", (e) {
      if (e.data is File) {
        analyzeImportedImage(e.data as File);
      } else if (e.data is String) {
        analyzeImportedImage(File(e.data as String));
      }
    });
  }

  Future<void> _initDetector() async {
    try {
      // Detector TFLite Customizado (Apenas Android)
      if (Platform.isAndroid) {
        final directory = await getExternalStorageDirectory();
        final modelPath = p.join(directory!.path, 'gemma3-1B-it-int4.tflite');

        if (await File(modelPath).exists()) {
          final options = LocalObjectDetectorOptions(
            mode: DetectionMode.single,
            modelPath: modelPath,
            classifyObjects: true,
            multipleObjects: true,
          );
          _objectDetector = ObjectDetector(options: options);
          debugPrint("Vision: Detector Local (Gemma TFLite) carregado.");
        } else {
          debugPrint("Vision: Usando Detector Base do Google (Offline).");
          _objectDetector = ObjectDetector(options: ObjectDetectorOptions(
            mode: DetectionMode.single,
            classifyObjects: true,
            multipleObjects: true,
          ));
        }
      } else {
        debugPrint("Vision: Sensores visuais ativos em modo passivo (Desktop).");
      }
    } catch (e) {
      debugPrint("Erro ao inicializar detector visual: $e");
    }
  }

  Future<void> _captureAndAnalyze() async {
    if (_isCapturing || _objectDetector == null) return;
    _isCapturing = true;

    CameraController? controller;

    try {
      debugPrint("Vision: Ativando hardware local...");
      final cameras = await availableCameras();
      if (cameras.isEmpty) return;

      controller = CameraController(cameras.first, ResolutionPreset.medium, enableAudio: false);
      await controller.initialize();
      await Future.delayed(const Duration(milliseconds: 500));
      
      final XFile image = await controller.takePicture();
      await controller.dispose();
      controller = null;

      final inputImage = InputImage.fromFilePath(image.path);
      final List<DetectedObject> objects = await _objectDetector!.processImage(inputImage);

      String description = _formatDescription(objects);
      _publishVisionEvent(description);
      
    } catch (e) {
      debugPrint("Erro na visão local: $e");
    } finally {
      _isCapturing = false;
      if (controller != null) await controller.dispose();
    }
  }

  String _formatDescription(List<DetectedObject> objects) {
    if (objects.isEmpty) return "Ambiente observado, nenhum objeto específico identificado.";
    
    final labels = objects.map((obj) {
      final label = obj.labels.isNotEmpty ? obj.labels.first.text : "objeto desconhecido";
      return "- $label (confiança: ${(obj.labels.isNotEmpty ? obj.labels.first.confidence * 100 : 0).toStringAsFixed(0)}%)";
    }).join("\n");

    return "Análise Visual Local:\n$labels";
  }

  Future<void> analyzeImportedImage(File imageFile) async {
    if (_isCapturing) return;
    _isCapturing = true;
    
    _bus.publish(Event(name: "cognition.thinking.start", source: name));

    try {
      debugPrint("Vision: Analisando imagem importada com Gemini...");
      final description = await _tryGeminiVision(imageFile);
      
      if (description != null) {
        _publishVisionEvent("Visão Gemini (Imagem Importada):\n$description");
      } else {
        _publishVisionEvent("Falha ao analisar imagem importada.");
      }
    } catch (e) {
      debugPrint("Erro na visão Gemini: $e");
    } finally {
      _isCapturing = false;
      _bus.publish(Event(name: "cognition.thinking.stop", source: name));
    }
  }

  Future<String?> _tryGeminiVision(File imageFile) async {
    const String geminiKey = String.fromEnvironment('GEMINI_API_KEY');
    if (geminiKey.isEmpty) return "Erro: GEMINI_API_KEY não configurada.";

    final url = "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.6-flash:generateContent?key=$geminiKey";

    try {
      final bytes = await imageFile.readAsBytes();
      final base64Image = base64Encode(bytes);

      final response = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          "contents": [{
            "parts": [
              {"text": "Descreva esta imagem de forma detalhada para um sistema cognitivo."},
              {
                "inline_data": {
                  "mime_type": "image/jpeg",
                  "data": base64Image
                }
              }
            ]
          }]
        }),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['candidates'][0]['content']['parts'][0]['text'];
      }
    } catch (e) {
      debugPrint("Gemini Vision Exception: $e");
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
  void shutdown() {
    _objectDetector?.close();
  }
}
