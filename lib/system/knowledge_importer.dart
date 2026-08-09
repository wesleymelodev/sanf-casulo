import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';
import '../models/event.dart';
import '../services/cognitive_bus.dart';
import '../core/kernel.dart';

class KnowledgeImporter extends LifecycleComponent {
  @override
  final String name = "knowledge_importer";
  
  final CognitiveBus _bus;
  late Box _statusBox;
  String? _resolvedKnowledgePath;

  KnowledgeImporter(this._bus);

  @override
  void initialize() async {
    _statusBox = await Hive.openBox('knowledge_status');
    
    if (kIsWeb) return; // Sistema de arquivos local não suportado na Web
    
    // Resolve o caminho dinamicamente baseado na plataforma
    final directory = await getApplicationDocumentsDirectory();
    _resolvedKnowledgePath = "${directory.path}/knowledge";
    
    // Garante que a pasta existe para evitar erros de "não encontrado"
    final folder = Directory(_resolvedKnowledgePath!);
    if (!await folder.exists()) {
      await folder.create(recursive: true);
    }
    
    // DELAY DE SEGURANÇA: Espera o Kernel e a Memória Semântica estabilizarem
    Future.delayed(const Duration(seconds: 15), () => _scanKnowledgeBase());
  }

  Future<void> _scanKnowledgeBase() async {
    if (_resolvedKnowledgePath == null) return;
    
    final directory = Directory(_resolvedKnowledgePath!);
    final List<FileSystemEntity> files = directory.listSync();
    
    for (var file in files) {
      if (file is File && (
          file.path.endsWith(".pdf") || 
          file.path.endsWith(".txt") || 
          file.path.endsWith(".md")
      )) {
        final fileName = file.path.split(Platform.pathSeparator).last;
        
        if (!_statusBox.containsKey(fileName)) {
          await processFile(file, fileName);
        }
      }
    }
  }

  Future<void> processFile(File file, String fileName) async {
    try {
      String content = "";
      if (fileName.endsWith(".txt") || fileName.endsWith(".md")) {
        content = await file.readAsString();
        
        // Quebra o texto em chunks de ~500 caracteres para melhor indexação
        final chunks = _splitIntoChunks(content, 500);
        
        for (var i = 0; i < chunks.length; i++) {
          _bus.publish(Event(
            name: "cognition.learning.fact",
            source: name,
            data: "Fato extraído de $fileName (Parte ${i+1}): ${chunks[i]}",
            confidence: 1.0,
            priority: 0.8,
          ));
        }
      } else if (fileName.endsWith(".pdf")) {
        // Marcação simples para PDF (Conversão manual para TXT recomendada para ler conteúdo)
        content = "O arquivo PDF '$fileName' foi catalogado na base de conhecimento.";
        _bus.publish(Event(
          name: "cognition.learning.fact",
          source: name,
          data: content,
          confidence: 1.0,
          priority: 0.5,
        ));
      }

      await _statusBox.put(fileName, DateTime.now().toIso8601String());
      print("Conhecimento de '$fileName' processado e indexado.");
    } catch (e) {
      print("Erro ao indexar arquivo $fileName: $e");
    }
  }

  List<String> _splitIntoChunks(String text, int size) {
    List<String> chunks = [];
    for (var i = 0; i < text.length; i += size) {
      chunks.add(text.substring(i, i + size > text.length ? text.length : i + size));
    }
    return chunks;
  }

  @override
  void update(double deltaTime) {
    // Poderia escanear periodicamente se novos arquivos forem adicionados
  }

  @override
  void shutdown() {}
}
