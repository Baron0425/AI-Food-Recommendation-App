import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// วิดเจ็ตแสดง/เลือกจำนวนดาว (1-5) ใช้ร่วมกันทั้งแอพทุกจุดที่เกี่ยวกับคะแนน
/// เมนู (การ์ดเมนู, หน้ารายละเอียด, รายการรีวิว, ฟอร์มให้คะแนน) แทนที่จะให้
/// แต่ละหน้าวาดดาวเอาเองแบบไม่ตรงกัน — มี 2 โหมดผ่าน [editable]:
///
///   - อ่านอย่างเดียว (ค่าเริ่มต้น): ใช้โชว์คะแนนเฉลี่ย/คะแนนรีวิวแต่ละอัน
///     รองรับคะแนนมีเศษ (เช่น 4.3) ด้วยดาวเต็ม/ดาวครึ่ง/ดาวโปร่งตามสัดส่วนจริง
///   - แบบกดเลือกได้ (`editable: true`): ใช้ในฟอร์มส่งรีวิว ปัดเศษเป็นดาวเต็ม
///     เสมอเพราะ Score ที่ backend รับเป็น int 1-5 (ดู ReviewRequest ใน
///     api_server.py) จะส่งเป็นเศษไม่ได้อยู่แล้ว
class StarRating extends StatelessWidget {
  const StarRating({
    super.key,
    required this.rating,
    this.size = 20,
    this.editable = false,
    this.onChanged,
    this.maxRating = 5,
  });

  /// คะแนนปัจจุบัน (0-[maxRating]) — เศษได้เฉพาะตอน [editable] เป็น false
  final double rating;
  final double size;
  final bool editable;

  /// เรียกตอนกดดาว (เฉพาะตอน [editable] เป็น true) — ส่งค่าดาวที่กด (1-[maxRating])
  final ValueChanged<int>? onChanged;
  final int maxRating;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(maxRating, (index) {
        final starValue = index + 1;
        final icon = editable
            ? (starValue <= rating ? Icons.star : Icons.star_border)
            : _readonlyIcon(starValue);
        final star = Icon(icon, size: size, color: AppColors.turmeric);

        if (!editable) return star;

        return GestureDetector(
          onTap: () => onChanged?.call(starValue),
          child: Padding(padding: const EdgeInsets.symmetric(horizontal: 2), child: star),
        );
      }),
    );
  }

  IconData _readonlyIcon(int starValue) {
    if (rating >= starValue) return Icons.star;
    if (rating >= starValue - 0.5) return Icons.star_half;
    return Icons.star_border;
  }
}
