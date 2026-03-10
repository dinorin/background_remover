import 'package:flutter/material.dart';

class CheckerboardBackground extends StatelessWidget {
  final Widget child;
  const CheckerboardBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _Painter(),
      child: child,
    );
  }
}

class _Painter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const t = 16.0;
    final a = Paint()..color = const Color(0xFF2A2A2A);
    final b = Paint()..color = const Color(0xFF1F1F1F);
    for (double y = 0; y < size.height; y += t) {
      for (double x = 0; x < size.width; x += t) {
        final even = ((x ~/ t) + (y ~/ t)) % 2 == 0;
        canvas.drawRect(Rect.fromLTWH(x, y, t, t), even ? a : b);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
