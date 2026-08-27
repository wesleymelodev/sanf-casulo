import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:path_provider/path_provider.dart';
import '../models/event.dart';
import '../services/cognitive_bus.dart';
import '../core/kernel.dart';

class AudioController extends LifecycleComponent {
  @override
  final String name = "audio_controller";

  final CognitiveBus _bus;
  final SpeechToText _stt = SpeechToText();
  
  bool _sttInitialized = false;
  bool _isPassiveActive = false;
  bool _isActiveActive = false;
  
  Timer? _silenceTimer;
  static const Duration silenceThreshold = Duration(seconds: 10);
  String _accumulatedText = ""; 

  AudioController(this._bus);

  @override
  void initialize() async {
    if (Platform.isWindows) {
      debugPrint("AudioController: Desativado no Windows por compatibilidade.");
      return;
    }

    try {
      _sttInitialized = await _stt.initialize(
        onStatus: (status) {
          debugPrint("STT Status: $status");
          _bus.publish(Event(
            name: "sensor.audio.status",
            source: name,
            data: status,
            priority: 0.1,
          ));
          
          if (status == 'notListening') {
            if (_isActiveActive) {
              // Na escuta ativa, se o STT parar sozinho (timeout interno), 
              // verificamos se devemos reiniciar ou finalizar.
              _handleActiveStatusChange();
            } else if (_isPassiveActive) {
              _restartPassive();
            }
          }
        },
        onError: (error) {
          debugPrint("STT Error: $error");
          if (!_isActiveActive) _restartPassive();
        },
      );

      if (_sttInitialized) {
        _startPassive();
      }

      _bus.subscribe("sensor.audio.toggle", (e) => _onButtonPress());
    } catch (e) {
      debugPrint("Failed to initialize AudioController: $e");
    }
  }

  void _onButtonPress() {
    if (_isActiveActive) {
      _stopActive();
    } else {
      _startActive();
    }
  }

  // --- Camada 1: Escuta Passiva (Background / Contexto / Wake Word) ---
  void _startPassive() async {
    if (!_sttInitialized || _stt.isListening || _isActiveActive) return;
    
    _isPassiveActive = true;
    debugPrint("AudioController: Iniciando escuta passiva...");
    
    try {
      await _stt.listen(
        onResult: (result) {
          if (result.finalResult) {
            final text = result.recognizedWords;
            _bus.publish(Event(
              name: "sensor.audio",
              source: name,
              data: text,
              priority: 0.5,
              confidence: 0.8,
            ));

            if (_isWakeWordDetected(text)) {
              _bus.publish(Event(
                name: "system.wake_up",
                source: name,
                data: text,
                priority: 1.0,
              ));
            }
          }
        },
        localeId: 'pt_BR',
        listenMode: ListenMode.confirmation, 
        cancelOnError: false,
      );
    } catch (e) {
      debugPrint("AudioController: Erro na escuta passiva: $e");
      _isPassiveActive = false;
    }
  }

  void _restartPassive() {
    if (!_isPassiveActive || _isActiveActive) return;
    Future.delayed(const Duration(seconds: 2), () {
      if (_isPassiveActive && !_isActiveActive && !_stt.isListening) {
        _startPassive();
      }
    });
  }

  // --- Camada 2: Escuta Ativa (Comando Local / Sem Backend) ---
  void _startActive() async {
    if (_isActiveActive) return;

    _isActiveActive = true;
    _isPassiveActive = false;
    _accumulatedText = "";

    await _stt.stop();
    debugPrint("AudioController: Iniciando escuta ativa (10s de tolerância)...");
    
    _bus.publish(Event(name: "ui.audio.recording.start", source: name));
    _listenActive();
  }

  void _listenActive() async {
    if (!_isActiveActive) return;

    try {
      await _stt.listen(
        onResult: (result) {
          _accumulatedText = result.recognizedWords;
          // Reseta o timer de silêncio a cada nova palavra detectada
          _resetSilenceTimer();
        },
        localeId: 'pt_BR',
        listenMode: ListenMode.dictation,
        cancelOnError: false,
        partialResults: true,
      );
      _resetSilenceTimer();
    } catch (e) {
      debugPrint("AudioController: Erro no listen ativo: $e");
      _stopActive();
    }
  }

  void _resetSilenceTimer() {
    _silenceTimer?.cancel();
    _silenceTimer = Timer(silenceThreshold, _onSilenceTimeout);
  }

  void _handleActiveStatusChange() {
    // Se o STT parou mas o timer de silêncio ainda não venceu, 
    // reiniciamos a escuta para continuar capturando a frase longa.
    if (_isActiveActive && (_silenceTimer?.isActive ?? false)) {
      _listenActive();
    }
  }

  void _onSilenceTimeout() {
    debugPrint("AudioController: 10s de silêncio atingidos.");
    _stopActive();
  }

  void _stopActive() async {
    if (!_isActiveActive) return;
    
    _isActiveActive = false;
    _silenceTimer?.cancel();
    await _stt.stop();

    _bus.publish(Event(name: "ui.audio.recording.stop", source: name));

    if (_accumulatedText.isNotEmpty) {
      debugPrint("AudioController: Comando capturado: $_accumulatedText");
      _bus.publish(Event(
        name: "user.input",
        source: "audio_controller_active",
        data: _accumulatedText,
        priority: 0.9,
        metadata: {"from_audio": true},
      ));
    }

    _isPassiveActive = true;
    _startPassive();
  }

  bool _isWakeWordDetected(String text) {
    final lowerText = text.toLowerCase();
    final wakeVariations = [
      'sanf', 'samf', 'surf', 'surfe', 'samp', 'soft', 'super', 'shuffle', 
      'soma', 'sonf', 'sang', 'sunf', 'saint', 'self', 'safe', 'sound', 
      'smart', 'snf', 'saph', 'senf', 'salf', 'san', 'sam', 'sâmf', 'sânf'
    ];
    return wakeVariations.any((variation) => lowerText.contains(variation));
  }

  @override
  void update(double deltaTime) {}

  @override
  void shutdown() {
    _stt.stop();
    _silenceTimer?.cancel();
  }
}
