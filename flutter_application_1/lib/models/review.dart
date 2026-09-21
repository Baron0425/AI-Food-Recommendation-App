/// โมเดลรีวิว/ให้คะแนนเมนู — แม็พกับ `ReviewItem` และ `ReviewListResponse`
/// (Pydantic) ฝั่ง Python ที่ endpoint GET /api/menu/{mid}/reviews คืนกลับมา:
///   ReviewItem: { "uid": int, "fullname": str, "score": int, "comment": str|null, "review_date": str }
///   ReviewListResponse: { "average_score": float|null, "review_count": int, "reviews": list[ReviewItem] }
///
/// ใช้คนละโมเดลกับ `MenuResult`/`FavoriteMenuItem` เพราะมาจากคนละ endpoint/
/// concern — อันนี้คือ "ใครให้กี่ดาว พูดว่าอะไร" ล้วนๆ ไม่เกี่ยวกับตัวสูตรอาหาร
class ReviewItem {
  ReviewItem({
    required this.uid,
    required this.fullname,
    required this.score,
    required this.comment,
    required this.reviewDate,
  });

  final int uid;
  final String fullname;
  final int score;
  final String? comment;
  final String reviewDate;

  factory ReviewItem.fromJson(Map<String, dynamic> json) {
    return ReviewItem(
      uid: json['uid'] as int,
      fullname: json['fullname'] as String,
      score: json['score'] as int,
      comment: json['comment'] as String?,
      reviewDate: json['review_date'] as String,
    );
  }
}

class ReviewListResponse {
  ReviewListResponse({
    required this.averageScore,
    required this.reviewCount,
    required this.reviews,
  });

  final double? averageScore;
  final int reviewCount;
  final List<ReviewItem> reviews;

  factory ReviewListResponse.fromJson(Map<String, dynamic> json) {
    return ReviewListResponse(
      // average_score เป็น null ได้ถ้ายังไม่มีใครรีวิวเมนูนี้เลย (ดู
      // get_menu_review_summary ฝั่ง backend) — ต้อง cast แบบ nullable ตรงๆ
      averageScore: (json['average_score'] as num?)?.toDouble(),
      reviewCount: json['review_count'] as int,
      reviews: (json['reviews'] as List)
          .map((e) => ReviewItem.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}
