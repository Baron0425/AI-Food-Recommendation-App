import 'package:flutter/material.dart';

import '../models/menu_result.dart';
import '../models/review.dart';
import '../models/user.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../widgets/star_rating.dart';

/// หน้ารายละเอียดเมนู — รูปภาพ/วัตถุดิบ/วิธีทำเต็ม + ส่วนรีวิว/ให้คะแนน
///
/// **ของใหม่ทั้งหน้า:** ฝั่ง backend (api_server.py) มี endpoint
/// GET /api/menu/{mid}, GET /api/menu/{mid}/reviews และ POST /api/reviews
/// ทำไว้ครบแล้ว แต่ฝั่งแอพยังไม่เคยเรียกใช้เลย (หน้าค้นหาเดิมมีแค่ bottom
/// sheet โชว์สูตรสั้นๆ ไม่มีที่ให้ดูรีวิว/ให้ดาว) หน้านี้รวมทุกอย่างไว้ที่
/// เดียว ใช้ร่วมกันได้ทั้งจากการ์ดเมนูในหน้าหลัก (เมนูยอดนิยม/เมนูโปรด — ดู
/// TODO เดิมใน home_screen.dart ที่ตั้งใจไว้ตั้งแต่แรกว่าจะทำหน้านี้) และจาก
/// ผลการค้นหา เพื่อให้ประสบการณ์การดูรายละเอียด+รีวิวสอดคล้องกันทั้งแอพ
class MenuDetailScreen extends StatefulWidget {
  const MenuDetailScreen({
    super.key,
    required this.mid,
    required this.apiService,
    required this.authService,
    this.menuNameHint,
  });

  final int mid;
  final ApiService apiService;
  final AuthService authService;

  /// ชื่อเมนูที่รู้อยู่แล้วจากหน้าก่อน (จากการ์ด/ผลค้นหา) — ใช้โชว์เป็น
  /// AppBar title ทันทีระหว่างรอโหลดรายละเอียดเต็ม กันหน้าจอโล่งเปล่าตอนเปิดมาแวบแรก
  final String? menuNameHint;

  @override
  State<MenuDetailScreen> createState() => _MenuDetailScreenState();
}

class _MenuDetailScreenState extends State<MenuDetailScreen> {
  FavoriteMenuItem? _menu;
  ReviewListResponse? _reviewData;
  bool _isLoadingMenu = true;
  bool _isLoadingReviews = true;
  String? _menuError;

  bool _isFavorite = false;
  bool _isTogglingFavorite = false;

  int _myScore = 0;
  final _commentController = TextEditingController();
  bool _isSubmittingReview = false;

  @override
  void initState() {
    super.initState();
    _loadMenu();
    _loadReviews();
    if (widget.authService.isLoggedIn) _loadFavoriteStatus();
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _loadMenu() async {
    setState(() {
      _isLoadingMenu = true;
      _menuError = null;
    });
    try {
      final menu = await widget.apiService.getMenuDetail(widget.mid);
      if (!mounted) return;
      setState(() => _menu = menu);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _menuError = e.message);
    } finally {
      if (mounted) setState(() => _isLoadingMenu = false);
    }
  }

  Future<void> _loadReviews() async {
    setState(() => _isLoadingReviews = true);
    try {
      final data = await widget.apiService.getMenuReviews(widget.mid);
      if (!mounted) return;
      setState(() => _reviewData = data);
    } on ApiException {
      // โหลดรีวิวไม่สำเร็จ ไม่ต้อง block หน้าทั้งหน้า — แค่ section รีวิวจะ
      // โชว์สถานะว่างแทน ผู้ใช้ยังอ่านสูตรอาหารส่วนหลักได้ตามปกติ
    } finally {
      if (mounted) setState(() => _isLoadingReviews = false);
    }
  }

