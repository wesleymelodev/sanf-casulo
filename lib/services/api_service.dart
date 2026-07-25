// api_service.dart
import 'dart:convert';
import 'package:flutter/cupertino.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

class ApiService {
  // Lista de URLs para redundância (Produção/IP e Localhost)
  final List<String> _baseUrls = [ "http://192.168.1.160:8000/v1", "http://localhost:8000/v1" ];
  // Índice para lembrar qual URL funcionou por último (otimização)
  int _currentUrlIndex = 0;
  // Busca o token do ambiente (passado no build ou run)
  // GETTER HÍBRIDO
  static String get token {
    // 1. Tenta buscar do comando --dart-define (Compilação)
    const compileTimeToken = String.fromEnvironment('REMOTE_AUTH_TOKEN');
    if (compileTimeToken.isNotEmpty) return compileTimeToken;

    // 2. Se não achar, tenta buscar do arquivo .env (Tempo de execução)
    return dotenv.env['REMOTE_AUTH_TOKEN'] ?? '';
  }

  Future<void> interact(String text) async {
    int attempts = 0; bool success = false;
    // Tenta percorrer a lista de URLs disponíveis
    while (attempts < _baseUrls.length && !success) {
      final String url = "${_baseUrls[_currentUrlIndex]}/interact";

      try {
        debugPrint("Tentando interação via: $url");

        final response = await http.post(
          Uri.parse(url),
          headers: {
            "Content-Type": "application/json",
            "Authorization": "Bearer $token",
          },
          body: jsonEncode({"text": text}),
        ).timeout(const Duration(seconds: 8)); // Timeout ligeiramente menor para falha rápida

        if (response.statusCode == 200 || response.statusCode == 202) {
          success = true;
          debugPrint("Interação bem-sucedida via $url");
          // Mantém este índice como o preferencial para a próxima chamada
        } else {
          debugPrint("Servidor respondeu com erro (${response.statusCode}) em $url. Tentando próxima...");
          _rotateUrl();
        }
      } catch (e) {
        debugPrint("Falha de conexão em $url: $e. Tentando próxima...");
        _rotateUrl();
      }

      attempts++;
    }

    if (!success) {
      throw Exception("O SANF está inacessível em todas as rotas configuradas.");
    }
  }

  void _rotateUrl() {
    _currentUrlIndex = (_currentUrlIndex + 1) % _baseUrls.length;
  }
}
