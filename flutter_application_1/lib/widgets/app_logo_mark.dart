import 'package:flutter/material.dart';

/// โลโก้แบบ custom-painted แทนไอคอน Material ทั่วไป (เดิมใช้ `Icons.eco`
/// ซึ่งเป็นไอคอนสำเร็จรูปที่แอพไหนก็ใช้ได้ ดูไม่มีเอกลักษณ์) วาดเป็นรูปใบไม้
/// พร้อมจุด/วงแหวนเล็กที่มุม สื่อถึง "AI" ตามคอนเซปต์โลโก้ในเอกสาร (ใบไม้ +
/// โหนดวงจร) โดยไม่ต้องพึ่งไฟล์รูปภาพ/ฟอนต์ไอคอนเพิ่ม
class AppLogoMark extends StatelessWidget {
  const AppLogoMark({super.key, this.size = 44, this.color = Colors.white});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _LogoPainter(color: color)),
    );
  }
}

class _LogoPainter extends CustomPainter {
  _LogoPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final leafPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    // ใบไม้: รูป vesica จากสองเส้นโค้งประกบกัน แหลมบน-ล่าง
    final leafPath = Path()
      ..moveTo(w * 0.5, h * 0.10)
      ..quadraticBezierTo(w * 0.94, h * 0.32, w * 0.5, h * 0.90)
      ..quadraticBezierTo(w * 0.06, h * 0.32, w * 0.5, h * 0.10)
      ..close();
    canvas.drawPath(leafPath, leafPaint);

    // เส้นกลางใบ (vein)
    final veinPaint = Paint()
      ..color = color.withOpacity(0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.035
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(w * 0.5, h * 0.24), Offset(w * 0.5, h * 0.76), veinPaint);

    // จุด + วงแหวนมุมขวาบน สื่อถึงโหนด/AI
    canvas.drawCircle(Offset(w * 0.82, h * 0.20), w * 0.065, leafPaint);
    final ringPaint = Paint()
      ..color = color.withOpacity(0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.028;
    canvas.drawCircle(Offset(w * 0.82, h * 0.20), w * 0.12, ringPaint);
  }

  @override
  bool shouldRepaint(covariant _LogoPainter oldDelegate) => oldDelegate.color != color;
}
