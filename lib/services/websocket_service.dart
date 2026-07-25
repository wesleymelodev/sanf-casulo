// web_socket_service.dart
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:flutter/foundation.dart';
//
class WebSocketService {
  final Function(dynamic) onMessage;
  WebSocketChannel? _channel;
  final String url = "ws://192.168.1.160:8000/v1/stream"; // Update with production URL if needed

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
    } catch (e) {
      debugPrint("WS Connection Exception: $e");
      _reconnect();
    }
  }

  void _reconnect() {
    Future.delayed(const Duration(seconds: 5), () {
      debugPrint("Attempting to reconnect WS...");
      connect();
    });
  }

  void disconnect() {
    _channel?.sink.close();
  }
}
