import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../models/event.dart';
import '../models/bot_expression.dart';
import '../services/cognitive_bus.dart';
import '../services/language_engine.dart';
import '../services/proactivity_engine.dart';
import '../services/response_generator.dart';
import '../core/kernel.dart';
import '../core/scheduler.dart';
import '../core/workspace.dart';
import '../memory/sensory_memory.dart';
import '../memory/working_memory.dart';
import '../memory/episodic_memory.dart';
import '../memory/semantic_memory.dart';
import '../cognition/attention.dart';
import '../cognition/associative_engine.dart';
import '../cognition/reasoning.dart';
import '../system/homeostasis.dart';
import '../system/metrics.dart';
import '../system/knowledge_importer.dart';
import '../system/audio_sensor.dart';
import '../system/curiosity_sensor.dart';
import '../system/vision_sensor.dart';
import 'package:permission_handler/permission_handler.dart';

class RobotState extends ChangeNotifier {
  // --- UI Reactive States ---
  double energy = 1.0;
  double cognitiveLoad = 0.0;
  bool isAlert = false;
  String homeostaticMode = "Equilibrado";
  String attentionFocus = "Nenhum";
  bool isSpeaking = false;
  bool isListening = false;
  BotExpression expression = BotExpression.idle;
  List<Map<String, String>> chatHistory = [];
  double modelTemperature = 1.0;

  // --- Internal Cognitive Core ---
  late final Kernel kernel;
  late final CognitiveBus bus;
  late final Scheduler scheduler;
  late final CognitiveWorkspace workspace;
  late final LanguageEngine languageEngine;
  late final ProactivityEngine proactivityEngine;
  
  late final SensoryMemory sensoryMemory;
  late final WorkingMemory workingMemory;
  late final EpisodicMemory episodicMemory;
  late final SemanticMemory semanticMemory;
  late final AttentionController attention;
  late final AssociativeEngine associativeEngine;
  late final ReasoningEngine reasoning;
  late final ResponseGenerator responseGenerator;
  late final Homeostasis homeostasis;
  late final Metrics metrics;
  late final KnowledgeImporter knowledgeImporter;
  late final AudioSensor audioSensor;
  late final CuriositySensor curiositySensor;
  late final VisionSensor visionSensor;
  
  final FlutterTts tts = FlutterTts();
  final SpeechToText stt = SpeechToText();
  bool _speechEnabled = false;

  RobotState() {
    _initializeCore();
  }

  void _initializeCore() async {
    bus = CognitiveBus();
    kernel = Kernel(targetCycleSeconds: 0.01);
    
    // Request permissions for Android
    if (Platform.isAndroid) {
      try {
        await [
          Permission.microphone,
          Permission.camera,
          Permission.storage,
        ].request();
      } catch (e) {
        debugPrint("Permission Error: $e");
      }
    }

    scheduler = Scheduler(bus);
    workspace = CognitiveWorkspace(bus);
    
    sensoryMemory = SensoryMemory(bus);
    workingMemory = WorkingMemory(bus);
    episodicMemory = EpisodicMemory(bus);
    semanticMemory = SemanticMemory(bus);

    attention = AttentionController(bus);
    associativeEngine = AssociativeEngine(bus);
    reasoning = ReasoningEngine(bus);
    languageEngine = LanguageEngine(bus, semanticMemory: semanticMemory);
    proactivityEngine = ProactivityEngine(bus, proactivityLevel: 0.6);
    responseGenerator = ResponseGenerator(bus);

    homeostasis = Homeostasis(bus);
    metrics = Metrics(bus);
    knowledgeImporter = KnowledgeImporter(bus);
    audioSensor = AudioSensor(bus);
    curiositySensor = CuriositySensor(bus);
    visionSensor = VisionSensor(bus);

    kernel.register(scheduler);
    kernel.register(workspace);
    kernel.register(sensoryMemory);
    kernel.register(workingMemory);
    kernel.register(episodicMemory);
    kernel.register(semanticMemory);
    kernel.register(attention);
    kernel.register(associativeEngine);
    kernel.register(reasoning);
    kernel.register(proactivityEngine);
    kernel.register(responseGenerator);
    kernel.register(homeostasis);
    kernel.register(metrics);
    kernel.register(knowledgeImporter);
    kernel.register(audioSensor);
    kernel.register(curiositySensor);
    kernel.register(visionSensor);

    await Hive.initFlutter();
    
    try {
      await tts.setLanguage("pt-BR");
      _setMaleVoice();
      _speechEnabled = await stt.initialize(
        onStatus: (status) {
          isListening = status == 'listening';
          notifyListeners();
        },
      );
    } catch (e) {
      debugPrint("TTS/STT Init Error: $e");
    }

    kernel.run();

    bus.subscribe("cognition.response", _onCognitionResponse);
    bus.subscribe("attention.focus.changed", _onAttentionFocusChanged);
    bus.subscribe("system.homeostasis.changed", _onHomeostasisChanged);
    bus.subscribe("ui.expression.changed", _onExpressionChanged);
    
    bus.subscribe("workspace.updated", (e) => languageEngine.handleEvent(e));
    bus.subscribe("cognition.proactive_thought", (e) => languageEngine.handleEvent(e));
  }