  /// เช็คว่าเมนูนี้อยู่ในรายการโปรดของผู้ใช้อยู่แล้วหรือไม่ — ยังไม่มี endpoint
  /// เช็คทีละเมนู จึงดึงรายการโปรดทั้งหมดมาเทียบ mid เอา (รายการโปรดแต่ละคน
  /// ไม่น่าจะเยอะมากในแอพระดับนี้ ไม่คุ้มที่จะขอ endpoint ใหม่แค่เรื่องนี้)
  Future<void> _loadFavoriteStatus() async {
    final token = widget.authService.token;
    if (token == null) return;
    try {
      final favorites = await widget.apiService.getFavorites(token);
      if (!mounted) return;
      setState(() => _isFavorite = favorites.any((m) => m.mid == widget.mid));
    } on ApiException {
      // เงียบไว้ — ไม่กระทบการดูรายละเอียดเมนูหลัก แค่ไอคอนหัวใจอาจไม่ sync
    }
  }

  Future<void> _toggleFavorite() async {
    if (!widget.authService.isLoggedIn) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('กรุณาเข้าสู่ระบบก่อนกดถูกใจเมนู')),
      );
      return;
    }
    final token = widget.authService.token!;
    final wasFavorite = _isFavorite;

    // Optimistic update เหมือนหน้าหลัก — สลับสถานะทันทีแล้ว rollback ถ้า error
    setState(() {
      _isFavorite = !wasFavorite;
      _isTogglingFavorite = true;
    });
    try {
      if (wasFavorite) {
        await widget.apiService.removeFavorite(token, widget.mid);
      } else {
        await widget.apiService.addFavorite(token, widget.mid);
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _isFavorite = wasFavorite);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _isTogglingFavorite = false);
    }
  }

  Future<void> _submitReview() async {
    if (!widget.authService.isLoggedIn) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('กรุณาเข้าสู่ระบบก่อนให้คะแนน')),
      );
      return;
    }
    if (_myScore == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('กรุณาเลือกจำนวนดาวก่อนส่งรีวิว')),
      );
      return;
    }

    final token = widget.authService.token!;
    setState(() => _isSubmittingReview = true);
    try {
      await widget.apiService.submitReview(
        token,
        mid: widget.mid,
        score: _myScore,
        comment: _commentController.text.trim().isEmpty
            ? null
            : _commentController.text.trim(),
      );
      _commentController.clear();
      setState(() => _myScore = 0);
      await _loadReviews(); // รีเฟรชรายการรีวิว + คะแนนเฉลี่ยใหม่ทันที
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ขอบคุณสำหรับรีวิว!')),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _isSubmittingReview = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = _menu?.menuName ?? widget.menuNameHint ?? 'รายละเอียดเมนู';

    return Scaffold(
      backgroundColor: AppColors.cream,
      appBar: AppBar(
        backgroundColor: AppColors.leaf,
        foregroundColor: Colors.white,
        titleTextStyle:
            Theme.of(context).appBarTheme.titleTextStyle?.copyWith(color: Colors.white),
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          ValueListenableBuilder<AppUser?>(
            valueListenable: widget.authService.currentUser,
            builder: (context, user, _) {
              if (user == null) return const SizedBox.shrink();
              return IconButton(
                onPressed: _isTogglingFavorite ? null : _toggleFavorite,
                icon: Icon(_isFavorite ? Icons.favorite : Icons.favorite_border),
              );
            },
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoadingMenu) {
      return const Center(child: CircularProgressIndicator(color: AppColors.leaf));
    }
    if (_menuError != null || _menu == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 40, color: AppColors.inkMuted),
              const SizedBox(height: 8),
              Text(_menuError ?? 'ไม่พบเมนูนี้', textAlign: TextAlign.center),
            ],
          ),
        ),
      );
    }

    final menu = _menu!;
    final ingredients =
        menu.ingredient.split('\n').where((s) => s.trim().isNotEmpty).toList();

    return RefreshIndicator(
      color: AppColors.leaf,
      onRefresh: () => Future.wait([_loadMenu(), _loadReviews()]),
      child: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          _buildHeroImage(menu),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(menu.menuName,
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                _buildAverageScoreRow(),
                const SizedBox(height: 22),
                _sectionTitle('วัตถุดิบ', Icons.shopping_basket_outlined),
                const SizedBox(height: 10),
                ...ingredients.map((i) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Padding(
                            padding: EdgeInsets.only(top: 6, right: 8),
                            child: CircleAvatar(radius: 3, backgroundColor: AppColors.leaf),
                          ),
                          Expanded(child: Text(i, style: const TextStyle(height: 1.4))),
                        ],
                      ),
                    )),
                const SizedBox(height: 22),
                _sectionTitle('วิธีทำ', Icons.menu_book_outlined),
                const SizedBox(height: 10),
                Text(menu.method, style: const TextStyle(height: 1.6)),
                const SizedBox(height: 28),
                const Divider(),
                const SizedBox(height: 12),
                _sectionTitle('รีวิวจากผู้ใช้งาน', Icons.reviews_outlined),
                const SizedBox(height: 14),
                _buildReviewForm(),
                const SizedBox(height: 20),
                _buildReviewList(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroImage(FavoriteMenuItem menu) {
    return SizedBox(
      width: double.infinity,
      height: 200,
      child: menu.image != null && menu.image!.isNotEmpty
          ? Image.network(
              menu.image!,
              fit: BoxFit.cover,
              cacheWidth: (MediaQuery.of(context).size.width *
                      MediaQuery.of(context).devicePixelRatio)
                  .round(),
              gaplessPlayback: true,
              errorBuilder: (_, _, _) => _heroPlaceholder(),
            )
          : _heroPlaceholder(),
    );
  }

  Widget _heroPlaceholder() {
    return Container(
      color: const Color(0xFFEAF3E3),
      child: const Center(child: Icon(Icons.restaurant, size: 56, color: AppColors.leaf)),
    );
  }

  Widget _buildAverageScoreRow() {
    final data = _reviewData;
    if (_isLoadingReviews && data == null) {
      return const SizedBox(
        height: 20,
        child: Align(
          alignment: Alignment.centerLeft,
          child: SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.leaf),
          ),
        ),
      );
    }
    if (data == null || data.reviewCount == 0) {
      return const Text(
        'ยังไม่มีรีวิว — เป็นคนแรกที่ให้คะแนนเมนูนี้สิ!',
        style: TextStyle(color: AppColors.inkMuted, fontSize: 13),
      );
    }
    return Row(
      children: [
        StarRating(rating: data.averageScore ?? 0, size: 18),
        const SizedBox(width: 8),
        Text(
          '${(data.averageScore ?? 0).toStringAsFixed(1)} (${data.reviewCount} รีวิว)',
          style: const TextStyle(
            color: AppColors.inkMuted,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _sectionTitle(String text, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.leaf),
        const SizedBox(width: 8),
        Text(text, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
      ],
    );
  }

  Widget _buildReviewForm() {
    return ValueListenableBuilder<AppUser?>(
      valueListenable: widget.authService.currentUser,
      builder: (context, user, _) {
        if (user == null) {
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.line),
            ),
            child: const Text(
              'เข้าสู่ระบบเพื่อให้คะแนนและแสดงความคิดเห็นเมนูนี้',
              style: TextStyle(color: AppColors.inkMuted),
            ),
          );
        }
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('ให้คะแนนเมนูนี้', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 10),
              StarRating(
                rating: _myScore.toDouble(),
                size: 30,
                editable: true,
                onChanged: (value) => setState(() => _myScore = value),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _commentController,
                maxLines: 3,
                decoration: const InputDecoration(hintText: 'แสดงความคิดเห็น (ไม่บังคับ)'),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: ElevatedButton(
                  onPressed: _isSubmittingReview ? null : _submitReview,
                  child: _isSubmittingReview
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('ส่งรีวิว'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildReviewList() {
    final data = _reviewData;
    if (_isLoadingReviews && data == null) {
      return const Center(child: CircularProgressIndicator(color: AppColors.leaf));
    }
    if (data == null || data.reviews.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      children: data.reviews
          .map((r) => Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.line),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(r.fullname, style: const TextStyle(fontWeight: FontWeight.w600)),
                        Text(r.reviewDate,
                            style: const TextStyle(color: AppColors.inkMuted, fontSize: 11)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    StarRating(rating: r.score.toDouble(), size: 15),
                    if (r.comment != null && r.comment!.trim().isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(r.comment!, style: const TextStyle(height: 1.4)),
                    ],
                  ],
                ),
              ))
          .toList(),
    );
  }
}