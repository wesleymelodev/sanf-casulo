import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/robot_state.dart';

class InputBar extends StatefulWidget {
  final Function(String) onSend;
  const InputBar({super.key, required this.onSend});

  @override
  State<InputBar> createState() => _InputBarState();
}

class _InputBarState extends State<InputBar> {
  final TextEditingController _controller = TextEditingController();
  bool _isExpanded = false;

  void _handleSend() {
    if (_controller.text.isNotEmpty) {
      widget.onSend(_controller.text);
      _controller.clear();
      setState(() => _isExpanded = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<RobotState>();
    
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      // Aumentamos a largura base para caber os dois ícones com conforto
      width: _isExpanded ? 350 : 120, 
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.cyan.withOpacity(0.15),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.cyanAccent.withOpacity(0.4)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Botão de Microfone
          IconButton(
            icon: Icon(
              state.isListening ? Icons.stop : Icons.mic, 
              color: state.isListening ? Colors.redAccent : Colors.cyanAccent
            ),
            onPressed: () {
              state.toggleListening();
            },
          ),
          
          // Espaçamento interno quando não expandido
          if (!_isExpanded) const SizedBox(width: 8),

          // Campo de Texto (Só aparece quando expandido)
          if (_isExpanded)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                child: TextField(
                  controller: _controller,
                  autofocus: true,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    hintText: "Fale comigo...",
                    hintStyle: TextStyle(color: Colors.white38),
                    border: InputBorder.none,
                  ),
                  onSubmitted: (_) => _handleSend(),
                ),
              ),
            ),

          // Botão de Teclado / Enviar
          IconButton(
            icon: Icon(
              _isExpanded ? Icons.send : Icons.keyboard, 
              color: Colors.cyanAccent
            ),
            onPressed: () {
              if (!_isExpanded) {
                setState(() => _isExpanded = true);
              } else {
                _handleSend();
              }
            },
          ),
        ],
      ),
    );
  }
}