  void setModelTemperature(double val) {
    modelTemperature = val;
    bus.publish(Event(
      name: "system.config.temperature_changed",
      source: "ui_settings",
      data: val,
      priority: 0.1,
    ));
    notifyListeners();
  }

  void _onExpressionChanged(Event event) {
    if (event.data is BotExpression) {
      expression = event.data;
      notifyListeners();
    }
  }

  void _setMaleVoice() async {
    debugPrint("--- INICIANDO BUSCA DE VOZES (TARGET: NESO) ---");
    try {
      List<dynamic> voices = await tts.getVoices;
      
      if (voices.isEmpty) {
        debugPrint("AVISO: Lista de vozes vazia. Tentando novamente em 2s...");
        Future.delayed(const Duration(seconds: 2), _setMaleVoice);
        return;
      }

      debugPrint("TOTAL DE VOZES: ${voices.length}");
      for (var v in voices) {
        debugPrint("VOZ: ${v["name"]} | Locale: ${v["locale"]} | Gender: ${v["gender"]}");
      }

      // 1. TENTATIVA DIRETA: Buscar por "neso" ou "Voz II"
      var target = voices.firstWhere(
        (v) {
          String name = v["name"].toString().toLowerCase();
          String locale = v["locale"].toString().toLowerCase();
          return locale.contains("pt") && (name.contains("neso") || name.contains("voz ii") || name.contains("voz 2"));
        },
        orElse: () => null,
      );

      // 2. TENTATIVA ESPECÍFICA GOOGLE MALE (pt-br-x-ptd)
      if (target == null) {
        debugPrint("Voz 'neso' não encontrada. Tentando padrão Google Masculino (ptd)...");
        target = voices.firstWhere(
          (v) {
            String name = v["name"].toString().toLowerCase();
            String locale = v["locale"].toString().toLowerCase();
            return locale.contains("pt") && name.contains("ptd");
          },
          orElse: () => null,
        );
      }

      // 3. BUSCA POR GENERO OU IDENTIFICADORES MASCULINOS CONHECIDOS (Fallback)
      if (target == null) {
        debugPrint("Heurística final para voz masculina...");
        target = voices.firstWhere(
          (v) {
            String name = v["name"].toString().toLowerCase();
            String gender = v["gender"]?.toString().toLowerCase() ?? "";
            String locale = v["locale"].toString().toLowerCase();
            
            bool isPt = locale.contains("pt");
            bool isMale = gender == "male" || 
                          name.contains("male") || 
                          name.contains("david") ||
                          name.contains("-b-") || // Padrão Google para vozes masculinas
                          name.contains("standard-b") ||
                          name.contains("wavenet-b");
            return isPt && isMale;
          },
          orElse: () => null,
        );
      }

      if (target != null) {
        debugPrint("VOZ SELECIONADA FINAL: ${target["name"]}");
        await tts.setVoice({
          "name": target["name"],
          "locale": target["locale"]
        });
        await tts.setPitch(0.8); 
      } else {
        debugPrint("ERRO: Nenhuma voz compatível encontrada. Forçando tom grave extremo.");
        await tts.setPitch(0.1); 
      }
    } catch (e) {
      debugPrint("Erro fatal ao configurar voz: $e");
    }
  }

