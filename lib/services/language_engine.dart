import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import '../models/event.dart';
import 'cognitive_bus.dart';

class LanguageEngine {
  final CognitiveBus _bus;
  final String name = "language_engine";

  final String geminiKey = const String.fromEnvironment('GEMINI_API_KEY');
  final String groqKey = const String.fromEnvironment('GROQ_API_KEY');
  final String cfKey = const String.fromEnvironment('CLOUDFLARE_API_TOKEN');
  final String cfAccount = const String.fromEnvironment('CLOUDFLARE_ACCOUNT_ID');
  final String ollamaHost = const String.fromEnvironment('OLLAMA_HOST', defaultValue: "http://localhost:11434");

  LanguageEngine(this._bus);

  void handleEvent(Event event) {
    if (event.name == "workspace.updated") {
      final sourceEvent = event.data.event as Event;
      
      // Filter out pulses and metrics
      if (sourceEvent.name == "sensor.pulse" || sourceEvent.name == "system.metrics.updated") {
        return;
      }

      // Check if it's a direct input or directed audio
      bool shouldRespond = false;
      if (sourceEvent.source == "brain_visualizer" || 
          sourceEvent.source == "terminal_sensor" || 
          sourceEvent.source == "input_bar") {
        shouldRespond = true;
      } else if (sourceEvent.name == "sensor.audio") {
        final text = sourceEvent.data.toString().toLowerCase();
        final vocativos = ["sanf", "surf", "samf", "salf", "nexus", "spectrum", "você", "voce"];
        shouldRespond = vocativos.any((v) => text.contains(v)) || text.endsWith("?");
      }

      if (shouldRespond) {
        _processQuery(sourceEvent.data.toString());
      }
    }
  }

  void _processQuery(String query) async {
    // Cognitive delay simulation
    await Future.delayed(const Duration(milliseconds: 500));
    
    final response = await _executeFallbackChain(query);
    _publishResponse(response);
  }

  Future<String> _executeFallbackChain(String query) async {
    final history = _bus.history
        .where((e) => e.name == "cognition.response" || e.source == "input_bar")
        .take(10)
        .toList();

    final systemPrompt = "Você é o SANF (Spectrum Ancrolyn Nexus Fractal), um sistema cognitivo amigável.";

    // mantenha esses modelos exatamente assim, não altere em hipotese alguma
    // Fallback Chain: Ollama -> Gemini -> Groq -> Cloudflare
    final attempts = [
      () => _tryOllama("gemma3:1b", systemPrompt, query),
      () => _tryGemini("gemini-3.6-flash", systemPrompt, query),
      () => _tryGroq("openai/gpt-oss-120b", systemPrompt, query),
      () => _tryCloudflare("@cf/meta/llama-3.1-8b-instruct", systemPrompt, query),
    ];

    for (var attempt in attempts) {
      try {
        final result = await attempt();
        if (result != null) return result;
      } catch (e) {
        debugPrint("Language Engine Attempt Failed: $e");
      }
    }

    return "Sinto muito, meus sistemas de linguagem estão temporariamente offline.";
  }

  Future<String?> _tryGemini(String model, String system, String query) async {
    if (geminiKey.isEmpty) return null;
    final url = "https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent?key=$geminiKey";
    
    final response = await http.post(
      Uri.parse(url),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        "contents": [{"parts": [{"text": "$system\n\nUsuário: $query"}]}],
        "generationConfig": {"temperature": 1.0, "maxOutputTokens": 2048}
      }),
    ).timeout(const Duration(seconds: 30));

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['candidates'][0]['content']['parts'][0]['text'];
    }
    return null;
  }

  Future<String?> _tryGroq(String model, String system, String query) async {
    if (groqKey.isEmpty) return null;
    final url = "https://api.groq.com/openai/v1/chat/completions";
    
    final response = await http.post(
      Uri.parse(url),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $groqKey'
      },
      body: jsonEncode({
        "model": model,
        "messages": [
          {"role": "system", "content": system},
          {"role": "user", "content": query}
        ],
        "temperature": 1.0
      }),
    ).timeout(const Duration(seconds: 20));

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['choices'][0]['message']['content'];
    }
    return null;
  }

  Future<String?> _tryOllama(String model, String system, String query) async {
    final url = "$ollamaHost/api/generate";
    
    final response = await http.post(
      Uri.parse(url),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        "model": model,
        "prompt": "$system\n\nUsuário: $query",
        "stream": false
      }),
    ).timeout(const Duration(seconds: 300));

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['response'];
    }
    return null;
  }

  Future<String?> _tryCloudflare(String model, String system, String query) async {
    if (cfKey.isEmpty || cfAccount.isEmpty) return null;
    final url = "https://api.cloudflare.com/client/v4/accounts/$cfAccount/ai/run/$model";
    
    final response = await http.post(
      Uri.parse(url),
      headers: {'Authorization': 'Bearer $cfKey'},
      body: jsonEncode({
        "messages": [
          {"role": "system", "content": system},
          {"role": "user", "content": query}
        ]
      }),
    ).timeout(const Duration(seconds: 30));

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['result']['response'];
    }
    return null;
  }

  void _publishResponse(String text) {
    _bus.publish(Event(
      name: "cognition.response",
      source: name,
      data: text,
      priority: 0.5,
    ));
  }
}
