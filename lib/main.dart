import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'providers/robot_state.dart';
import 'widgets/robot_eyes.dart';
import 'widgets/robot_mouth.dart';
import 'widgets/status_panel.dart';
import 'widgets/input_bar.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: const FirebaseOptions(
      apiKey: "AIzaSyD6vFYYAP42Lp2_kE7vRDWuffdlI_dp0Ro",
      authDomain: "sanf-casulo.firebaseapp.com",
      projectId: "sanf-casulo",
      storageBucket: "sanf-casulo.firebasestorage.app",
      messagingSenderId: "72454618080",
      appId: "1:72454618080:web:3adc3d7d613e81a2414985",
      measurementId: "G-TKS7B5PCQM",
    ),
  );
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
      title: 'SANF Casulo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF00050A), // Deep Black
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
              width: 400,
              height: 400,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    Colors.cyan.withOpacity(0.1),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          
          // Main Face Components
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              RobotEyes(
                energy: state.energy,
                isAlert: state.isAlert,
              ),
              const SizedBox(height: 40),
              RobotMouth(isSpeaking: state.isSpeaking),
            ],
          ),

          // Status Panel (Top Left)
          Positioned(
            top: 40,
            left: 20,
            child: StatusPanel(
              cognitiveLoad: state.cognitiveLoad,
              homeostaticMode: state.homeostaticMode,
              attentionFocus: state.attentionFocus,
            ),
          ),

          // Chat Overlay (Optional/Minimal)
          if (state.chatHistory.isNotEmpty)
            Positioned(
              bottom: 120,
              left: 20,
              right: 20,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black45,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  state.chatHistory.last['text'] ?? "",
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.cyanAccent, fontSize: 18),
                ),
              ),
            ),

          // Input Bar (Bottom Center)
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Center(
              child: InputBar(
                onSend: (text) => state.sendMessage(text),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
