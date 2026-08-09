import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';

class KnowledgeSeeder {
  static Future<void> seedIfNecessary() async {
    if (kIsWeb) return; // O Hive na Web usa IndexedDB e não suporta seeding via arquivo local assim
    try {
      // getApplicationDocumentsDirectory() é o padrão do Hive.initFlutter()
      final directory = await getApplicationDocumentsDirectory();
      final path = directory.path;
      
      debugPrint("Verificando sementes de conhecimento em: $path");
      
      await _copyAssetToLocal(
        'assets/knowledge_seed/semantic_memory_store.hive', 
        '$path/semantic_memory_store.hive'
      );
      
      await _copyAssetToLocal(
        'assets/knowledge_seed/knowledge_status.hive', 
        '$path/knowledge_status.hive'
      );
      
      debugPrint("Seed de conhecimento finalizado.");
    } catch (e) {
      debugPrint("Erro no KnowledgeSeeder: $e");
    }
  }

  static Future<void> _copyAssetToLocal(String assetPath, String localPath) async {
    final file = File(localPath);
    
    // Só copia se o arquivo local ainda não existir (preserva o que o usuário já aprendeu)
    if (!await file.exists()) {
      debugPrint("Copiando asset $assetPath para $localPath");
      final byteData = await rootBundle.load(assetPath);
      final bytes = byteData.buffer.asUint8List(
        byteData.offsetInBytes, 
        byteData.lengthInBytes
      );
      await file.writeAsBytes(bytes);
    }
  }
}
