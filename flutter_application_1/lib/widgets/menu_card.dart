import 'package:flutter/material.dart';

import '../models/menu_result.dart';
import '../theme/app_theme.dart';

/// การ์ดแสดงเมนูในหน้าหลัก — แนวนอน (ข้อความซ้าย รูปขวา) ตามภาพตัวอย่างในเอกสาร
///
/// **Design pass:** ใช้ `AppColors` จากธีมกลางแทนสี hardcode — จุดนี้เดิมเป็น
/// ต้นเหตุของสีเพี้ยน (ยังค้างเฉด `#6FA828` เก่าทั้งที่ไฟล์อื่นแก้ไปแล้ว)
class MenuCard extends StatelessWidget {
  const MenuCard({
    super.key,
    required this.item,
    this.onTap,
    this.isFavorite = false,
    this.onToggleFavorite,
  });

  final FavoriteMenuItem item;
  final VoidCallback? onTap;
  final bool isFavorite;
  final VoidCallback? onToggleFavorite;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      elevation: 0,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.line),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          padding: const EdgeInsets.all(10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      item.menuName,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    // ใหม่: โชว์คะแนนเฉลี่ย + จำนวนรีวิวถ้ามี (มีเฉพาะเมนูที่
                    // มาจาก /api/menu/popular — เมนูโปรดยังไม่แนบคะแนนมาให้)
                    // ไม่มีก็ยังโชว์ label เดิมไว้กันการ์ดดูโล่งไป
                    if (item.averageScore != null)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.star, size: 12, color: AppColors.turmeric),
                          const SizedBox(width: 2),
                          Text(
                            '${item.averageScore!.toStringAsFixed(1)} (${item.reviewCount})',
                            style: const TextStyle(
                              color: AppColors.inkMuted,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      )
                    else
                      const Text(
                        'อาหารไทย',
                        style: TextStyle(color: AppColors.inkMuted, fontSize: 11),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Stack(
                clipBehavior: Clip.none,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: SizedBox(
                      width: 64,
                      height: 64,
                      child: item.image != null && item.image!.isNotEmpty
                          ? Image.network(
                              item.image!,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => _placeholderIcon(),
                            )
                          : _placeholderIcon(),
                    ),
                  ),
                  if (onToggleFavorite != null)
                    Positioned(
                      top: -6,
                      left: -6,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: onToggleFavorite,
                        child: Container(
                          padding: const EdgeInsets.all(3),
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(color: Colors.black26, blurRadius: 3),
                            ],
                          ),
                          child: Icon(
                            isFavorite ? Icons.favorite : Icons.favorite_border,
                            size: 16,
                            color: isFavorite ? AppColors.chili : AppColors.inkMuted,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _placeholderIcon() {
    return Container(
      color: const Color(0xFFEAF3E3),
      child: const Icon(Icons.restaurant, size: 24, color: AppColors.leaf),
    );
  }
}
