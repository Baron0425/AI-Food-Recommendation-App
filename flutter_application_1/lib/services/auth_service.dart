import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../models/user.dart';
import 'api_service.dart';

/// จัดการสถานะการล็อกอินทั้งแอพ: เก็บ/อ่าน JWT token แบบเข้ารหัส
/// (flutter_secure_storage), เรียก ApiService สำหรับ register/login/google/
/// logout และแจ้งเตือน UI ที่ฟังอยู่เมื่อสถานะเปลี่ยน (ผ่าน ValueNotifier —
/// ไม่ต้องเพิ่ม package จัดการ state เพิ่ม เช่น provider/riverpod)
///
/// วิธีใช้ใน widget:
///   ValueListenableBuilder<AppUser?>(
///     valueListenable: authService.currentUser,
///     builder: (context, user, _) => user == null ? LoginButton() : ProfileMenu(),
///   )
///
/// **แก้ไขรอบก่อน — migrate ไป google_sign_in 7.x:** เวอร์ชัน 7.0.0 เปลี่ยน
/// `GoogleSignIn` เป็น singleton (`GoogleSignIn.instance`), เพิ่มขั้นตอน
/// `initialize()` ที่ต้องเรียกครั้งเดียวก่อนใช้งาน, เปลี่ยน `signIn()` เป็น
/// `authenticate()`, และเปลี่ยน exception type จาก `PlatformException` เป็น
/// `GoogleSignInException`
///
/// **แก้ไขรอบนี้ — เพิ่ม serverClientId:** ต้องระบุ Web Client ID (จาก Google
/// Cloud Console → Credentials → OAuth 2.0 Client IDs → "Web client (auto
/// created by Google Service)") ตอนเรียก initialize() ไม่งั้น idToken ที่ได้
/// จะมี audience ไม่ตรงกับที่ backend (RECIPE_GOOGLE_CLIENT_ID) คาดหวัง ทำให้
/// backend verify ไม่ผ่าน แม้ sign-in ฝั่ง Flutter จะดูเหมือนสำเร็จก็ตาม —
/// ต้องเป็นค่าเดียวกันเป๊ะๆ กับที่ตั้งใน RECIPE_GOOGLE_CLIENT_ID ฝั่ง backend
class AuthService {
  AuthService({required this.apiService});

  final ApiService apiService;

  static const _tokenKey = 'jwt_token';
  final _secureStorage = const FlutterSecureStorage();
  final _googleSignIn = GoogleSignIn.instance;

  /// Web Client ID จาก Google Cloud Console (OAuth 2.0 Client IDs → "Web
  /// client (auto created by Google Service)") — ต้องตรงกับ
  /// RECIPE_GOOGLE_CLIENT_ID ที่ตั้งไว้ฝั่ง backend เป๊ะๆ
  static const _googleServerClientId =
      '1004629703821-s26ndmkuj0ta5uq4quin0lraho6bfb5h.apps.googleusercontent.com';

  /// กันเรียก initialize() ซ้ำสองครั้ง (ผิดกติกาของ 7.x — ต้องเรียกครั้งเดียว)
  bool _googleSignInInitialized = false;

  /// สถานะผู้ใช้ปัจจุบัน — null แปลว่ายังไม่ได้ล็อกอิน
  final ValueNotifier<AppUser?> currentUser = ValueNotifier<AppUser?>(null);

  String? _token;

  /// เรียกครั้งเดียวตอนแอพเริ่มทำงาน (main.dart) — เช็คว่ามี token ที่เก็บไว้
  /// จากรอบก่อนไหม ถ้ามีลองดึงข้อมูล user มาเช็คว่า token ยังใช้ได้อยู่ไหม
  /// (กันกรณี token หมดอายุตั้งแต่ตอนปิดแอพไป) และเตรียม GoogleSignIn ให้
  /// พร้อมใช้งานไปในตัว (initialize ต้องเรียกก่อน authenticate เสมอใน 7.x)
  Future<void> tryRestoreSession() async {
    await _ensureGoogleSignInInitialized();

    final storedToken = await _secureStorage.read(key: _tokenKey);
    if (storedToken == null) return;

    try {
      final user = await apiService.getCurrentUser(storedToken);
      _token = storedToken;
      currentUser.value = user;
    } on ApiException {
      // token หมดอายุ/ไม่ถูกต้อง — ลบทิ้ง ให้ผู้ใช้ล็อกอินใหม่
      await _secureStorage.delete(key: _tokenKey);
    }
  }

