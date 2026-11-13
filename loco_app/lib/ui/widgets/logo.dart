import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme.dart';

/// The LOCO logo, drawn with code (no image files, always sharp).
/// Same geometry as the website: a dark tile with X and O, plus the LOCO wordmark.
class LocoPaint {
  static void mark(Canvas canvas) {
    // 64 x 64 design units
    final tile = RRect.fromRectAndRadius(const Rect.fromLTWH(0, 0, 64, 64), const Radius.circular(15));
    canvas.drawRRect(tile, Paint()..color = LC.darkBg);

    final border = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..shader = const LinearGradient(
        colors: [LC.purple, LC.pink],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(const Rect.fromLTWH(0, 0, 64, 64));
    canvas.drawRRect(
      RRect.fromRectAndRadius(const Rect.fromLTWH(1, 1, 62, 62), const Radius.circular(14)),
      border,
    );
    x(canvas, const Rect.fromLTWH(12, 12, 20, 20), 7);
    ring(canvas, const Offset(44, 44), 9, 7);
  }

  /// An X drawn inside [r] (two crossing round lines, blue to purple).
  static void x(Canvas canvas, Rect r, double stroke) {
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..shader = const LinearGradient(
        colors: [LC.blue, LC.purple],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(r);
    canvas.drawLine(r.topLeft, r.bottomRight, p);
    canvas.drawLine(r.topRight, r.bottomLeft, p);
  }

  static void ring(Canvas canvas, Offset c, double radius, double stroke) {
    canvas.drawCircle(
      c,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = LC.pink,
    );
  }

  /// The word "LOCO", 334 x 96 design units. Letters are strokes, so no font is needed.
  static void word(Canvas canvas) {
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 14
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..shader = const LinearGradient(
        colors: [LC.purple, LC.blue, LC.pink],
        stops: [0, 0.55, 1],
      ).createShader(const Rect.fromLTWH(14, 0, 305, 96));

    final l = Path()
      ..moveTo(21, 21)
      ..lineTo(21, 75)
      ..lineTo(58, 75);
    canvas.drawPath(l, p);
    canvas.drawCircle(const Offset(121, 48), 27, p);
    canvas.drawArc(
      Rect.fromCircle(center: const Offset(203, 48), radius: 27),
      40 * math.pi / 180,
      280 * math.pi / 180,
      false,
      p,
    );
    canvas.drawCircle(const Offset(285, 48), 27, p);
  }
}

class _MarkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 64, size.height / 64);
    LocoPaint.mark(canvas);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

class _WordPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 334, size.height / 96);
    LocoPaint.word(canvas);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

class _LockupPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 456, size.height / 96);
    canvas.save();
    canvas.scale(1.5, 1.5);
    LocoPaint.mark(canvas);
    canvas.restore();
    canvas.translate(122, 0);
    LocoPaint.word(canvas);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

/// The square X/O icon.
class LocoMark extends StatelessWidget {
  const LocoMark({super.key, this.size = 32});
  final double size;

  @override
  Widget build(BuildContext context) =>
      SizedBox(width: size, height: size, child: CustomPaint(painter: _MarkPainter()));
}

/// The word LOCO.
class LocoWordmark extends StatelessWidget {
  const LocoWordmark({super.key, this.height = 24});
  final double height;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: height * 334 / 96,
        height: height,
        child: CustomPaint(painter: _WordPainter()),
      );
}

/// Icon + word together (used on the lobby card).
class LocoLockup extends StatelessWidget {
  const LocoLockup({super.key, this.width = 300});
  final double width;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: width,
        height: width * 96 / 456,
        child: CustomPaint(painter: _LockupPainter()),
      );
}
