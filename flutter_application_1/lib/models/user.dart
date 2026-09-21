/// โมเดลผู้ใช้ — แม็พกับ `UserResponse` (Pydantic) ฝั่ง Python:
///   { "uid": int, "email": str, "fullname": str, "tel": str|null, "role": int }
///
/// role: 0 = admin, 1 = member (ตามเอกสารโครงงาน)
class AppUser {
  AppUser({
    required this.uid,
    required this.email,
    required this.fullname,
    required this.tel,
    required this.role,
  });

  final int uid;
  final String email;
  final String fullname;
  final String? tel;
  final int role;

  bool get isAdmin => role == 0;

  factory AppUser.fromJson(Map<String, dynamic> json) {
    return AppUser(
      uid: json['uid'] as int,
      email: json['email'] as String,
      fullname: json['fullname'] as String,
      tel: json['tel'] as String?,
      role: json['role'] as int,
    );
  }
}

/// แม็พกับ `TokenResponse` (Pydantic) ฝั่ง Python — ผลลัพธ์ตอน register/login สำเร็จ
class AuthResult {
  AuthResult({required this.accessToken, required this.user});

  final String accessToken;
  final AppUser user;

  factory AuthResult.fromJson(Map<String, dynamic> json) {
    return AuthResult(
      accessToken: json['access_token'] as String,
      user: AppUser.fromJson(json['user'] as Map<String, dynamic>),
    );
  }
}
