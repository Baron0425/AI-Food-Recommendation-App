import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/menu_result.dart';
import '../models/review.dart';
import '../models/user.dart';

/// เชื่อมต่อกับ Recipe Recommendation API (`api_server.py`)
///
/// **ต้องตั้งค่า `baseUrl` ให้ตรงกับที่รัน `uvicorn api_server:app` อยู่จริง:**
///   - Android emulator       -> `http://10.0.2.2:8000` (ค่าเริ่มต้นด้านล่าง —
///     emulator แม็พ 10.0.2.2 กลับไปที่ localhost ของเครื่อง host ให้อัตโนมัติ
///     ใช้ `localhost`/`127.0.0.1` ตรงๆ ไม่ได้ เพราะ emulator แยกเน็ตเวิร์กจากเครื่องจริง)
///   - iOS simulator           -> `http://127.0.0.1:8000` ใช้ได้ตรงๆ
///   - มือถือจริงผ่าน WiFi วงเดียวกัน -> IP วง LAN ของเครื่องที่รันเซิร์ฟเวอร์
///     เช่น `http://192.168.1.42:8000` (หาด้วย `ipconfig` บน Windows)
///   - Production/deploy จริง  -> โดเมนจริง เช่น `https://api.yourapp.com`
class ApiService {
  ApiService({
    String? baseUrl,
  }) : baseUrl =
          baseUrl ??
          const String.fromEnvironment(
            'API_BASE_URL',
            defaultValue: 'http://10.0.2.2:8000',
          );

  final String baseUrl;

  static const _timeout = Duration(seconds: 10);

  /// ค้นหาอัตโนมัติ — ระบบเดาเองว่าเป็นชื่อเมนูหรือวัตถุดิบ (GET /api/search)
  /// เหมาะกับช่องค้นหาช่องเดียวในหน้าแอพ (ตามที่ออกแบบไว้ในเอกสารโครงงาน)
  Future<SearchResponse> searchAuto(String query, {int topK = 3}) async {
    final uri = Uri.parse('$baseUrl/api/search').replace(queryParameters: {
      'q': query,
      'top_k': '$topK',
    });
    return _getSearchResponse(uri);
  }

  /// ค้นหาเฉพาะด้วยชื่อเมนู (GET /api/search/name)
  Future<SearchResponse> searchByName(String name, {int topK = 3}) async {
    final uri =
        Uri.parse('$baseUrl/api/search/name').replace(queryParameters: {
      'name': name,
      'top_k': '$topK',
    });
    return _getSearchResponse(uri);
  }

