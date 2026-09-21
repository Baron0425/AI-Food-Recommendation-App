import 'package:flutter/material.dart';

/// โลโก้ Google ของจริง (4 สีตามแบรนด์: น้ำเงิน, แดง, เหลือง, เขียว) วาดด้วย
/// `CustomPainter` แทนตัวอักษร "G" สีเดียว — ไม่ต้องพึ่งไฟล์รูป/ไอคอนฟอนต์เพิ่ม
/// ใช้สีตามที่ Google กำหนดจริง (#4285F4 / #EA4335 / #FBBC05 / #34A853)
class GoogleLogo extends StatelessWidget {
  const GoogleLogo({super.key, this.size = 20});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _GoogleGPainter()),
    );
  }
}

class _GoogleGPainter extends CustomPainter {
  static const _blue = Color(0xFF4285F4);
  static const _red = Color(0xFFEA4335);
  static const _yellow = Color(0xFFFBBC05);
  static const _green = Color(0xFF34A853);
  static const _twoPi = 6.28318530718;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    final strokeWidth = radius * 0.44;
    final ringRadius = radius - strokeWidth / 2;
    final rect = Rect.fromCircle(center: center, radius: ringRadius);

    Paint ringPaint(Color color) => Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.butt;

    void arc(double startDeg, double sweepDeg, Color color) {
      canvas.drawArc(
        rect,
        startDeg * _twoPi / 360,
        sweepDeg * _twoPi / 360,
        false,
        ringPaint(color),
      );
    }

    arc(-40, 100, _blue);
    arc(60, 90, _green);
    arc(150, 75, _yellow);
    arc(225, 95, _red);

    final barPaint = Paint()..color = _blue;
    final barRect = Rect.fromLTWH(
      center.dx - strokeWidth * 0.06,
      center.dy - strokeWidth * 0.5,
      radius - center.dx + strokeWidth * 0.56,
      strokeWidth,
    );
    canvas.drawRect(barRect, barPaint);
  }

  @override
  bool shouldRepaint(covariant _GoogleGPainter oldDelegate) => false;
}
