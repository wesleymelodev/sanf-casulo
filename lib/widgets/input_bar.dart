import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import '../providers/robot_state.dart';
import '../models/event.dart';

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

  Future<void> _importImage(BuildContext context, RobotState state) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
      );

      if (result != null && result.files.single.path != null) {
        final file = File(result.files.single.path!);
        state.bus.publish(Event(
          name: "vision.analyze_file",
          source: "input_bar",
          data: file,
          priority: 0.9,
        ));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Enviando imagem para análise Gemini..."))
        );
      }
    } catch (e) {
      debugPrint("Erro ao importar imagem: $e");
    }
  }

  Future<void> _importFile(BuildContext context, RobotState state) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: false,
      );

      if (result != null && result.files.single.path != null) {
        final file = File(result.files.single.path!);
        state.importRuntimeFile(file, result.files.single.name);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Arquivo '${result.files.single.name}' importado."))
        );
      }
    } catch (e) {
      debugPrint("Erro ao importar arquivo: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<RobotState>();
    
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      // Ajuste de largura para acomodar o botão de menu sem overflow
      width: _isExpanded ? 280 : 160,
      constraints: const BoxConstraints(maxWidth: 600),
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: Colors.cyan.withOpacity(0.15),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.cyanAccent.withOpacity(0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Botão de Microfone
          Flexible(
            child: IconButton(
              icon: Icon(
                state.isListening ? Icons.stop : Icons.mic, 
                color: state.isListening ? Colors.redAccent : Colors.cyanAccent
              ),
              onPressed: () {
                state.toggleListening();
              },
            ),
          ),
          
          if (!_isExpanded) const SizedBox(width: 4),

          // Campo de Texto (Só aparece quando expandido)
          if (_isExpanded)
            Expanded(
              flex: 4,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3.0),
                child: TextField(
                  controller: _controller,
                  autofocus: true,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  decoration: const InputDecoration(
                    hintText: "Fale comigo...",
                    hintStyle: TextStyle(color: Colors.white38, fontSize: 12),
                    border: InputBorder.none,
                    isDense: true,
                  ),
                  onSubmitted: (_) => _handleSend(),
                ),
              ),
            ),

          // Botão de Teclado / Enviar
          Flexible(
            child: IconButton(
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
          ),

          // Menu de Ações (Popup)
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.cyanAccent),
            color: const Color(0xFF1A1A1A),
            onSelected: (value) {
              if (value == 'image') {
                _importImage(context, state);
              } else if (value == 'file') {
                _importFile(context, state);
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'image',
                child: Row(
                  children: [
                    Icon(Icons.image_search, color: Colors.cyanAccent),
                    SizedBox(width: 10),
                    Text("Ver Imagem (Gemini)", style: TextStyle(color: Colors.white, fontSize: 13)),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'file',
                child: Row(
                  children: [
                    Icon(Icons.upload_file, color: Colors.cyanAccent),
                    SizedBox(width: 10),
                    Text("Importar Arquivo", style: TextStyle(color: Colors.white, fontSize: 13)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
