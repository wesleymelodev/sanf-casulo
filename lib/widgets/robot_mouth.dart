// robot_mouth.dart
import 'dart:math';
import 'package:flutter/material.dart';

class RobotMouth extends StatefulWidget {
  final bool isSpeaking;
  const RobotMouth({super.key, this.isSpeaking = false});

  @override
  State<RobotMouth> createState() => _RobotMouthState();
}

class _RobotMouthState extends State<RobotMouth> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final List<double> _barHeights = List.filled(15, 0.1);
  final Random _random = Random();

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    )..addListener(() {
        if (widget.isSpeaking) {
          setState(() {
            for (int i = 0; i < _barHeights.length; i++) {
              _barHeights[i] = 0.2 + _random.nextDouble() * 0.8;
            }
          });
        } else {
          setState(() {
            for (int i = 0; i < _barHeights.length; i++) {
              _barHeights[i] = 0.1;
            }
          });
        }
      });
    _controller.repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 50, // Aumentado para acomodar a curvatura
      width: 150,
      child: Stack(
        alignment: Alignment.center,
        children: List.generate(_barHeights.length, (index) {
          // Calcula o deslocamento vertical para criar a concavidade para cima (sorriso)
          // Usamos uma parábola simples: y = a * (x - h)^2
          double x = index / (_barHeights.length - 1); // 0.0 a 1.0
          double curveOffset = -20 * pow(x - 0.5, 2) * 4; // Desloca as pontas para cima

          return Positioned(
            left: index * (150 / _barHeights.length),
            bottom: 20 - curveOffset, // Ajusta a posição base de cada barra
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 100),
              width: 8,
              height: 40 * _barHeights[index],
              decoration: BoxDecoration(
                color: Colors.yellowAccent,
                borderRadius: BorderRadius.circular(4),
                boxShadow: [
                  BoxShadow(
                    color: Colors.yellow.withOpacity(0.5),
                    blurRadius: 5,
                    spreadRadius: 1,
                  )
                ],
              ),
            ),
          );
        }),
      ),
    );
  }
}
