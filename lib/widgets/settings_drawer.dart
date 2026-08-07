import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/robot_state.dart';

class SettingsDrawer extends StatelessWidget {
  const SettingsDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<RobotState>();

    return Drawer(
      backgroundColor: const Color(0xFF00050A).withOpacity(0.9),
      child: Container(
        decoration: BoxDecoration(
          border: Border(left: BorderSide(color: Colors.cyanAccent.withOpacity(0.2))),
        ),
        child: Column(
          children: [
            const DrawerHeader(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.psychology, color: Colors.cyanAccent, size: 40),
                    SizedBox(height: 10),
                    Text(
                      "CONFIGURAÇÕES COGNITIVAS",
                      style: TextStyle(color: Colors.cyanAccent, fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 1.2),
                    ),
                  ],
                ),
              ),
            ),
            
            Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        "Temperatura do Modelo",
                        style: TextStyle(color: Colors.white, fontSize: 16),
                      ),
                      Text(
                        state.modelTemperature.toStringAsFixed(1),
                        style: const TextStyle(color: Colors.yellowAccent, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Slider(
                    value: state.modelTemperature,
                    min: 0.0,
                    max: 2.0,
                    divisions: 20,
                    activeColor: Colors.cyanAccent,
                    inactiveColor: Colors.white10,
                    onChanged: (val) => state.setModelTemperature(val),
                  ),
                  const Text(
                    "Valores baixos tornam o SANF mais preciso e literal. Valores altos aumentam a criatividade e a 'loucura' das respostas.",
                    style: TextStyle(color: Colors.white38, fontSize: 11),
                  ),

                  const SizedBox(height: 30),
                  
                  // --- MODO CONVERSAÇÃO (PROATIVIDADE) ---
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        "Modo Conversação",
                        style: TextStyle(color: Colors.white, fontSize: 16),
                      ),
                      Text(
                        "${(state.proactivityLevel * 100).toInt()}%",
                        style: const TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Slider(
                    value: state.proactivityLevel,
                    min: 0.0,
                    max: 1.0,
                    divisions: 20,
                    activeColor: Colors.cyanAccent,
                    inactiveColor: Colors.white10,
                    onChanged: (val) => state.setProactivityLevel(val),
                  ),
                  const Text(
                    "Aumente para que o SANF puxe assunto com mais frequência. No máximo, ele tentará falar a cada 1 minuto de tédio.",
                    style: TextStyle(color: Colors.white38, fontSize: 11),
                  ),

                  const SizedBox(height: 30),

                  // --- NOME DO USUÁRIO ---
                  const Text(
                    "Nome do Usuário",
                    style: TextStyle(color: Colors.white, fontSize: 16),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    decoration: InputDecoration(
                      hintText: "Como devo te chamar?",
                      hintStyle: const TextStyle(color: Colors.white24),
                      filled: true,
                      fillColor: Colors.white.withOpacity(0.05),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: Colors.cyanAccent.withOpacity(0.3)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: Colors.cyanAccent.withOpacity(0.1)),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
                    ),
                    style: const TextStyle(color: Colors.cyanAccent),
                    onSubmitted: (val) {
                      if (val.trim().isNotEmpty) {
                        state.setUserName(val.trim());
                      }
                    },
                    controller: TextEditingController(text: state.userName),
                  ),
                  const SizedBox(height: 5),
                  const Text(
                    "Isso ajuda o SANF a manter a conexão pessoal com você entre as sessões.",
                    style: TextStyle(color: Colors.white38, fontSize: 11),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