  Future<void> _ensureGoogleSignInInitialized() async {
    if (_googleSignInInitialized) return;
    await _googleSignIn.initialize(serverClientId: _googleServerClientId);
    _googleSignInInitialized = true;
  }

  Future<void> register({
    required String email,
    required String fullname,
    required String password,
    String? tel,
  }) async {
    final result = await apiService.register(
      email: email,
      fullname: fullname,
      password: password,
      tel: tel,
    );
    await _saveSession(result);
  }

  Future<void> login({required String email, required String password}) async {
    final result = await apiService.login(email: email, password: password);
    await _saveSession(result);
  }

  /// เปิดหน้าจอเลือกบัญชี Google ของระบบปฏิบัติการ แล้วส่ง idToken ที่ได้ไปให้
  /// backend ตรวจสอบต่อ (ดู auth.py: authenticate_google)
  ///
  /// **แก้บัคสำคัญ (คงไว้จากรอบก่อน):** ต้องดัก exception จาก Google sign-in
  /// เอง แล้วแปลงเป็น `ApiException` ให้ชั้น UI (login_screen.dart) ที่ดักจับ
  /// เฉพาะ `ApiException` อยู่แล้วจัดการได้ถูกต้อง — ใน 7.x exception type
  /// เปลี่ยนจาก `PlatformException` เป็น `GoogleSignInException`
  Future<void> loginWithGoogle() async {
    await _ensureGoogleSignInInitialized();

    GoogleSignInAccount? account;
    try {
      account = await _googleSignIn.authenticate();
    } on GoogleSignInException catch (e) {
      // ผู้ใช้กดยกเลิกตอนเลือกบัญชีเอง (ไม่ใช่ error) — ไม่ต้อง throw
      if (e.code == GoogleSignInExceptionCode.canceled) {
        return;
      }
      throw ApiException(
        'เข้าสู่ระบบ Google ไม่สำเร็จ (${e.code}): ${e.description ?? "ไม่ทราบสาเหตุ"} '
        '— มักเกิดจากยังตั้งค่า Google Cloud Console ไม่ครบ (OAuth Client ID / SHA-1 fingerprint)',
      );
    }

    // idToken ได้มาจาก authenticate() ตรงๆ ใน 7.x (ไม่ต้องเรียก
    // account.authentication แบบเดิมอีกต่อไป — property นั้นถูกลบออกแล้ว)
    final idToken = account.authentication.idToken;
    if (idToken == null) {
      throw ApiException('ไม่ได้รับ ID Token จาก Google กรุณาลองใหม่');
    }
    final result = await apiService.loginWithGoogle(idToken);
    await _saveSession(result);
  }

  Future<void> updateProfile({String? fullname, String? tel, String? password}) async {
    final token = _requireToken();
    final updated = await apiService.updateProfile(
      token,
      fullname: fullname,
      tel: tel,
      password: password,
    );
    currentUser.value = updated;
  }

  Future<void> logout() async {
    if (_token != null) {
      try {
        await apiService.logout(_token!);
      } on ApiException {
        // ยกเลิกฝั่งเซิร์ฟเวอร์ไม่สำเร็จก็ไม่เป็นไร — ยังต้องลบ token ฝั่งเครื่อง
        // ต่อเสมอ เพราะ "logout" ที่ user รับรู้คือแอพนี้ ไม่ใช่เซิร์ฟเวอร์
      }
    }
    // ล้าง Google session ด้วยเผื่อ login ผ่าน Google มา (ไม่งั้นครั้งหน้ากด
    // "Login with Google" จะเข้าบัญชีเดิมทันทีโดยไม่ให้เลือกบัญชีใหม่)
    await _googleSignIn.signOut();
    await _secureStorage.delete(key: _tokenKey);
    _token = null;
    currentUser.value = null;
  }

  String? get token => _token;

  bool get isLoggedIn => currentUser.value != null;

  Future<void> _saveSession(AuthResult result) async {
    await _secureStorage.write(key: _tokenKey, value: result.accessToken);
    _token = result.accessToken;
    currentUser.value = result.user;
  }

  String _requireToken() {
    final token = _token;
    if (token == null) {
      throw ApiException('กรุณาเข้าสู่ระบบก่อน');
    }
    return token;
  }
}