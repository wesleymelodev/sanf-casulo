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
      width: _isExpanded ? 300 : 60,
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: Colors.cyan.withOpacity(0.2),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.cyanAccent.withOpacity(0.5)),
      ),
      child: Row(
        children: [
          IconButton(
            icon: Icon(
              state.isListening ? Icons.stop : Icons.mic, 
              color: state.isListening ? Colors.redAccent : Colors.cyanAccent
            ),
            onPressed: () {
              state.toggleListening();
            },
          ),
          const Spacer(),
          if (_isExpanded)
            Expanded(
              flex: 10,
              child: TextField(
                controller: _controller,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  hintText: "Digite algo...",
                  hintStyle: TextStyle(color: Colors.white54),
                  border: InputBorder.none,
                ),
                onSubmitted: (_) => _handleSend(),
              ),
            ),
          IconButton(
            icon: Icon(_isExpanded ? Icons.send : Icons.keyboard, color: Colors.cyanAccent),
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
