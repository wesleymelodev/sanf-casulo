import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'providers/robot_state.dart';
import 'widgets/robot_face.dart';
import 'widgets/robot_mouth.dart';
import 'widgets/input_bar.dart';
import 'widgets/knowledge_uploader.dart';
import 'widgets/settings_drawer.dart';
import 'services/background_service.dart';

void main() async {
  // Global error handler to catch boot crashes
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    debugPrint("CRITICAL BOOT ERROR: ${details.exception}");
  };

  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    // 1. Minimal Initialization for boot
    await Hive.initFlutter();

    // 2. Conditional Android background init
    try {
      if (Platform.isAndroid) {
        await BackgroundBrain.initialize();
        BackgroundBrain.scheduleProactiveTask();
      }
    } catch (e) {
      debugPrint("Background Init Fail: $e");
    }

    runApp(
      ChangeNotifierProvider(
        create: (_) => RobotState(),
        child: const SANF(),
      ),
    );
  }, (error, stack) {
    debugPrint("ZONED ERROR: $error");
  });
}

class SANF extends StatelessWidget {
  const SANF({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SANF Desktop',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF00050A),
        useMaterial3: true,
      ),
      home: const ShellPage(),
    );
  }
}

class ShellPage extends StatelessWidget {
  const ShellPage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<RobotState>();

    return Scaffold(
      endDrawer: const SettingsDrawer(),
      body: Stack(
        children: [
          // Background Glow
          Center(
            child: Container(
              width: 500,
              height: 500,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    Colors.cyan.withOpacity(0.05),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          
          // Main Face Components: Floating in the center, slightly elevated
          Align(
            alignment: const Alignment(0, -0.2), // Elevates position slightly
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                RobotFace(
                  expression: state.expression,
                  energy: state.energy,
                ),
                const SizedBox(height: 20),
                RobotMouth(isSpeaking: state.isSpeaking),
              ],
            ),
          ),

          // Metrics and Status (Overlay)
          _buildMetricsOverlay(state),

          // Settings Button (Top Right)
          Positioned(
            top: 40,
            right: 20,
            child: Builder(
              builder: (context) => IconButton(
                icon: const Icon(Icons.settings, color: Colors.cyanAccent),
                onPressed: () => Scaffold.of(context).openEndDrawer(),
              ),
            ),
          ),

          // Chat Overlay: Scrollable balloon with max height
          if (state.chatHistory.isNotEmpty)
            Positioned(
              bottom: 130,
              left: 50,
              right: 50,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 200, maxWidth: 600),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.7),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.cyanAccent.withOpacity(0.3)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.cyanAccent.withOpacity(0.1),
                          blurRadius: 10,
                          spreadRadius: 2,
                        )
                      ],
                    ),
                    child: SingleChildScrollView(
                      reverse: true, // Auto-scroll to bottom
                      child: Text(
                        state.chatHistory.last['text'] ?? "",
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.cyanAccent,
                          fontSize: 18,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),

          // Input Bar
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const KnowledgeUploader(),
                const SizedBox(width: 10),
                InputBar(
                  onSend: (text) => state.sendMessage(text),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricsOverlay(RobotState state) {
    return Positioned(
      top: 40,
      left: 10,
      right: 10,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Left Side: Energy and Mode
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _metricBar("ENERGIA", state.energy, Colors.greenAccent),
                const SizedBox(height: 10),
                Text(
                  state.homeostaticMode.toUpperCase(),
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.cyanAccent, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          // Right Side: Cognitive Load and Focus
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _metricBar("CARGA COGNITIVA", state.cognitiveLoad, Colors.orangeAccent),
                const SizedBox(height: 10),
                Text(
                  state.attentionFocus.toUpperCase(),
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: const TextStyle(color: Colors.yellowAccent, fontSize: 9, letterSpacing: 1),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _metricBar(String label, double value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 8, color: Colors.white38)),
        const SizedBox(height: 4),
        LayoutBuilder(
          builder: (context, constraints) {
            return Container(
              width: constraints.maxWidth.clamp(0.0, 120.0), // Cap width
              height: 4,
              decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(2)),
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: value.clamp(0.0, 1.0),
                child: Container(decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
              ),
            );
          }
        ),
      ],
    );
  }
}
