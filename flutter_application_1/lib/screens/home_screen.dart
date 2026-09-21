import 'package:flutter/material.dart';

import '../models/menu_result.dart';
import '../models/user.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../widgets/menu_card.dart';
import 'login_screen.dart';
import 'menu_detail_screen.dart';
import 'profile_screen.dart';
import 'search_screen.dart';

/// หน้าหลัก — ทำตามภาพตัวอย่างในเอกสารโครงงาน (รูปที่ 1.5)
///
/// **แก้บัคปุ่มหัวใจ (รอบนี้):** เดิมโหลดรายการเมนูโปรด (`_favoriteMenus`)
/// เฉพาะตอนกดแท็บ "เมนูโปรด" เท่านั้น ทำให้ตอนอยู่แท็บ "เมนูยอดนิยม" ระบบไม่รู้
/// เลยว่าเมนูไหนเป็นโปรดอยู่แล้วบ้าง (`_favoriteMenus` เป็นลิสต์ว่างเสมอ) กด
/// หัวใจกี่ครั้งก็ถูกตีความว่า "ยังไม่ใช่โปรด" ตลอด เลยเรียก add ซ้ำๆ ไม่เคย
/// เรียก remove ได้เลยจากแท็บนี้ — แก้โดยเปลี่ยนมาเก็บเป็น `Set<int>` ของ MID
/// ที่เป็นโปรด (`_favoriteMids`) แล้วโหลดล่วงหน้าทันทีที่รู้ว่าล็อกอินแล้ว
/// (ไม่ต้องรอกดแท็บก่อน) ทำให้ไอคอนหัวใจถูกต้องไม่ว่าจะอยู่แท็บไหน และเพิ่ม
/// optimistic update (สลับสถานะหัวใจทันทีที่กด ไม่ต้องรอ API ตอบกลับ) ให้รู้สึก
/// ลื่นขึ้น พร้อม rollback อัตโนมัติถ้า API error
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.apiService, required this.authService});

  final ApiService apiService;
  final AuthService authService;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedTab = 0; // 0 = เมนูยอดนิยม, 1 = เมนูโปรด
  int _bottomNavIndex = 0;

  List<FavoriteMenuItem> _popularMenus = [];
  List<FavoriteMenuItem> _favoriteMenus = [];
  final Set<int> _favoriteMids = {}; // แหล่งความจริงเดียวว่า MID ไหนเป็นโปรด ใช้ทุกแท็บ

  bool _isLoadingGrid = false;
  String? _gridError;

  @override
  void initState() {
    super.initState();
    _loadPopularMenus();
    if (widget.authService.isLoggedIn) {
      _loadFavoriteMids();
    }
    widget.authService.currentUser.addListener(_onAuthChanged);
  }

  @override
  void dispose() {
    widget.authService.currentUser.removeListener(_onAuthChanged);
    super.dispose();
  }

  void _onAuthChanged() {
    if (widget.authService.isLoggedIn) {
      _loadFavoriteMids();
    } else {
      setState(() {
        _favoriteMids.clear();
        _favoriteMenus = [];
        if (_selectedTab == 1) _selectedTab = 0; // ออกจากระบบระหว่างอยู่แท็บโปรด -> กลับแท็บยอดนิยม
      });
    }
  }

  Future<void> _loadPopularMenus() async {
    setState(() {
      _isLoadingGrid = true;
      _gridError = null;
    });
    try {
      final menus = await widget.apiService.getPopularMenus();
      if (!mounted) return;
      setState(() => _popularMenus = menus);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _gridError = e.message);
    } finally {
      if (mounted) setState(() => _isLoadingGrid = false);
    }
  }

  /// โหลดรายการโปรดล่วงหน้าเสมอเมื่อรู้ว่าล็อกอินแล้ว (ไม่ต้องรอกดแท็บ) —
  /// เก็บทั้ง `_favoriteMenus` (ไว้แสดงในแท็บโปรด) และ `_favoriteMids`
  /// (ไว้เช็คสถานะหัวใจแบบเร็วในทุกแท็บ)
  Future<void> _loadFavoriteMids() async {
    final token = widget.authService.token;
    if (token == null) return;
    try {
      final menus = await widget.apiService.getFavorites(token);
      if (!mounted) return;
      setState(() {
        _favoriteMenus = menus;
        _favoriteMids
          ..clear()
          ..addAll(menus.map((m) => m.mid));
      });
    } on ApiException {
      // โหลดพื้นหลังเงียบๆ ล้มเหลวก็ไม่เป็นไร ไม่ต้องรบกวนผู้ใช้ด้วย error ทันที
      // ตอนเปิดแอพ — เดี๋ยวกดหัวใจจริงแล้วค่อยเจอ error ถ้ายังมีปัญหาอยู่
    }
  }

  Future<void> _toggleFavorite(FavoriteMenuItem item) async {
    if (!widget.authService.isLoggedIn) {
      _goToLogin();
      return;
    }
    final token = widget.authService.token!;
    final wasFavorite = _favoriteMids.contains(item.mid);

    // Optimistic update: สลับสถานะทันทีให้ผู้ใช้เห็นผลลัพธ์ไว ไม่ต้องรอ API
    setState(() {
      if (wasFavorite) {
        _favoriteMids.remove(item.mid);
        _favoriteMenus.removeWhere((m) => m.mid == item.mid);
      } else {
        _favoriteMids.add(item.mid);
        _favoriteMenus.add(item);
      }
    });

    try {
      if (wasFavorite) {
        await widget.apiService.removeFavorite(token, item.mid);
      } else {
        await widget.apiService.addFavorite(token, item.mid);
      }
    } on ApiException catch (e) {
      // rollback กลับสถานะเดิมถ้า API ล้มเหลว
      if (!mounted) return;
      setState(() {
        if (wasFavorite) {
          _favoriteMids.add(item.mid);
          _favoriteMenus.add(item);
        } else {
          _favoriteMids.remove(item.mid);
          _favoriteMenus.removeWhere((m) => m.mid == item.mid);
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  void _goToSearch() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SearchScreen(apiService: widget.apiService, authService: widget.authService),
      ),
    );
  }

  /// เปิดหน้ารายละเอียดเมนู (รูป/วัตถุดิบ/วิธีทำเต็ม + รีวิว/ให้ดาว) — แก้ตาม
  /// TODO เดิมในการ์ดเมนูด้านล่างที่ตั้งใจไว้ตั้งแต่แรกว่าจะทำหน้านี้
  void _goToMenuDetail(FavoriteMenuItem item) {
    Navigator.of(context)
        .push(
      MaterialPageRoute(
        builder: (_) => MenuDetailScreen(
          mid: item.mid,
          apiService: widget.apiService,
          authService: widget.authService,
          menuNameHint: item.menuName,
        ),
      ),
    )
        .then((_) {
      // กลับมาจากหน้ารายละเอียด (อาจกดถูกใจ/ยกเลิกถูกใจไว้ในนั้น) — รีเฟรช
      // สถานะโปรดให้ตรงกันอีกครั้ง กันไอคอนหัวใจในกริดค้างสถานะเก่า
      if (widget.authService.isLoggedIn) _loadFavoriteMids();
    });
  }

  Future<void> _goToProfileOrLogin() async {
    if (widget.authService.isLoggedIn) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ProfileScreen(authService: widget.authService)),
      );
      return;
    }
    _goToLogin();
  }

  Future<void> _goToLogin() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => LoginScreen(authService: widget.authService)),
    );
    // _onAuthChanged (ผูกไว้กับ authService.currentUser listener) จะจัดการ
    // โหลดรายการโปรดให้เองอัตโนมัติถ้าล็อกอินสำเร็จ ไม่ต้องเรียกซ้ำตรงนี้
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.cream,
      body: SafeArea(
        child: RefreshIndicator(
          color: AppColors.leaf,
          onRefresh: () async {
            await _loadPopularMenus();
            if (widget.authService.isLoggedIn) await _loadFavoriteMids();
          },
          child: Column(
            children: [
              _buildHeader(),
              const SizedBox(height: 18),
              _buildTabToggle(),
              const SizedBox(height: 10),
              _buildSectionCount(),
              const SizedBox(height: 6),
              Expanded(child: _buildMenuGrid()),
            ],
          ),
        ),
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 30),
      decoration: const BoxDecoration(
        gradient: AppTheme.headerGradient,
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(28),
          bottomRight: Radius.circular(28),
        ),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              GestureDetector(
                onTap: _goToProfileOrLogin,
                child: ValueListenableBuilder<AppUser?>(
                  valueListenable: widget.authService.currentUser,
                  builder: (context, user, _) => CircleAvatar(
                    radius: 18,
                    backgroundColor: Colors.white24,
                    child: Icon(
                      user == null ? Icons.person_outline : Icons.person,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              ValueListenableBuilder<AppUser?>(
                valueListenable: widget.authService.currentUser,
                builder: (context, user, _) => user == null
                    ? const SizedBox.shrink()
                    : GestureDetector(
                        onTap: () async {
                          await widget.authService.logout();
                          if (!mounted) return;
                          // เคลียร์สถานะหัวใจ/เมนูโปรดตรงนี้ทันที แบบ
                          // ไม่รอ listener — กันเคส "หัวใจค้าง" ที่เคยเจอ
                          // (เดิมพึ่ง _onAuthChanged อย่างเดียว ซึ่งควรจะทำงาน
                          // ถูกอยู่แล้ว แต่เพิ่มจุดนี้ไว้เป็น safety net ให้
                          // ชัวร์ 100% ไม่ต้องลุ้นเรื่อง timing ของ listener)
                          setState(() {
                            _favoriteMids.clear();
                            _favoriteMenus = [];
                            _selectedTab = 0;
                          });
                          _loadPopularMenus();
                        },
                        child: const Icon(Icons.power_settings_new, color: Colors.white),
                      ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ValueListenableBuilder<AppUser?>(
            valueListenable: widget.authService.currentUser,
            builder: (context, user, _) => Align(
              alignment: Alignment.centerLeft,
              child: Text(
                user == null ? 'หิวไหม? มาหาเมนูกัน' : 'สวัสดี, ${user.fullname} 👋',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          GestureDetector(
            onTap: _goToSearch,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 10, offset: const Offset(0, 4)),
                ],
              ),
              child: const Row(
                children: [
                  Expanded(
                    child: Text('Search for Food', style: TextStyle(color: AppColors.inkMuted)),
                  ),
                  Icon(Icons.search, color: AppColors.inkMuted),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabToggle() {
    // ก่อนล็อกอินมีแค่ pill "เมนูยอดนิยม" อันเดียวตรงกลาง (ตามภาพในเอกสาร) —
    // pill "เมนูโปรด" โผล่มาเมื่อล็อกอินแล้วเท่านั้น
    return ValueListenableBuilder<AppUser?>(
      valueListenable: widget.authService.currentUser,
      builder: (context, user, _) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _tabChip(label: 'เมนูยอดนิยม', index: 0),
            if (user != null) ...[
              const SizedBox(width: 12),
              _tabChip(label: 'เมนูโปรด', index: 1, icon: Icons.favorite_border),
            ],
          ],
        );
      },
    );
  }

  Widget _tabChip({required String label, required int index, IconData? icon}) {
    final isSelected = _selectedTab == index;
    return GestureDetector(
      onTap: () => setState(() => _selectedTab = index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFEAF3E3) : Colors.white,
          border: Border.all(color: isSelected ? AppColors.leaf : AppColors.line),
          borderRadius: BorderRadius.circular(24),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 15, color: AppColors.leaf),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: TextStyle(
                color: isSelected ? AppColors.leaf : AppColors.ink,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionCount() {
    if (_isLoadingGrid || _gridError != null) return const SizedBox.shrink();
    final count = _selectedTab == 0 ? _popularMenus.length : _favoriteMenus.length;
    if (count == 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          _selectedTab == 0 ? 'เมนูแนะนำ $count เมนู' : 'เมนูโปรดของคุณ $count เมนู',
          style: const TextStyle(color: AppColors.inkMuted, fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  Widget _buildMenuGrid() {
    if (_isLoadingGrid) {
      return const Center(child: CircularProgressIndicator(color: AppColors.leaf));
    }
    if (_gridError != null) {
      return _buildEmptyState(icon: Icons.wifi_off, message: _gridError!);
    }

    final menus = _selectedTab == 0 ? _popularMenus : _favoriteMenus;
    if (menus.isEmpty) {
      return _buildEmptyState(
        icon: _selectedTab == 0 ? Icons.restaurant_menu : Icons.favorite_border,
        message: _selectedTab == 0 ? 'ยังไม่มีเมนูในระบบ' : 'ยังไม่มีเมนูโปรด ลองกดหัวใจเมนูที่ชอบดูสิ',
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      itemCount: menus.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final item = menus[index];
        return MenuCard(
          item: item,
          onTap: () => _goToMenuDetail(item),
          isFavorite: _favoriteMids.contains(item.mid),
          // เฉพาะสมาชิก (ล็อกอินแล้ว) เท่านั้นที่กดหัวใจได้ ตามขอบเขตงานข้อ
          // 1.x/2.x ในเอกสาร (การกดถูกใจเป็นความสามารถของ "ผู้ใช้งานสมาชิก")
          // — ผู้ใช้ทั่วไปจะไม่เห็นไอคอนหัวใจเลย (ดู MenuCard: ไม่ render ถ้า
          // onToggleFavorite เป็น null) แทนที่จะปล่อยให้กดได้แล้วเด้งไปหน้า
          // login ซึ่งทำให้ดูเหมือน "กดได้" ทั้งที่ไม่ควรมีปุ่มให้กดตั้งแต่แรก
          onToggleFavorite:
              widget.authService.isLoggedIn ? () => _toggleFavorite(item) : null,
        );
      },
    );
  }

  Widget _buildEmptyState({required IconData icon, required String message}) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 40, color: AppColors.inkMuted),
          const SizedBox(height: 8),
          Text(message, style: const TextStyle(color: AppColors.inkMuted), textAlign: TextAlign.center),
        ],
      ),
    );
  }

  Widget _buildBottomNav() {
    return BottomNavigationBar(
      currentIndex: _bottomNavIndex,
      onTap: (index) async {
        if (index == 1) {
          await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) =>
                  SearchScreen(apiService: widget.apiService, authService: widget.authService),
            ),
          );
          return;
        }
        if (index == 2) {
          // ยังไม่มีหน้า "ประวัติ" จริง — เดิมกดแล้วไม่มีอะไรเกิดขึ้นเลย (แค่
          // ไฮไลต์ปุ่มเฉยๆ) ทำให้ดูเหมือนแอพค้าง ใส่ SnackBar แจ้งไว้ก่อน
          // ดีกว่าปล่อยให้กดแล้วเงียบแบบเดิม จนกว่าจะมีหน้าจริงมารองรับ
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('ฟีเจอร์ประวัติการค้นหา เร็วๆ นี้')),
          );
          return;
        }
        if (index == 3) {
          await _goToProfileOrLogin();
          return;
        }
        setState(() => _bottomNavIndex = index);
      },
      items: const [
        BottomNavigationBarItem(icon: Icon(Icons.home), label: 'หน้าหลัก'),
        BottomNavigationBarItem(icon: Icon(Icons.search), label: 'ค้นหา'),
        BottomNavigationBarItem(icon: Icon(Icons.receipt_long), label: 'ประวัติ'),
        BottomNavigationBarItem(icon: Icon(Icons.person), label: 'โปรไฟล์'),
      ],
    );
  }
}
