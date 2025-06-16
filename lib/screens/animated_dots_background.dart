import 'dart:math';
import 'package:flutter/material.dart';

class AnimatedDotsBackground extends StatefulWidget {
  const AnimatedDotsBackground({super.key});

  @override
  State<AnimatedDotsBackground> createState() => _AnimatedDotsBackgroundState();
}

class _AnimatedDotsBackgroundState extends State<AnimatedDotsBackground>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  List<Dot> dots = [];

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 20),
    )..repeat();

    // Initialize dots
    _initializeDots();
  }

  void _initializeDots() {
    const numberOfDots = 150;
    final random = Random();
    for (int i = 0; i < numberOfDots; i++) {
      dots.add(Dot(
        x: random.nextDouble(),
        y: random.nextDouble(),
        radius: random.nextDouble() * 2 + 1, // Size between 1 and 3
        speedX: (random.nextDouble() - 0.5) * 0.002, // Speed between -0.001 and 0.001
        speedY: (random.nextDouble() - 0.5) * 0.002,
      ));
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        // Update dot positions
        for (var dot in dots) {
          dot.x += dot.speedX;
          dot.y += dot.speedY;

          // Wrap around when dots move off-screen
          if (dot.x < 0) dot.x = 1.0;
          if (dot.x > 1) dot.x = 0.0;
          if (dot.y < 0) dot.y = 1.0;
          if (dot.y > 1) dot.y = 0.0;
        }

        return CustomPaint(
          painter: DotsPainter(dots: dots),
          size: Size.infinite,
        );
      },
    );
  }
}

class Dot {
  double x;
  double y;
  double radius;
  double speedX;
  double speedY;

  Dot({
    required this.x,
    required this.y,
    required this.radius,
    required this.speedX,
    required this.speedY,
  });
}

class DotsPainter extends CustomPainter {
  final List<Dot> dots;

  DotsPainter({required this.dots});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.8)
      ..style = PaintingStyle.fill;

    for (var dot in dots) {
      canvas.drawCircle(
        Offset(dot.x * size.width, dot.y * size.height),
        dot.radius,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}