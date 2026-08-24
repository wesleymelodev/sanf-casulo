import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
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
import '../cognition/consolidation_engine.dart';
import '../system/homeostasis.dart';
import '../system/metrics.dart';
import '../system/knowledge_importer.dart';
import '../system/audio_sensor.dart';
import '../system/curiosity_sensor.dart';
import '../system/vision_sensor.dart';
import '../system/environmental_sensor.dart';
import '../services/expression_mapper.dart';
import '../services/cloud_sync_service.dart';
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
  bool isThinking = false;
  BotExpression expression = BotExpression.idle;
  List<Map<String, String>> chatHistory = [];
  List<Map<String, String>> activeSessionHistory = [];
  double modelTemperature = 1.0;
  double proactivityLevel = 0.6; // 0.0 a 1.0
  String userName = "Viajante";
  String ghostName = "SANF (Spectrum Ancrolyn Nexus Fractal)";
  String selfModification = "Nenhuma auto-modificação ativa. Mantenha as diretrizes base.";

  // --- Dynamic UI States (Agentic Control) ---
  Color ambientColor = const Color(0xFF00050A);
  String appBarTitle = "SANF Interface";
  String fontFamily = 'Default';
  Color textBodyColor = Colors.cyanAccent;
  Color senderNameColor = Colors.yellowAccent;
  Color eyeColor = Colors.cyanAccent;
  Color mouthColor = Colors.yellowAccent;

  // --- Dynamic API Keys (Web/Custom) ---
  String webGeminiKey = "";
  String webGroqKey = "";
  String webCfKey = "";
  String webCfAccount = "";
  Map<String, String> webFirebaseConfig = {};

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
  late final ConsolidationEngine consolidationEngine;
  late final ResponseGenerator responseGenerator;
  late final Homeostasis homeostasis;
  late final Metrics metrics;
  late final KnowledgeImporter knowledgeImporter;
  late final AudioSensor audioSensor;
  late final CuriositySensor curiositySensor;
  late final VisionSensor visionSensor;
  late final EnvironmentalSensor environmentalSensor;
  late final CloudSyncService cloudSync;
  
  final FlutterTts tts = FlutterTts();
  bool _speechEnabled = false;

  static const platform = MethodChannel('com.lokinefrius.sanf/settings');
  static const sensorChannel = EventChannel('com.lokinefrius.sanf/sensors');

  RobotState() {
    _initializeCore();
  }

  Future<void> _syncSettingsToNative() async {
    try {
      await platform.invokeMethod('syncSettings', {
        'ghostName': ghostName,
        'userName': userName,
        'webGeminiKey': webGeminiKey,
        'webGroqKey': webGroqKey,
        'energy': energy,
        'cognitiveLoad': cognitiveLoad,
        'homeostaticMode': homeostaticMode,
        'proactivityLevel': proactivityLevel,
      });
    } catch (e) {
      debugPrint("Native Sync Error: $e");
    }
  }

  void _initializeCore() async {
    bus = CognitiveBus();
    kernel = Kernel(targetCycleSeconds: 0.01);

    // Hive is already initialized in main.dart
    final settingsBox = await Hive.openBox('settings');
    modelTemperature = settingsBox.get('modelTemperature', defaultValue: 1.0);
    proactivityLevel = settingsBox.get('proactivityLevel', defaultValue: 0.6);
    userName = settingsBox.get('userName', defaultValue: "Viajante");
    ghostName = settingsBox.get('ghostName', defaultValue: "SANF (Spectrum Ancrolyn Nexus Fractal)");
    selfModification = settingsBox.get('selfModification', defaultValue: "Nenhuma auto-modificação ativa. Mantenha as diretrizes base.");

    webGeminiKey = settingsBox.get('webGeminiKey', defaultValue: "");
    webGroqKey = settingsBox.get('webGroqKey', defaultValue: "");
    webCfKey = settingsBox.get('webCfKey', defaultValue: "");
    webCfAccount = settingsBox.get('webCfAccount', defaultValue: "");
    webFirebaseConfig = Map<String, String>.from(settingsBox.get('webFirebaseConfig', defaultValue: <String, String>{}));
    
    final List<dynamic>? savedHistory = settingsBox.get('activeSessionHistory');
    if (savedHistory != null) {
      activeSessionHistory = savedHistory.map((m) => Map<String, String>.from(m as Map)).toList();
    }

    // Request permissions for Android
    if (!kIsWeb && Platform.isAndroid) {
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
    consolidationEngine = ConsolidationEngine(bus, episodicMemory);
    languageEngine = LanguageEngine(
      bus, 
      semanticMemory: semanticMemory,
      initialTemp: modelTemperature,
      initialUser: userName,
      initialGhost: ghostName,
      geminiKey: webGeminiKey,
      groqKey: webGroqKey,
      initialHistory: activeSessionHistory,
      initialSelfMod: selfModification,
    );
    proactivityEngine = ProactivityEngine(bus, proactivityLevel: proactivityLevel);
    responseGenerator = ResponseGenerator(bus);

    homeostasis = Homeostasis(bus);
    metrics = Metrics(bus);
    knowledgeImporter = KnowledgeImporter(bus);
    audioSensor = AudioSensor(bus);
    curiositySensor = CuriositySensor(bus);
    visionSensor = VisionSensor(bus);
    environmentalSensor = EnvironmentalSensor(bus);
    cloudSync = CloudSyncService(bus, semanticMemory: semanticMemory);

    // REGISTRO COM LOGS DE DIAGNÓSTICO
    void _register(LifecycleComponent c) {
      debugPrint("Kernel: Registrando ${c.name}...");
      kernel.register(c);
    }

    _register(scheduler);
    _register(workspace);
    _register(sensoryMemory);
    _register(workingMemory);
    _register(episodicMemory);
    _register(semanticMemory);
    _register(attention);
    _register(associativeEngine);
    _register(reasoning);
    _register(consolidationEngine);
    _register(proactivityEngine);
    _register(responseGenerator);
    _register(homeostasis);
    _register(metrics);
    _register(knowledgeImporter);
    _register(audioSensor);
    _register(curiositySensor);
    _register(visionSensor);
    _register(environmentalSensor);
    _register(cloudSync);

    // INICIA O KERNEL IMEDIATAMENTE (Não espera por TTS ou Hive)
    debugPrint("Kernel: Iniciando ciclo cognitivo...");
    kernel.run();

    // Inscrições Globais
    bus.subscribe("cognition.response", _onCognitionResponse);
    bus.subscribe("cognition.thinking.start", (e) {
      scheduleMicrotask(() { 
        isThinking = true; 
        notifyListeners(); 
      });
      _vibratePattern("thinking");
    });
    bus.subscribe("cognition.thinking.stop", (e) => scheduleMicrotask(() { isThinking = false; notifyListeners(); }));
    bus.subscribe("attention.focus.changed", _onAttentionFocusChanged);
    bus.subscribe("system.homeostasis.changed", _onHomeostasisChanged);
    bus.subscribe("ui.expression.changed", _onExpressionChanged);
    
    // Inscrição para Comandos de UI (Agente)
    bus.subscribe("ui.command.execute", _onUiCommandReceived);
    
    // Inscrição para Ações de Dispositivo (Hardware)
    bus.subscribe("device.action.execute", _onDeviceActionReceived);

    // Inscrição para Sensores Nativos (Luz/Proximidade)
    if (!kIsWeb && Platform.isAndroid) {
      sensorChannel.receiveBroadcastStream().listen((data) {
        if (data is Map) {
          bus.publish(Event(
            name: "sensor.${data['type']}",
            source: "native_sensors",
            data: data['value'],
            priority: 0.3,
          ));
        }
      }, onError: (err) {
        debugPrint("Sensor Stream Error: $err");
      });
    }

    // Inscrições de Configuração para o Motor de Linguagem
    bus.subscribe("system.config.keys_changed", (e) => languageEngine.handleEvent(e));
    bus.subscribe("system.config.username_changed", (e) => languageEngine.handleEvent(e));
    bus.subscribe("system.config.ghostname_changed", (e) => languageEngine.handleEvent(e));
    bus.subscribe("system.config.self_mod_changed", (e) {
      selfModification = (e.data as String);
      Hive.box('settings').put('selfModification', selfModification);
      languageEngine.handleEvent(e);
      notifyListeners();
    });

    bus.subscribe("system.config.temperature_changed", (e) => languageEngine.handleEvent(e));
    bus.subscribe("cognition.context_shift", (e) => languageEngine.handleEvent(e));
    
    bus.subscribe("user.input", (e) {
      if (e.metadata["from_audio"] == true) {
        addMessage("Você", e.data.toString());
      }
    });
    
    bus.subscribe("sensor.audio.status", (e) {
      scheduleMicrotask(() {
        isListening = e.data == 'listening';
        notifyListeners();
      });
    });

    bus.subscribe("workspace.updated", (e) => languageEngine.handleEvent(e));
    bus.subscribe("cognition.proactive_thought", (e) => languageEngine.handleEvent(e));

    bus.subscribe("system.config.history_updated", (e) {
      activeSessionHistory = List<Map<String, String>>.from((e.data as List).map((m) => Map<String, String>.from(m as Map)));
      Hive.box('settings').put('activeSessionHistory', activeSessionHistory);
    });

    // SETUP ASSÍNCRONO (Não bloqueia o Kernel)
    _asyncSetup();
  }

  void _asyncSetup() async {
    try {
      await tts.setLanguage("pt-BR");
      _setMaleVoice();
    } catch (e) {
      debugPrint("TTS Setup Error: $e");
    }

    // Publish initial persisted settings
    bus.publish(Event(
      name: "system.config.temperature_changed",
      source: "kernel_boot",
      data: modelTemperature,
      priority: 0.0,
    ));
    bus.publish(Event(
      name: "system.config.proactivity_changed",
      source: "kernel_boot",
      data: proactivityLevel,
      priority: 0.0,
    ));
    bus.publish(Event(
      name: "system.config.username_changed",
      source: "kernel_boot",
      data: userName,
      priority: 1.0,
    ));
    bus.publish(Event(
      name: "system.config.ghostname_changed",
      source: "kernel_boot",
      data: ghostName,
      priority: 1.0,
    ));
    bus.publish(Event(
      name: "system.config.self_mod_changed",
      source: "kernel_boot",
      data: selfModification,
      priority: 1.0,
    ));
  }

  void setModelTemperature(double val) {
    modelTemperature = val;
    Hive.box('settings').put('modelTemperature', val);
    bus.publish(Event(
      name: "system.config.temperature_changed",
      source: "ui_settings",
      data: val,
      priority: 0.1,
    ));
    notifyListeners();
  }

  void setProactivityLevel(double val) {
    proactivityLevel = val;
    Hive.box('settings').put('proactivityLevel', val);
    bus.publish(Event(
      name: "system.config.proactivity_changed",
      source: "ui_settings",
      data: val,
      priority: 0.1,
    ));
    _syncSettingsToNative();
    notifyListeners();
  }

  void setUserName(String name) {
    userName = name;
    Hive.box('settings').put('userName', name);
    bus.publish(Event(
      name: "system.config.username_changed",
      source: "ui_settings",
      data: name,
      priority: 0.1,
    ));
    _syncSettingsToNative();
    notifyListeners();
  }

  void setGhostName(String name) {
    ghostName = name;
    Hive.box('settings').put('ghostName', name);
    bus.publish(Event(
      name: "system.config.ghostname_changed",
      source: "ui_settings",
      data: name,
      priority: 0.1,
    ));
    _syncSettingsToNative();
    notifyListeners();
  }

  void setWebGeminiKey(String key) {
    webGeminiKey = key;
    Hive.box('settings').put('webGeminiKey', key);
    bus.publish(Event(name: "system.config.keys_changed", source: "ui_settings", data: {"gemini": key}));
    _syncSettingsToNative();
    notifyListeners();
  }

  void setWebGroqKey(String key) {
    webGroqKey = key;
    Hive.box('settings').put('webGroqKey', key);
    bus.publish(Event(name: "system.config.keys_changed", source: "ui_settings", data: {"groq": key}));
    _syncSettingsToNative();
    notifyListeners();
  }

  void setWebFirebaseConfig(Map<String, String> config) {
    webFirebaseConfig = config;
    Hive.box('settings').put('webFirebaseConfig', config);
    notifyListeners();
  }

  void _onExpressionChanged(Event event) {
    if (event.data is BotExpression) {
      expression = event.data;
      notifyListeners();
    }
  }

  void _onUiCommandReceived(Event event) {
    final commands = event.data as Map<String, dynamic>;
    
    scheduleMicrotask(() {
      // 1. Mudança de Cor de Fundo
      if (commands['action'] == 'update_color' && commands['element'] == 'scaffoldBg') {
        ambientColor = _parseColor(commands['value']);
      }

      // 2. Mudança de Título
      if (commands['action'] == 'change_title') {
        appBarTitle = commands['value'];
      }

      // 3. Mudança de Fonte
      if (commands['action'] == 'update_font_family') {
        fontFamily = commands['value'];
      }

      // 4. Cores de Texto Dinâmicas
      if (commands.containsKey('text_body_color')) {
        textBodyColor = _parseColor(commands['text_body_color']);
      }
      if (commands.containsKey('sender_name_color')) {
        senderNameColor = _parseColor(commands['sender_name_color']);
      }
      if (commands.containsKey('eye_color')) {
        eyeColor = _parseColor(commands['eye_color']);
      }
      if (commands.containsKey('mouth_color')) {
        mouthColor = _parseColor(commands['mouth_color']);
      }
      
      notifyListeners();
    });
  }

  void _onDeviceActionReceived(Event event) async {
    if (kIsWeb || !Platform.isAndroid) return;

    final actions = event.data as List<dynamic>;
    
    for (var action in actions) {
      if (action is! Map) continue;
      final type = action['type'];
      
      try {
        if (type == 'vibrate') {
          final duration = action['duration'] ?? 500;
          final pattern = action['pattern'];
          if (pattern != null) {
            _vibratePattern(pattern.toString());
          } else {
            await platform.invokeMethod('device_vibrate', {'duration': duration});
          }
        } else if (type == 'set_alarm') {
          final hour = action['hour'] ?? 8;
          final minutes = action['minutes'] ?? 0;
          final message = action['message'] ?? "Alarme do SANF";
          await platform.invokeMethod('device_set_alarm', {
            'hour': hour,
            'minutes': minutes,
            'message': message,
          });
        } else if (type == 'get_battery') {
          final batteryLevel = await platform.invokeMethod('device_get_battery');
          bus.publish(Event(
            name: "sensor.battery.level",
            source: "native_action",
            data: batteryLevel,
            priority: 0.5,
          ));
          workspace.add(Event(
            name: "sensor.battery.level",
            source: "native_action",
            data: "Nível de bateria atual: $batteryLevel%",
            priority: 0.7
          ));
        } else if (type == 'flashlight') {
          final enabled = action['enabled'] ?? false;
          await platform.invokeMethod('device_flashlight', {'enabled': enabled});
        } else if (type == 'brightness') {
          final brightness = (action['value'] ?? 0.5).toDouble();
          await platform.invokeMethod('device_set_brightness', {'brightness': brightness});
        } else if (type == 'volume') {
          final volume = (action['value'] ?? 50).toInt();
          await platform.invokeMethod('device_set_volume', {'volume': volume});
        }
      } catch (e) {
        debugPrint("Error executing device action $type: $e");
      }
    }
  }

  Color _parseColor(String value) {
    if (value.startsWith('#')) {
      try {
        String hex = value.replaceFirst('#', '');
        if (hex.length == 6) hex = 'FF$hex';
        return Color(int.parse(hex, radix: 16));
      } catch (e) {
        return Colors.cyanAccent;
      }
    }
    switch (value.toLowerCase()) {
      case 'red': return const Color(0xFFFF0000);
      case 'blue': return const Color(0xFF0000FF);
      case 'green': return const Color(0xFF00FF00);
      case 'yellow': return const Color(0xFFFFFF00);
      case 'black': return const Color(0xFF000000);
      case 'white': return const Color(0xFFFFFFFF);
      case 'purple': return const Color(0xFFB700FF);
      case 'orange': return const Color(0xFFFF8700);
      case 'pink': return const Color(0xFFFF0080);
      case 'brown': return const Color(0xFF8B4513);
      case 'gray': return const Color(0xFF808080);
      case 'grey': return const Color(0xFF808080);
      case 'cyan': return Colors.cyanAccent;
      default: return Colors.cyanAccent;
    }
  }

  void _setMaleVoice() async {
    debugPrint("--- INICIANDO BUSCA DE VOZES (TARGET: NESO) ---");
    try {
      // Timeout de segurança para evitar travamento no boot na Web/Windows
      final List<dynamic> voices = await Future.any<dynamic>([
        tts.getVoices,
        Future.delayed(const Duration(seconds: 5), () => <dynamic>[]),
      ]);
      
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
          return locale.contains("pt") && name.contains("ptd");
        },
        orElse: () => null,
      );

      // 2. BUSCA POR GENERO OU IDENTIFICADORES MASCULINOS CONHECIDOS (Fallback)
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
    bus.publish(Event(name: "cognition.speaking.start", source: "robot_state"));
    notifyListeners();

    // Filtra asteriscos para o TTS não ler "asterisco" ou pausar estranhamente
    final cleanText = text.replaceAll('*', '');

    // Pequeno delay de "respiro" para o Windows processar o rebuild da UI antes do I/O de áudio
    await Future.delayed(const Duration(milliseconds: 200));

    // AGENDAMENTO DE EXPRESSÕES (Fallback para quando o handler nativo falha)
    // AVISO: No Windows, timers de sincronia durante o TTS podem causar instabilidade fatal
    try {
      if (!kIsWeb && !Platform.isWindows) {
        _scheduleExpressions(cleanText);
      } else {
        debugPrint("TTS Sync: Agendamento interno desativado ou rodando na Web/Windows.");
      }
    } catch (e) {
      debugPrint("Erro ao agendar expressões: $e");
    }

    if (!kIsWeb && Platform.isWindows) {
      debugPrint("TTS: Iniciando fala em modo isolado...");
    }

    try {
      // Limpeza de buffer e remoção de handlers perigosos no Windows
      // AVISO: Não sete handlers (mesmo vazios) no Windows para evitar erro de threading nativo
      if (!kIsWeb && Platform.isWindows) {
        await tts.stop(); 
      }
      
      await tts.speak(cleanText);
      
      // Timer interno para animação (evita usar canal nativo de conclusão que crasha o Windows)
      int estimatedDuration = (cleanText.length * 75).clamp(2000, 15000);
      Timer(Duration(milliseconds: estimatedDuration), () {
        isSpeaking = false;
        bus.publish(Event(name: "cognition.speaking.stop", source: "robot_state"));
        notifyListeners();
      });
    } catch (e) {
      debugPrint("Erro silenciado no TTS Windows: $e");
      isSpeaking = false;
      notifyListeners();
    }
  }

  void _scheduleExpressions(String fullText) {
    final words = fullText.split(' ');
    int currentOffset = 0;
    int scheduledCount = 0;

    for (var word in words) {
      if (kIsWeb || (!Platform.isWindows && scheduledCount > 15)) break; // Limite de 15 expressões por frase para evitar crash de Timers
      
      final cleanWord = word.replaceAll(RegExp(r'[^\w\s]'), '');
      final expression = ExpressionMapper.getExpressionForWord(cleanWord);
      
      if (expression != null) {
        scheduledCount++;
        // Estima o tempo em que esta palavra será dita (ms)
        // 75ms por caractere é uma média segura para velocidade 0.5
        int delay = (currentOffset * 75).clamp(0, 15000);
        
        Timer(Duration(milliseconds: delay), () {
          if (isSpeaking && hasListeners) {
            bus.publish(Event(
              name: "ui.expression.changed",
              source: "scheduled_sync",
              data: expression,
              priority: 0.2,
            ));
          }
        });
      }
      currentOffset += word.length + 1;
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
    if (isAlert) {
      _vibratePattern("alert");
    }
    notifyListeners();
  }

  void _onHomeostasisChanged(Event event) {
    energy = (event.data['energy'] ?? 1.0).toDouble();
    cognitiveLoad = (event.data['cognitive_load'] ?? 0.0).toDouble();
    
    final modeStr = event.data['mode']?.toString() ?? "balanced";
    if (modeStr == 'balanced') homeostaticMode = "Equilibrado";
    else if (modeStr == 'protective') homeostaticMode = "Protetor";
    else if (modeStr == 'restorative') homeostaticMode = "Regenerativo";
    
    _syncSettingsToNative();
    notifyListeners();
  }

  void addMessage(String sender, String text) {
    chatHistory.add({"sender": sender, "text": text});
    if (chatHistory.length > 20) chatHistory.removeAt(0);
    
    // Decouple UI update from the current execution context to prevent Windows rendering deadlock
    scheduleMicrotask(() {
      notifyListeners();
    });
  }

  Future<void> sendMessage(String text) async {
    if (text.isEmpty) return;
    
    try {
      addMessage("Você", text);

      // Pequeno respiro para a UI processar a nova mensagem antes da carga cognitiva
      await Future.delayed(const Duration(milliseconds: 50));

      bus.publish(Event(
        name: "user.input",
        source: "input_bar",
        data: text,
        priority: 0.9,
      ));
      
    } catch (e) {
      debugPrint("ERROR in sendMessage: $e");
    }
  }

  Future<void> importRuntimeFile(File file, String fileName) async {
    await knowledgeImporter.processFile(file, fileName);
    notifyListeners();
  }

  void toggleListening() async {
    // Comando para o sensor de áudio via barramento
    bus.publish(Event(
      name: "sensor.audio.toggle",
      source: "input_bar",
      priority: 0.5,
    ));
  }

  void _vibratePattern(String type) async {
    if (kIsWeb || !Platform.isAndroid) return;
    
    try {
      switch (type) {
        case "thinking":
          await platform.invokeMethod('device_vibrate', {'duration': 50});
          break;
        case "alert":
          await platform.invokeMethod('device_vibrate', {'duration': 100});
          await Future.delayed(const Duration(milliseconds: 100));
          await platform.invokeMethod('device_vibrate', {'duration': 100});
          break;
        case "error":
        case "heavy":
          await platform.invokeMethod('device_vibrate', {'duration': 800});
          break;
        case "pulse":
          await platform.invokeMethod('device_vibrate', {'duration': 200});
          await Future.delayed(const Duration(milliseconds: 400));
          await platform.invokeMethod('device_vibrate', {'duration': 200});
          break;
      }
    } catch (e) {
      debugPrint("Vibration pattern error: $e");
    }
  }

  @override
  void dispose() {
    kernel.stop();
    super.dispose();
  }
}
