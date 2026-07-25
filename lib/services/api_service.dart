// api_service.dart
import 'dart:convert';
import 'package:flutter/cupertino.dart';
import 'package:http/http.dart' as http;

class ApiService {
  final String baseUrl = "http://192.168.1.160:8000/v1";
  final String token = "REMOTE_AUTH_TOKEN"; // Recommended to move to secure storage or env

  Future<void> interact(String text) async {
    try {
      final response = await http.post(
        Uri.parse("$baseUrl/interact"),
        headers: {
          "Content-Type": "application/json",
          "Authorization": "Bearer $token",
        },
        body: jsonEncode({"text": text}),
      ).timeout(const Duration(seconds: 10)); // Adicionado timeout

      if (response.statusCode != 200 && response.statusCode != 202) {
        debugPrint("Erro API: ${response.body}");
      }
    } catch (e) {
      debugPrint("Falha na comunicação: $e");
    }
  }
}
