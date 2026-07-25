import 'dart:async';
import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../models/event.dart';
import '../services/cognitive_bus.dart';
import '../services/language_engine.dart';
import '../core/kernel.dart';
import '../core/scheduler.dart';
import '../core/workspace.dart';

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
  
  final FlutterTts tts = FlutterTts();
  final SpeechToText stt = SpeechToText();
  bool _speechEnabled = false;

  RobotState() {
    _initializeCore();
  }

  void _initializeCore() async {
    bus = CognitiveBus();
    kernel = Kernel(targetCycleSeconds: 0.01);
    
    scheduler = Scheduler(bus);
    workspace = CognitiveWorkspace(bus);
    languageEngine = LanguageEngine(bus);

    kernel.register(scheduler);
    kernel.register(workspace);

    // Initializations
    await Hive.initFlutter();
    await Hive.openBox('episodic_memory');
    
    await tts.setLanguage("pt-BR");
    _speechEnabled = await stt.initialize(
      onStatus: (status) {
        isListening = status == 'listening';
        notifyListeners();
      },
    );

    // Start Kernel
    kernel.run();

    // Wire up listeners
    bus.subscribe("cognition.response", _onCognitionResponse);
    bus.subscribe("attention.focus.changed", _onAttentionFocusChanged);
    bus.subscribe("system.homeostasis.changed", _onHomeostasisChanged);
    bus.subscribe("workspace.updated", languageEngine.handleEvent);
    
    // Internal state monitor
    Timer.periodic(const Duration(milliseconds: 500), (_) {
      _updateInternalMetrics();
    });
  }

  void _onCognitionResponse(Event event) async {
    final text = event.data.toString();
    addMessage("SANF", text);
    
    // UI Update on main thread
    isSpeaking = true;
    notifyListeners();

    try {
      await tts.speak(text);
      // We'll use a timer as a fallback for the completion handler due to the plugin bug
      int estimatedDuration = (text.length * 70); // ~70ms per character
      Timer(Duration(milliseconds: estimatedDuration), () {
        isSpeaking = false;
        notifyListeners();
      });
    } catch (e) {
      debugPrint("TTS Error: $e");
      isSpeaking = false;
      notifyListeners();
    }
  }

  void _onAttentionFocusChanged(Event event) {
    // Expected data structure from attention engine (to be implemented)
    attentionFocus = event.data.toString();
    isAlert = event.priority > 0.8;
    notifyListeners();
  }

  void _onHomeostasisChanged(Event event) {
    // Expected data structure from homeostasis engine (to be implemented)
    // For now, reactive to simple internal simulation or placeholders
    notifyListeners();
  }

  void _updateInternalMetrics() {
    // Link cognitive load to scheduler/bus pressure
    cognitiveLoad = (bus.pendingCount / 32.0).clamp(0.0, 1.0);
    
    // Simulated passive energy drain
    energy = (energy - 0.0005).clamp(0.0, 1.0);
    if (energy < 0.2) homeostaticMode = "Regenerativo";
    else if (isAlert) homeostaticMode = "Protetor";
    else homeostaticMode = "Equilibrado";
    
    notifyListeners();
  }

  void addMessage(String sender, String text) {
    chatHistory.add({"sender": sender, "text": text});
    if (chatHistory.length > 20) chatHistory.removeAt(0);
    notifyListeners();
    
    Hive.box('episodic_memory').add({
      'timestamp': DateTime.now().toIso8601String(),
      'sender': sender,
      'text': text
    });
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
