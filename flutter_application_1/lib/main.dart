import 'package:flutter/material.dart';

import 'screens/home_screen.dart';
import 'services/api_service.dart';
import 'services/auth_service.dart';
import 'theme/app_theme.dart';

void main() {
  runApp(const RecipeApp());
}

class RecipeApp extends StatefulWidget {
  const RecipeApp({super.key});

  @override
  State<RecipeApp> createState() => _RecipeAppState();
}

class _RecipeAppState extends State<RecipeApp> {
  // ApiService() ใช้ baseUrl เริ่มต้นเป็น 10.0.2.2:8000 (Android emulator)
  // ถ้าทดสอบบนอุปกรณ์อื่น แก้ตรงนี้ เช่น:
  //   ApiService(baseUrl: 'http://192.168.1.42:8000')
  final _apiService = ApiService();
  late final AuthService _authService;
  bool _isRestoringSession = true;

  @override
  void initState() {
    super.initState();
    _authService = AuthService(apiService: _apiService);
    _restoreSession();
  }

  Future<void> _restoreSession() async {
    // เช็คว่ามี token ที่เก็บไว้จากรอบก่อนไหม (ผู้ใช้เคยล็อกอินค้างไว้) —
    // ทำก่อนแสดงหน้าแรก กันไม่ให้เห็นหน้า "ยังไม่ได้ล็อกอิน" กระพริบแวบหนึ่ง
    // ก่อนสลับเป็น "ล็อกอินแล้ว"
    await _authService.tryRestoreSession();
    if (mounted) setState(() => _isRestoringSession = false);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AI Recipe',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: _isRestoringSession
          ? const Scaffold(body: Center(child: CircularProgressIndicator(color: AppColors.leaf)))
          : HomeScreen(apiService: _apiService, authService: _authService),
    );
  }
}
