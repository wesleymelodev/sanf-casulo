import 'dart:math';
import '../models/event.dart';
import '../services/cognitive_bus.dart';
import '../core/kernel.dart';

class EnvironmentalSensor extends LifecycleComponent {
  final CognitiveBus _bus;
  double? _lastLux;
  double? _lastProximity;
  
  // Acelerômetro
  double _lastX = 0, _lastY = 0, _lastZ = 0;
  bool _isFaceDown = false;
  DateTime? _lastShakeTime;

  EnvironmentalSensor(this._bus);

  @override
  String get name => "environmental_sensor";

  @override
  void initialize() {
    _bus.subscribe("sensor.light", _onLightChanged);
    _bus.subscribe("sensor.proximity", _onProximityChanged);
    _bus.subscribe("sensor.accelerometer", _onAccelerometerChanged);
  }

  void _onLightChanged(Event event) {
    final double lux = (event.data as num).toDouble();
    
    // Filtro de relevância
    bool isSignificant = _lastLux == null || (lux - _lastLux!).abs() > 200 || (lux < 10 && _lastLux! >= 10) || (lux > 1000 && _lastLux! <= 1000);
    
    if (isSignificant) {
      String description = _getLuxDescription(lux);
      _bus.publish(Event(
        name: "cognition.perception.environmental",
        source: name,
        data: "Luminosidade ambiente: $description ($lux lux)",
        priority: (lux < 10 || lux > 5000) ? 0.7 : 0.4
      ));

      if (lux < 5) {
        _dispatchDeviceAction("brightness", 0.05);
      } else if (lux > 8000) {
        _dispatchDeviceAction("brightness", 1.0);
      }

      _lastLux = lux;
    }
  }

  void _onAccelerometerChanged(Event event) {
    final Map data = event.data as Map;
    final double x = (data['x'] as num).toDouble();
    final double y = (data['y'] as num).toDouble();
    final double z = (data['z'] as num).toDouble();

    // 1. Detecção de Shake (Sacudida)
    double acceleration = sqrt(x * x + y * y + z * z) - 9.8;
    if (acceleration.abs() > 12) { // Threshold de sacudida
      final now = DateTime.now();
      if (_lastShakeTime == null || now.difference(_lastShakeTime!).inMilliseconds > 1000) {
        _lastShakeTime = now;
        _bus.publish(Event(
          name: "cognition.perception.environmental",
          source: name,
          data: "Movimento brusco detectado (Sacudida)",
          priority: 0.8
        ));
      }
    }

    // 2. Detecção de Orientação (Face Down)
    // Se Z for muito negativo, o celular está de bruços
    bool faceDown = z < -8.0;
    if (faceDown != _isFaceDown) {
      _isFaceDown = faceDown;
      _bus.publish(Event(
        name: "cognition.perception.environmental",
        source: name,
        data: _isFaceDown ? "Dispositivo virado para baixo (Privacidade)" : "Dispositivo virado para cima",
        priority: _isFaceDown ? 0.9 : 0.5
      ));

      if (_isFaceDown) {
        _dispatchDeviceAction("vibrate", 50); // Feedback tátil curto
      }
    }

    _lastX = x; _lastY = y; _lastZ = z;
  }

  void _dispatchDeviceAction(String type, dynamic value) {
    _bus.publish(Event(
      name: "device.action.execute",
      source: name,
      data: [{ "type": type, "value": value }],
      priority: 0.1 
    ));
  }

  void _onProximityChanged(Event event) {
    final double cm = (event.data as num).toDouble();
    if (_lastProximity == null || _lastProximity != cm) {
      String status = cm < 5 ? "Objeto muito próximo detectado" : "Caminho livre";
      _bus.publish(Event(
        name: "cognition.perception.environmental",
        source: name,
        data: "Proximidade: $status ($cm cm)",
        priority: cm < 5 ? 0.8 : 0.3
      ));
      _lastProximity = cm;
    }
  }

  String _getLuxDescription(double lux) {
    if (lux < 5) return "Breu total";
    if (lux < 50) return "Muito escuro";
    if (lux < 200) return "Iluminação fraca";
    if (lux < 1000) return "Ambiente bem iluminado";
    if (lux < 5000) return "Muito claro";
    return "Luz solar intensa";
  }

  @override
  void shutdown() {
    _bus.unsubscribe("sensor.light", _onLightChanged);
    _bus.unsubscribe("sensor.proximity", _onProximityChanged);
    _bus.unsubscribe("sensor.accelerometer", _onAccelerometerChanged);
  }

  @override
  void update(double deltaTime) {}
}
