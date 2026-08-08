import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class HelpSection extends StatelessWidget {
  const HelpSection({super.key});

  Future<void> _launchURL(String url) async {
    if (!await launchUrl(Uri.parse(url))) {
      throw Exception('Could not launch $url');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF0D1117),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500, maxHeight: 600),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    "GUIA DE CONFIGURAÇÃO",
                    style: TextStyle(
                      color: Colors.cyanAccent,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: Colors.white54),
                  )
                ],
              ),
              const Divider(color: Colors.white10),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildStep(
                        "1. Gemini API Key",
                        "Acesse o Google AI Studio e crie uma chave gratuita.",
                        "https://aistudio.google.com/app/apikey",
                      ),
                      _buildStep(
                        "2. Groq API Key",
                        "Crie uma conta no Groq Cloud e gere sua API Key para modelos rápidos.",
                        "https://console.groq.com/keys",
                      ),
                      _buildStep(
                        "3. Firebase Web Config",
                        "No Console do Firebase, vá em 'Configurações do Projeto' > 'Geral' > 'Seus aplicativos'. Adicione um app Web e copie o objeto 'firebaseConfig'.",
                        "https://console.firebase.google.com/",
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        "NOTA: Na versão Web, suas chaves são armazenadas apenas localmente no seu navegador (LocalStorage) via Hive.",
                        style: TextStyle(color: Colors.white38, fontSize: 12, fontStyle: FontStyle.italic),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStep(String title, String description, String url) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 4),
          Text(
            description,
            style: const TextStyle(color: Colors.white70, fontSize: 14),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: () => _launchURL(url),
            icon: const Icon(Icons.open_in_new, size: 16, color: Colors.cyanAccent),
            label: const Text(
              "Obter Chave",
              style: TextStyle(color: Colors.cyanAccent, fontSize: 13),
            ),
            style: TextButton.styleFrom(padding: EdgeInsets.zero, alignment: Alignment.centerLeft),
          ),
        ],
      ),
    );
  }
}
