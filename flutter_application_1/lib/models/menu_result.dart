/// โมเดลข้อมูลที่แม็พตรงกับ JSON ที่ API (api_server.py) ส่งกลับมา
///
/// ต้องมีฟิลด์ตรงกับ `MenuResult` (Pydantic) ฝั่ง Python เป๊ะๆ:
///   { "mid": int|null, "menu": str, "score": float, "ingredients": list[str], "method": str }
class MenuResult {
  MenuResult({
    this.mid,
    required this.menu,
    required this.score,
    required this.ingredients,
    required this.method,
  });

  // เพิ่ม mid (เดิมไฟล์นี้ไม่มีฟิลด์นี้เลยทั้งที่ backend ส่งมาให้แล้วผ่าน
  // _attach_mid) — ต้องมีไว้เพื่อเปิดหน้ารายละเอียด/รีวิวเมนู (ดูรีวิว/ให้
  // ดาว ต้องรู้ mid) ต่อจากผลการค้นหาได้ nullable ไว้เผื่อกรณีหาใน DB ไม่เจอ
  // (ไม่ควรเกิดขึ้นจริงเพราะ sync ไว้แล้ว แต่ Pydantic ฝั่ง backend ก็เผื่อไว้)
  final int? mid;
  final String menu;
  final double score;
  final List<String> ingredients;
  final String method;

  factory MenuResult.fromJson(Map<String, dynamic> json) {
    return MenuResult(
      mid: json['mid'] as int?,
      menu: json['menu'] as String,
      // ต้องแปลงเป็น double เสมอ เพราะ JSON เลขที่ไม่มีจุดทศนิยม (เช่น 1)
      // จะถูก decode มาเป็น int ใน Dart ทำให้ error ถ้า cast ตรงๆ เป็น double
      score: (json['score'] as num).toDouble(),
      ingredients: List<String>.from(json['ingredients'] as List),
      method: json['method'] as String,
    );
  }
}

/// โมเดลที่แม็พตรงกับ `SearchResponse` (Pydantic) ฝั่ง Python:
///   { "query": str, "count": int, "results": list[MenuResult] }
class SearchResponse {
  SearchResponse({
    required this.query,
    required this.count,
    required this.results,
  });

  final String query;
  final int count;
  final List<MenuResult> results;

  factory SearchResponse.fromJson(Map<String, dynamic> json) {
    return SearchResponse(
      query: json['query'] as String,
      count: json['count'] as int,
      results: (json['results'] as List)
          .map((e) => MenuResult.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

/// โมเดลเมนูที่ใช้กับ /api/menu/popular และ /api/favorites — แม็พกับ
/// `MenuFavoriteItem` (Pydantic) ฝั่ง Python:
///   { "mid": int, "menu_name": str, "image": str|null, "ingredient": str, "method": str,
///     "average_score": float|null, "review_count": int }
///
/// คนละโมเดลกับ `MenuResult` (ที่ใช้กับ /api/search) เพราะมาจากคนละตาราง/
/// endpoint — `MenuResult` มาจากผลลัพธ์โมเดล KNN (มี `score`, `ingredients`
/// เป็น list) ส่วนอันนี้มาจากตาราง `Menu` ใน SQLite ตรงๆ (มี `mid`, `image`,
/// `ingredient` เป็น text ก้อนเดียว)
class FavoriteMenuItem {
  FavoriteMenuItem({
    required this.mid,
    required this.menuName,
    required this.image,
    required this.ingredient,
    required this.method,
    this.averageScore,
    this.reviewCount = 0,
  });

  final int mid;
  final String menuName;
  final String? image;
  final String ingredient;
  final String method;

  // เพิ่มเข้ามา — ของเดิมไฟล์นี้ไม่มี 2 ฟิลด์นี้เลย ทั้งที่ backend
  // (MenuFavoriteItem ใน api_server.py) ส่งมาให้อยู่แล้วจาก /api/menu/popular
  // (average_score/review_count เป็น null/0 จาก endpoint อื่นที่ยังไม่ได้
  // คำนวณให้ เช่น /api/favorites, /api/menu/{mid} — ไม่ error แค่ไม่มีข้อมูล)
  final double? averageScore;
  final int reviewCount;

  factory FavoriteMenuItem.fromJson(Map<String, dynamic> json) {
    return FavoriteMenuItem(
      mid: json['mid'] as int,
      menuName: json['menu_name'] as String,
      image: json['image'] as String?,
      ingredient: json['ingredient'] as String,
      method: json['method'] as String,
      averageScore: (json['average_score'] as num?)?.toDouble(),
      reviewCount: json['review_count'] as int? ?? 0,
    );
  }
}