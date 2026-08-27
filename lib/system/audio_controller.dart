import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import '../models/event.dart';
import '../services/cognitive_bus.dart';
import '../core/kernel.dart';

class AudioController extends LifecycleComponent {
  @override
  final String name = "audio_controller";

  final CognitiveBus _bus;
  final SpeechToText _stt = SpeechToText();
  final AudioRecorder _recorder = AudioRecorder();
  
  bool _sttInitialized = false;
  bool _isPassiveActive = false;
  bool _isActiveActive = false;
  
  Timer? _silenceTimer;
  static const Duration silenceThreshold = Duration(seconds: 10);
  
  // Volume de referência para silêncio. No 'record', a amplitude vai de -160 a 0.
  // -45dB é um valor comum para detectar silêncio em ambientes com algum ruído.
  static const double _silenceVolumeThreshold = -45.0; 

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
          debugPrint("STT Passive Status: $status");
          _bus.publish(Event(
            name: "sensor.audio.status",
            source: name,
            data: status,
            priority: 0.1,
          ));
          
          // Reinicia a escuta passiva se ela parar sozinha (timeout nativo) 
          // e não estivermos em gravação ativa
          if (status == 'notListening' && _isPassiveActive && !_isActiveActive) {
            _restartPassive();
          }
        },
        onError: (error) {
          debugPrint("STT Passive Error: $error");
          _restartPassive();
        },
      );

      if (_sttInitialized) {
        _startPassive();
      }

      // Escuta comandos de toggle do botão de UI
      _bus.subscribe("sensor.audio.toggle", (e) => _onButtonPress());
    } catch (e) {
      debugPrint("Failed to initialize AudioController: $e");
    }
  }

  void _onButtonPress() {
    if (_isActiveActive) {
      debugPrint("AudioController: Botão pressionado - Parando escuta ativa.");
      _stopActive();
    } else {
      debugPrint("AudioController: Botão pressionado - Iniciando escuta ativa.");
      _startActive();
    }
  }

  // --- Camada 1: Escuta Passiva (Background / Contexto) ---
  void _startPassive() async {
    if (!_sttInitialized || _stt.isListening || _isActiveActive) return;
    
    _isPassiveActive = true;
    debugPrint("AudioController: Iniciando escuta passiva (camada de contexto)...");
    
    try {
      await _stt.listen(
        onResult: (result) {
          if (result.finalResult) {
            _bus.publish(Event(
              name: "sensor.audio",
              source: name,
              data: result.recognizedWords,
              priority: 0.5,
              confidence: 0.8,
            ));
            print("CONTEXTO PASSIVO: ${result.recognizedWords}");
          }
        },
        localeId: 'pt_BR',
        listenMode: ListenMode.confirmation, 
        cancelOnError: false,
        partialResults: true,
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

  // --- Camada 2: Escuta Ativa (Comando / Gravação) ---
  void _startActive() async {
    if (_isActiveActive) return;

    _isActiveActive = true;
    _isPassiveActive = false; // Desativa flag da passiva

    // Para o STT para liberar o hardware do microfone para o Recorder
    await _stt.stop();

    try {
      if (await _recorder.hasPermission()) {
        final tempDir = await getTemporaryDirectory();
        final String path = "${tempDir.path}/active_audio_${DateTime.now().millisecondsSinceEpoch}.m4a";
        
        const config = RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 128000,
          sampleRate: 44100,
        );

        await _recorder.start(config, path: path);
        _bus.publish(Event(name: "ui.audio.recording.start", source: name));
        
        _startSilenceMonitor();
      } else {
        debugPrint("AudioController: Sem permissão de microfone para gravação ativa.");
        _isActiveActive = false;
        _startPassive();
      }
    } catch (e) {
      debugPrint("AudioController: Erro ao iniciar gravação ativa: $e");
      _isActiveActive = false;
      _startPassive();
    }
  }

  void _startSilenceMonitor() {
    _silenceTimer?.cancel();
    _silenceTimer = Timer(silenceThreshold, _onSilenceTimeout);

    // Monitora picos de volume para resetar o timer de silêncio
    _recorder.onAmplitudeChanged(const Duration(milliseconds: 500)).listen((amp) {
      if (!_isActiveActive) return;

      if (amp.current > _silenceVolumeThreshold) {
        // Voz/Som detectado: reseta o timeout de 10s
        if (_silenceTimer?.isActive ?? false) {
          _silenceTimer?.cancel();
          _silenceTimer = Timer(silenceThreshold, _onSilenceTimeout);
        }
      }
    });
  }

  void _onSilenceTimeout() {
    if (!_isActiveActive) return;
    debugPrint("AudioController: Silêncio de 10s detectado. Finalizando automaticamente.");
    _stopActive();
  }

  void _stopActive() async {
    if (!_isActiveActive) return;
    
    _isActiveActive = false;
    _silenceTimer?.cancel();

    try {
      final String? path = await _recorder.stop();
      _bus.publish(Event(name: "ui.audio.recording.stop", source: name));

      if (path != null) {
        debugPrint("AudioController: Gravação concluída: $path");
        _bus.publish(Event(
          name: "user.input.audio",
          source: name,
          data: path,
          priority: 0.9,
          metadata: {"type": "audio_blob"},
        ));
      }
    } catch (e) {
      debugPrint("AudioController: Erro ao parar gravação: $e");
    }

    // Reativa a escuta passiva após concluir a ativa
    _isPassiveActive = true;
    _startPassive();
  }

  @override
  void update(double deltaTime) {}

  @override
  void shutdown() {
    _stt.stop();
    _recorder.dispose();
    _silenceTimer?.cancel();
  }
}
