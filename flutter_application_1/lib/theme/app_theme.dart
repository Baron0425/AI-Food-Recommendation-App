import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Design tokens ของแอพ — จุดเดียวที่กำหนดสี/ฟอนต์ทั้งหมด
///
/// **เหตุผลที่แยกไฟล์นี้ออกมา:** ก่อนหน้านี้แต่ละหน้าประกาศค่าสีเขียวเป็น
/// constant ของตัวเอง (`_primaryGreen`, `_darkGreen`) ซ้ำกันหลายไฟล์ ทำให้
/// ค่าเพี้ยนไม่ตรงกันโดยไม่ตั้งใจ (พบว่า `main.dart` กับ `menu_card.dart`
/// ยังค้างเฉดสีเก่า `#6FA828` ขณะที่ไฟล์อื่นแก้เป็น `#5FA82E` ไปแล้ว) ย้ายมา
/// รวมไว้ที่เดียวแล้วให้ทุกหน้า import ไปใช้ กันไม่ให้เกิดปัญหานี้ซ้ำอีก และ
/// แก้ทีเดียวมีผลทั้งแอพ
///
/// โทนสี: เขียวใบไม้สด (อาหาร/ธรรมชาติ) + ทอง-ขมิ้น (เครื่องเทศไทย) บนพื้น
///ครีมอุ่นแทนขาว/เทาซีดแบบทั่วไป
class AppColors {
  AppColors._();

  static const leaf = Color(0xFF4F9A3C); // เขียวใบไม้สด — สีหลัก
  static const leafDark = Color(0xFF3B7A2C); // เขียวเข้มขึ้นสำหรับ gradient/pressed state
  static const forest = Color(0xFF1E3D17); // เขียวป่าเข้ม — โลโก้/พื้นหลังคอนทราสต์สูง
  static const turmeric = Color(0xFFE8A33D); // ทอง-ขมิ้น — accent จุดเล็กๆ (คะแนน, ไฮไลต์)
  static const cream = Color(0xFFFAF7F0); // พื้นหลังหลักทั้งแอพ
  static const ink = Color(0xFF26301F); // สีตัวอักษรหลัก (เขียวเข้มอมดำ ไม่ใช่ดำสนิท)
  static const inkMuted = Color(0xFF6B7566); // ตัวอักษรรอง/คำอธิบาย
  static const chili = Color(0xFFD64545); // แดง — error/logout/danger
  static const line = Color(0xFFE7E2D6); // เส้นแบ่ง/กรอบบางๆ บนพื้นครีม
}

/// ธีมหลักของแอพ — ผูกกับ `MaterialApp(theme: AppTheme.light)`
class AppTheme {
  AppTheme._();

  static ThemeData get light {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.leaf,
        primary: AppColors.leaf,
        secondary: AppColors.turmeric,
        surface: Colors.white,
        error: AppColors.chili,
      ),
      scaffoldBackgroundColor: AppColors.cream,
    );

    final headingFont = GoogleFonts.kanitTextTheme(base.textTheme);
    final bodyFont = GoogleFonts.sarabunTextTheme(base.textTheme);

    return base.copyWith(
      textTheme: bodyFont.copyWith(
        displayLarge: headingFont.displayLarge?.copyWith(color: AppColors.ink),
        displayMedium: headingFont.displayMedium?.copyWith(color: AppColors.ink),
        displaySmall: headingFont.displaySmall?.copyWith(color: AppColors.ink),
        headlineLarge: headingFont.headlineLarge?.copyWith(color: AppColors.ink),
        headlineMedium: headingFont.headlineMedium?.copyWith(color: AppColors.ink),
        headlineSmall: headingFont.headlineSmall?.copyWith(
          color: AppColors.ink,
          fontWeight: FontWeight.w600,
        ),
        titleLarge: headingFont.titleLarge?.copyWith(
          color: AppColors.ink,
          fontWeight: FontWeight.w600,
        ),
        titleMedium: headingFont.titleMedium?.copyWith(
          color: AppColors.ink,
          fontWeight: FontWeight.w600,
        ),
        bodyLarge: bodyFont.bodyLarge?.copyWith(color: AppColors.ink),
        bodyMedium: bodyFont.bodyMedium?.copyWith(color: AppColors.ink),
        bodySmall: bodyFont.bodySmall?.copyWith(color: AppColors.inkMuted),
        labelLarge: bodyFont.labelLarge?.copyWith(color: AppColors.ink),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.cream,
        foregroundColor: AppColors.ink,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.kanit(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: AppColors.ink,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        hintStyle: GoogleFonts.sarabun(color: AppColors.inkMuted),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.leaf, width: 1.6),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.leaf,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(50),
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: GoogleFonts.kanit(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(50),
          foregroundColor: AppColors.ink,
          side: const BorderSide(color: AppColors.line),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: GoogleFonts.sarabun(fontSize: 15, fontWeight: FontWeight.w500),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.leaf,
          textStyle: GoogleFonts.sarabun(fontWeight: FontWeight.w600),
        ),
      ),
      dividerTheme: const DividerThemeData(color: AppColors.line, thickness: 1),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? AppColors.leaf : Colors.white,
        ),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: Colors.white,
        selectedItemColor: AppColors.leaf,
        unselectedItemColor: AppColors.inkMuted,
        type: BottomNavigationBarType.fixed,
        selectedLabelStyle: TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
        unselectedLabelStyle: TextStyle(fontSize: 11),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.ink,
        contentTextStyle: GoogleFonts.sarabun(color: Colors.white),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  /// Gradient มาตรฐานของ header เขียว — ใช้ซ้ำได้ทุกหน้าที่มี header แบบนี้
  static const headerGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [AppColors.leaf, AppColors.leafDark],
  );
}
