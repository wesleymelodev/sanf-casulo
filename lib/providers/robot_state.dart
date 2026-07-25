import 'dart:async';
import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../models/event.dart';
import '../services/cognitive_bus.dart';
import '../services/language_engine.dart';
import '../services/proactivity_engine.dart';
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
import '../cognition/response_generator.dart';
import '../system/homeostasis.dart';
import '../system/metrics.dart';
import '../system/knowledge_importer.dart';

class RobotState extends ChangeNotifier {
  // --- UI Reactive States ---
  double energy = 1.0;
  double cognitiveLoad = 0.0;
  bool isAlert = false;
  String homeostaticMode = "Equilibrado";
  String attentionFocus = "Nenhum";
  bool isSpeaking = false;
  bool isListening = false;
  List<Map<String, String>> chatHistory = [];

  // --- Internal Cognitive Core ---
  late final Kernel kernel;
  late final CognitiveBus bus;
  late final Scheduler scheduler;
  late final CognitiveWorkspace workspace;
  late final LanguageEngine languageEngine;
  late final ProactivityEngine proactivityEngine;
  
  // New Core Components
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
  
  final FlutterTts tts = FlutterTts();
  final SpeechToText stt = SpeechToText();
  bool _speechEnabled = false;

  RobotState() {
    _initializeCore();
  }

  void _initializeCore() async {
    bus = CognitiveBus();
    kernel = Kernel(targetCycleSeconds: 0.01);
    
    // 1. Core Infrastructure
    scheduler = Scheduler(bus);
    workspace = CognitiveWorkspace(bus);
    
    // 2. Memory Systems
    sensoryMemory = SensoryMemory(bus);
    workingMemory = WorkingMemory(bus);
    episodicMemory = EpisodicMemory(bus);
    semanticMemory = SemanticMemory(bus);

    // 3. Cognition Engines
    attention = AttentionController(bus);
    associativeEngine = AssociativeEngine(bus);
    reasoning = ReasoningEngine(bus);
    semanticMemory = SemanticMemory(bus);
    languageEngine = LanguageEngine(bus, semanticMemory: semanticMemory);
    proactivityEngine = ProactivityEngine(bus, proactivityLevel: 0.6);
    responseGenerator = ResponseGenerator(bus);

    // 4. System & Metrics
    homeostasis = Homeostasis(bus);
    metrics = Metrics(bus);
    knowledgeImporter = KnowledgeImporter(bus);

    // Register all in Kernel
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

    // Initializations
    await Hive.initFlutter();
    
    await tts.setLanguage("pt-BR");
    _speechEnabled = await stt.initialize(
      onStatus: (status) {
        isListening = status == 'listening';
        notifyListeners();
      },
    );

    // Start Kernel
    kernel.run();

    // Wire up UI-critical listeners
    bus.subscribe("cognition.response", _onCognitionResponse);
    bus.subscribe("attention.focus.changed", _onAttentionFocusChanged);
    bus.subscribe("system.homeostasis.changed", _onHomeostasisChanged);
    
    // Language engine hook to workspace
    bus.subscribe("workspace.updated", (e) => languageEngine.handleEvent(e));
    bus.subscribe("cognition.proactive_thought", (e) => languageEngine.handleEvent(e));
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

    try {
      await tts.speak(text);
      int estimatedDuration = (text.length * 75).clamp(2000, 15000); 
      Timer(Duration(milliseconds: estimatedDuration), () {
        isSpeaking = false;
        notifyListeners();
      });
    } catch (e) {
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
        'text': text
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

  void toggleListening() async {
    if (!_speechEnabled) return;
    if (isListening) {
      await stt.stop();
    } else {
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
