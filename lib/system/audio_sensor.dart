import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_to_text.dart';
import '../models/event.dart';
import '../services/cognitive_bus.dart';
import '../core/kernel.dart';

class AudioSensor extends LifecycleComponent {
  @override
  final String name = "audio_sensor";

  final CognitiveBus _bus;
  final SpeechToText _speechToText = SpeechToText();
  bool _isInitialized = false;
  bool _isListening = false;

  AudioSensor(this._bus);

  @override
  void initialize() async {
    if (Platform.isWindows) {
      debugPrint("AudioSensor: Desativado no Windows por compatibilidade.");
      return;
    }
    try {
      _isInitialized = await _speechToText.initialize(
        onStatus: (status) {
          debugPrint("AudioSensor Status: $status");
          if (status == 'notListening' && _isListening) {
            _restartListening();
          }
        },
        onError: (error) {
          debugPrint("AudioSensor Error: $error");
          // On Windows, SAPI error 80045077 usually means Portuguese not installed or Mic blocked
          _restartListening();
        },
      );

      if (_isInitialized) {
        _startPassiveListening();
      } else {
        debugPrint("AudioSensor failed to initialize.");
      }
    } catch (e) {
      debugPrint("Failed to initialize AudioSensor: $e");
    }
  }

  void _startPassiveListening() async {
    if (!_isInitialized) return;
    _isListening = true;
    
    debugPrint("AudioSensor: Starting passive listen...");
    await _speechToText.listen(
      onResult: (result) {
        if (result.finalResult) {
          _publishAudioEvent(result.recognizedWords);
        }
      },
      localeId: 'pt_BR',
      listenMode: ListenMode.confirmation, 
      cancelOnError: false,
      partialResults: true, // Enable partial results for better re-triggering logic
    );
  }

  void _restartListening() {
    // Small delay to prevent tight loops in case of constant errors
    Future.delayed(const Duration(seconds: 1), () {
      if (_isListening) {
        _startPassiveListening();
      }
    });
  }

  void _publishAudioEvent(String text) {
    if (text.isEmpty) return;

    _bus.publish(Event(
      name: "sensor.audio",
      source: name,
      data: text,
      priority: 0.5,
      confidence: 0.8,
      novelty: 0.7,
    ));
    print("OUVIDO: $text");
  }

  @override
  void update(double deltaTime) {
    // No specific per-cycle logic needed as STT uses callbacks
  }

  @override
  void shutdown() {
    _isListening = false;
    _speechToText.stop();
  }
}