  /// แนะนำเมนูจากวัตถุดิบที่มี (POST /api/recommend)
  Future<SearchResponse> recommendByIngredients(
    String ingredients, {
    int topK = 3,
  }) async {
    final uri = Uri.parse('$baseUrl/api/recommend');
    final response = await http
        .post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'ingredients': ingredients, 'top_k': topK}),
        )
        .timeout(_timeout);

    return _parseSearchResponse(response);
  }

  Future<SearchResponse> _getSearchResponse(Uri uri) async {
    final response = await http.get(uri).timeout(_timeout);
    return _parseSearchResponse(response);
  }

  SearchResponse _parseSearchResponse(http.Response response) {
    final decoded = _decodeOrThrow(response);
    return SearchResponse.fromJson(decoded as Map<String, dynamic>);
  }

  // -------------------------------------------------------------------
  // Auth (STEP 4-7) — สมัคร/ล็อกอิน/Google/ข้อมูลผู้ใช้
  // -------------------------------------------------------------------

  /// สมัครสมาชิกด้วย Email + Password (POST /api/auth/register)
  Future<AuthResult> register({
    required String email,
    required String fullname,
    required String password,
    String? tel,
  }) async {
    final uri = Uri.parse('$baseUrl/api/auth/register');
    final response = await http
        .post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'email': email,
            'fullname': fullname,
            'password': password,
            'tel': tel,
          }),
        )
        .timeout(_timeout);
    return AuthResult.fromJson(_decodeOrThrow(response) as Map<String, dynamic>);
  }

  /// ล็อกอินด้วย Email + Password (POST /api/auth/login)
  Future<AuthResult> login({required String email, required String password}) async {
    final uri = Uri.parse('$baseUrl/api/auth/login');
    final response = await http
        .post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'email': email, 'password': password}),
        )
        .timeout(_timeout);
    return AuthResult.fromJson(_decodeOrThrow(response) as Map<String, dynamic>);
  }

  /// ล็อกอิน/สมัครสมาชิกผ่าน Google (POST /api/auth/google)
  /// [googleIdToken] คือ idToken ที่ได้จาก `GoogleSignInAuthentication.idToken`
  Future<AuthResult> loginWithGoogle(String googleIdToken) async {
    final uri = Uri.parse('$baseUrl/api/auth/google');
    final response = await http
        .post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'id_token': googleIdToken}),
        )
        .timeout(_timeout);
    return AuthResult.fromJson(_decodeOrThrow(response) as Map<String, dynamic>);
  }

  /// ดึงข้อมูลผู้ใช้ปัจจุบัน (GET /api/auth/me) — ต้องส่ง token ที่ได้จาก login
  Future<AppUser> getCurrentUser(String token) async {
    final uri = Uri.parse('$baseUrl/api/auth/me');
    final response = await http.get(uri, headers: _authHeaders(token)).timeout(_timeout);
    return AppUser.fromJson(_decodeOrThrow(response) as Map<String, dynamic>);
  }

  /// แก้ไขข้อมูลส่วนตัว (PUT /api/auth/me) — ส่งเฉพาะ field ที่ต้องการเปลี่ยน
  Future<AppUser> updateProfile(
    String token, {
    String? fullname,
    String? tel,
    String? password,
  }) async {
    final uri = Uri.parse('$baseUrl/api/auth/me');
    final response = await http
        .put(
          uri,
          headers: {..._authHeaders(token), 'Content-Type': 'application/json'},
          body: jsonEncode({
            'fullname': ?fullname,
            'tel': ?tel,
            'password': ?password,
          }),
        )
        .timeout(_timeout);
    return AppUser.fromJson(_decodeOrThrow(response) as Map<String, dynamic>);
  }

  /// Logout (POST /api/auth/logout) — JWT เป็น stateless ฝั่งเซิร์ฟเวอร์ไม่มี
  /// อะไรให้ลบจริงๆ แต่เรียกไว้เพื่อความสมบูรณ์ของ flow — การ "ออกจากระบบ"
  /// จริงๆ คือฝั่งแอพลบ token ที่เก็บไว้ทิ้ง (ดู AuthService.logout)
  Future<void> logout(String token) async {
    final uri = Uri.parse('$baseUrl/api/auth/logout');
    await http.post(uri, headers: _authHeaders(token)).timeout(_timeout);
  }

  // -------------------------------------------------------------------
  // Favorites / Popular menu
  // -------------------------------------------------------------------

  Future<List<FavoriteMenuItem>> getPopularMenus({int limit = 10}) async {
    final uri = Uri.parse('$baseUrl/api/menu/popular')
        .replace(queryParameters: {'limit': '$limit'});
    final response = await http.get(uri).timeout(_timeout);
    final decoded = _decodeOrThrow(response) as Map<String, dynamic>;
    return (decoded['results'] as List)
        .map((e) => FavoriteMenuItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<FavoriteMenuItem>> getFavorites(String token) async {
    final uri = Uri.parse('$baseUrl/api/favorites');
    final response = await http.get(uri, headers: _authHeaders(token)).timeout(_timeout);
    final decoded = _decodeOrThrow(response) as Map<String, dynamic>;
    return (decoded['results'] as List)
        .map((e) => FavoriteMenuItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> addFavorite(String token, int mid) async {
    final uri = Uri.parse('$baseUrl/api/favorites');
    final response = await http
        .post(
          uri,
          headers: {..._authHeaders(token), 'Content-Type': 'application/json'},
          body: jsonEncode({'mid': mid}),
        )
        .timeout(_timeout);
    _decodeOrThrow(response);
  }

  Future<void> removeFavorite(String token, int mid) async {
    final uri = Uri.parse('$baseUrl/api/favorites/$mid');
    final response = await http.delete(uri, headers: _authHeaders(token)).timeout(_timeout);
    _decodeOrThrow(response);
  }

  // -------------------------------------------------------------------
  // Menu detail / Reviews (ใหม่ — ฝั่ง backend ทำ endpoint ไว้แล้วแต่หน้าแอพ
  // ยังไม่เคยเรียกใช้เลย เพิ่มให้ครบตรงนี้)
  // -------------------------------------------------------------------

  /// รายละเอียดเมนูเดียวแบบเต็ม (GET /api/menu/{mid}) — public ไม่ต้องล็อกอิน
  Future<FavoriteMenuItem> getMenuDetail(int mid) async {
    final uri = Uri.parse('$baseUrl/api/menu/$mid');
    final response = await http.get(uri).timeout(_timeout);
    return FavoriteMenuItem.fromJson(_decodeOrThrow(response) as Map<String, dynamic>);
  }

  /// รีวิว + คะแนนเฉลี่ยของเมนู (GET /api/menu/{mid}/reviews) — public
  Future<ReviewListResponse> getMenuReviews(int mid) async {
    final uri = Uri.parse('$baseUrl/api/menu/$mid/reviews');
    final response = await http.get(uri).timeout(_timeout);
    return ReviewListResponse.fromJson(_decodeOrThrow(response) as Map<String, dynamic>);
  }

  /// ให้ดาว 1-5 + คอมเมนต์ (ไม่บังคับ) กับเมนู (POST /api/reviews) — ต้อง
  /// ล็อกอิน รีวิวซ้ำเมนูเดิมจะ "แก้ไข" ของเดิมแทนสร้างใหม่ (ตาม
  /// UNIQUE(UID, MID) ฝั่ง backend — ดู menu_repository.upsert_review)
  Future<void> submitReview(
    String token, {
    required int mid,
    required int score,
    String? comment,
  }) async {
    final uri = Uri.parse('$baseUrl/api/reviews');
    final response = await http
        .post(
          uri,
          headers: {..._authHeaders(token), 'Content-Type': 'application/json'},
          body: jsonEncode({'mid': mid, 'score': score, 'comment': comment}),
        )
        .timeout(_timeout);
    _decodeOrThrow(response);
  }

  Map<String, String> _authHeaders(String token) => {'Authorization': 'Bearer $token'};

  /// ตรวจ HTTP status + decode utf8 ให้ครบในที่เดียว (ใช้ร่วมกันทุกเมธอด)
  /// ต้อง decode เป็น utf8 จาก bodyBytes ตรงๆ ไม่ใช้ response.body เฉยๆ ไม่งั้น
  /// ข้อความภาษาไทยมีโอกาสเพี้ยนบางอุปกรณ์
  dynamic _decodeOrThrow(http.Response response) {
    final decodedBody = utf8.decode(response.bodyBytes);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      String detail = decodedBody;
      try {
        final parsed = jsonDecode(decodedBody);
        if (parsed is Map && parsed['detail'] != null) {
          detail = parsed['detail'].toString();
        }
      } catch (_) {
        // เก็บ decodedBody ดิบไว้เป็น detail ถ้า parse JSON ไม่ได้
      }
      throw ApiException(detail);
    }
    if (decodedBody.isEmpty) return null;
    return jsonDecode(decodedBody);
  }
}

/// Exception ที่มีข้อความอ่านง่าย เอาไปโชว์บน UI (เช่น SnackBar) ได้ตรงๆ
class ApiException implements Exception {
  ApiException(this.message);
  final String message;

  @override
  String toString() => message;
}
