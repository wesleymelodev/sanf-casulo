import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import '../providers/robot_state.dart';

class KnowledgeUploader extends StatefulWidget {
  const KnowledgeUploader({super.key});

  @override
  State<KnowledgeUploader> createState() => _KnowledgeUploaderState();
}

class _KnowledgeUploaderState extends State<KnowledgeUploader> {
  bool _isUploading = false;

  Future<void> _pickAndUploadFile() async {
    setState(() => _isUploading = true);
    
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'txt', 'md'],
      );

      if (result != null) {
        final state = context.read<RobotState>();
        final file = File(result.files.single.path!);
        final fileName = result.files.single.name;

        // Ingerir conhecimento via RobotState/KnowledgeImporter
        await state.importRuntimeFile(file, fileName);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Arquivo '$fileName' ingerido com sucesso!")),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Erro ao importar arquivo: $e")),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _isUploading
        ? const Padding(
            padding: EdgeInsets.all(8.0),
            child: SizedBox(
                width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.cyanAccent)),
          )
        : IconButton(
            icon: const Icon(Icons.upload_file, color: Colors.cyanAccent),
            tooltip: "Importar Conhecimento (PDF, TXT, MD)",
            onPressed: _pickAndUploadFile,
          );
  }
}
