import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:flutter/foundation.dart';

class WebSocketService {
  final Function(dynamic) onMessage;
  WebSocketChannel? _channel;
  final String url = "ws://127.0.0.1:8000/v1/stream";

  WebSocketService({required this.onMessage});

  void connect() {
    try {
      _channel = WebSocketChannel.connect(Uri.parse(url));
      _channel!.stream.listen(
        (message) => onMessage(message),
        onError: (error) {
          debugPrint("WS Error: $error");
          _reconnect();
        },
        onDone: () {
          debugPrint("WS Connection closed");
          _reconnect();
        },
      );
      debugPrint("WS Connected to $url");
    } catch (e) {
      debugPrint("WS Connection Exception: $e");
      _reconnect();
    }
  }

  void _reconnect() {
    Future.delayed(const Duration(seconds: 3), () {
      debugPrint("Attempting to reconnect WS...");
      connect();
    });
  }

  void disconnect() {
    _channel?.sink.close();
  }
}
