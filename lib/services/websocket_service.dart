// web_socket_service.dart
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:flutter/foundation.dart';
//
class WebSocketService {
  final Function(dynamic) onMessage;
  WebSocketChannel? _channel;
  // URLs de redundância
  final List<String> _urls = [
    "ws://192.168.1.160:8000/v1/stream",
    "ws://localhost:8000/v1/stream"
  ];
  int _currentUrlIndex = 0;
  bool _isManuallyClosed = false;

  WebSocketService({required this.onMessage});

  void connect() async {
    _isManuallyClosed = false;
    final String targetUrl = _urls[_currentUrlIndex];
    debugPrint("Tentando conectar WS em: $targetUrl");
    try {
      _channel = WebSocketChannel.connect(Uri.parse(targetUrl));

      // Verificação de conexão ativa (precisamos ouvir o stream para saber se funcionou)
      _channel!.stream.listen(
            (message) {
          // Se recebemos qualquer mensagem, resetamos o índice para a URL principal na próxima vez
          _currentUrlIndex = 0;
          onMessage(message);
        },
        onError: (error) {
          debugPrint("Erro no Stream WS ($targetUrl): $error");
          _handleFailure();
        },
        onDone: () {
          if (!_isManuallyClosed) {
            debugPrint("Conexão WS fechada pelo servidor ($targetUrl)");
            _handleFailure();
          }
        },
        cancelOnError: true,
      );
    } catch (e) {
      debugPrint("Exceção ao conectar WS ($targetUrl): $e");
      _handleFailure();
    }
  }

  void _handleFailure() {
    if (_isManuallyClosed) return;

    // Tenta alternar entre as URLs (0 -> 1 -> 0...)
    _currentUrlIndex = (_currentUrlIndex + 1) % _urls.length;

    debugPrint("Falha na conexão. Alternando para URL índice $_currentUrlIndex em 5 segundos...");

    // Aguarda um pouco antes de tentar a próxima para não sobrecarregar o app
    Future.delayed(const Duration(seconds: 5), () {
      if (!_isManuallyClosed) connect();
    });
  }


  void disconnect() {
    _isManuallyClosed = true;
    _channel?.sink.close();
    debugPrint("WS desconectado manualmente.");
  }
}
