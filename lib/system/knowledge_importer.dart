import 'dart:io';
import 'package:hive/hive.dart';
import '../models/event.dart';
import '../services/cognitive_bus.dart';
import '../core/kernel.dart';

class KnowledgeImporter extends LifecycleComponent {
  @override
  final String name = "knowledge_importer";
  
  final CognitiveBus _bus;
  late Box _statusBox;
  final String knowledgePath = "lib/knowledge";

  KnowledgeImporter(this._bus);

  @override
  void initialize() async {
    _statusBox = await Hive.openBox('knowledge_status');
    _scanKnowledgeBase();
  }

  Future<void> _scanKnowledgeBase() async {
    final directory = Directory(knowledgePath);
    if (!await directory.exists()) {
      print("Diretório de conhecimento não encontrado: $knowledgePath");
      return;
    }

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
      } else if (fileName.endsWith(".pdf")) {
        content = "Documento PDF: $fileName. Conteúdo integrado para processamento semântico futuro.";
      }

      // Publica o fato para a memória semântica
      _bus.publish(Event(
        name: "cognition.learning.fact",
        source: name,
        data: "Conhecimento de $fileName: $content",
        confidence: 1.0,
        priority: 0.8,
      ));

      await _statusBox.put(fileName, DateTime.now().toIso8601String());
      print("Arquivo processado e integrado: $fileName");
    } catch (e) {
      print("Erro ao processar arquivo $fileName: $e");
    }
  }

  @override
  void update(double deltaTime) {
    // Poderia escanear periodicamente se novos arquivos forem adicionados
  }

  @override
  void shutdown() {}
}