  void _onCognitionResponse(Event event) async {
    final text = event.data.toString();
    if (text.startsWith("[Atenção]") || text.startsWith("[Estado]")) {
      addMessage("SISTEMA", text);
      return;
    }
    
    addMessage("SANF", text);
    isSpeaking = true;
    notifyListeners();

    // Filtra asteriscos para o TTS não ler "asterisco" ou pausar estranhamente
    final cleanText = text.replaceAll('*', '');

    try {
      // Remove handlers do Windows que causam erro de thread
      tts.setCompletionHandler(() {});
      tts.setErrorHandler((msg) {});
      
      await tts.speak(cleanText);
      
      // Timer interno para animação (evita usar canal nativo de conclusão)
      int estimatedDuration = (cleanText.length * 75).clamp(2000, 15000);
      Timer(Duration(milliseconds: estimatedDuration), () {
        isSpeaking = false;
        notifyListeners();
      });
    } catch (e) {
      debugPrint("Erro silenciado no TTS Windows: $e");
      isSpeaking = false;
      notifyListeners();
    }
  }

  void _onAttentionFocusChanged(Event event) {
    if (event.data is AttentionFocus) {
      final AttentionFocus focus = event.data;
      attentionFocus = focus.item.event.data?.toString() ?? focus.item.event.name;
    } else {
      attentionFocus = event.data.toString();
    }
    isAlert = event.priority > 0.8;
    notifyListeners();
  }

  void _onHomeostasisChanged(Event event) {
    energy = (event.data['energy'] ?? 1.0).toDouble();
    cognitiveLoad = (event.data['cognitive_load'] ?? 0.0).toDouble();
    
    final modeStr = event.data['mode']?.toString() ?? "balanced";
    if (modeStr == 'balanced') homeostaticMode = "Equilibrado";
    else if (modeStr == 'protective') homeostaticMode = "Protetor";
    else if (modeStr == 'restorative') homeostaticMode = "Regenerativo";
    
    notifyListeners();
  }

  void addMessage(String sender, String text) {
    chatHistory.add({"sender": sender, "text": text});
    if (chatHistory.length > 20) chatHistory.removeAt(0);
    notifyListeners();
    
    if (Hive.isBoxOpen('episodic_memory_store')) {
       Hive.box('episodic_memory_store').add({
        'timestamp': DateTime.now().toIso8601String(),
        'sender': sender,
        'text': text,
        'expression': expression.name, // Save as string to avoid Hive adapter error
      });
    }
  }

  Future<void> sendMessage(String text) async {
    if (text.isEmpty) return;
    addMessage("Você", text);
    
    bus.publish(Event(
      name: "user.input",
      source: "input_bar",
      data: text,
      priority: 0.9,
    ));
  }

  Future<void> importRuntimeFile(File file, String fileName) async {
    await knowledgeImporter.processFile(file, fileName);
    notifyListeners();
  }

  void toggleListening() async {
    // Note: Manual listening toggled from UI. 
    // In passive mode, the AudioSensor handles this. 
    // This method is now a fallback or manual override.
    if (isListening) {
      await stt.stop();
    } else {
      _speechEnabled = await stt.initialize();
      if (!_speechEnabled) return;

      await stt.listen(
        onResult: (result) {
          if (result.finalResult) {
            sendMessage(result.recognizedWords);
          }
        },
        localeId: 'pt_BR',
      );
    }
  }

  @override
  void dispose() {
    kernel.stop();
    super.dispose();
  }
}
