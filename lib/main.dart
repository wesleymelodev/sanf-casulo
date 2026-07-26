import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/robot_state.dart';
import 'widgets/robot_face.dart';
import 'widgets/robot_mouth.dart';
import 'widgets/input_bar.dart';
import 'widgets/knowledge_uploader.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    ChangeNotifierProvider(
      create: (_) => RobotState(),
      child: const SANF(),
    ),
  );
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
          
          // Main Face Components: mantenha no centro da tela com Center.
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Center(
                child: RobotFace(
                  expression: state.expression,
                  energy: state.energy,
                ),
              ),
              const SizedBox(height: 20),
              Center(
                child: RobotMouth(isSpeaking: state.isSpeaking),
              ),
            ],
          ),

          // Metrics and Status (Overlay)
          _buildMetricsOverlay(state),

          // Chat Overlay
          if (state.chatHistory.isNotEmpty)
            Positioned(
              bottom: 130,
              left: 50,
              right: 50,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.cyanAccent.withOpacity(0.2)),
                ),
                child: Text(
                  state.chatHistory.last['text'] ?? "",
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.cyanAccent, fontSize: 20),
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
      left: 20,
      right: 20,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Left Side: Energy and Mode
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _metricBar("ENERGIA", state.energy, Colors.greenAccent),
              const SizedBox(height: 10),
              Text(
                state.homeostaticMode.toUpperCase(),
                style: const TextStyle(color: Colors.cyanAccent, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 2),
              ),
            ],
          ),
          // Right Side: Cognitive Load and Focus
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _metricBar("CARGA COGNITIVA", state.cognitiveLoad, Colors.orangeAccent),
              const SizedBox(height: 10),
              Text(
                state.attentionFocus.toUpperCase(),
                style: const TextStyle(color: Colors.yellowAccent, fontSize: 10, letterSpacing: 1.5),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _metricBar(String label, double value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 9, color: Colors.white38)),
        const SizedBox(height: 4),
        Container(
          width: 150,
          height: 4,
          decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(2)),
          child: FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: value.clamp(0.0, 1.0),
            child: Container(decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
          ),
        ),
      ],
    );
  }
}
