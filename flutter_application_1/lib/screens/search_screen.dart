import 'package:flutter/material.dart';

import '../models/menu_result.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import 'menu_detail_screen.dart';

/// หน้าค้นหาเมนู/วัตถุดิบ — เชื่อมกับ GET /api/search (auto-detect)
///
/// **ปรับรอบนี้ (ใช้งานง่ายขึ้น):**
///   - เพิ่มปุ่มกากบาทล้างช่องค้นหาเมื่อพิมพ์อะไรไว้ (กดล้างได้ไม่ต้องลบเอง)
///   - เพิ่มชิปคำค้นหาตัวอย่างตอนยังไม่เคยค้นหา (สำหรับคนใหม่ที่ไม่รู้จะพิมพ์
///     อะไรก่อน) กดชิปแล้วค้นหาให้ทันที
///   - ผลลัพธ์มี fade-in transition แทนโผล่มาเฉยๆ ให้ความรู้สึกลื่นขึ้น
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key, required this.apiService, required this.authService});

  final ApiService apiService;
  // เพิ่มเข้ามา — ต้องใช้ส่งต่อให้ MenuDetailScreen ตอนกด "ดูรีวิว & ให้คะแนน"
  // ในชีทรายละเอียดด้านล่าง (เดิมหน้านี้ไม่รู้จัก auth เลยเพราะแค่ค้นหา/แสดงผล
  // ไม่มีอะไรต้องล็อกอิน)
  final AuthService authService;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  static const _suggestions = ['ผัดไทย', 'ต้มยำกุ้ง', 'กะเพราหมูสับ', 'แกงเขียวหวาน', 'ข้าวมันไก่'];

  final _controller = TextEditingController();
  final _focusNode = FocusNode();

  List<MenuResult> _results = [];
  bool _isLoading = false;
  String? _errorMessage;
  bool _hasSearchedOnce = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focusNode.requestFocus());
    _controller.addListener(() => setState(() {})); // รีเฟรชปุ่มล้าง (X) ตามความยาวข้อความ
  }

  Future<void> _search([String? overrideQuery]) async {
    final query = (overrideQuery ?? _controller.text).trim();
    if (query.isEmpty) return;

    if (overrideQuery != null) {
      _controller.text = overrideQuery;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _hasSearchedOnce = true;
    });

    try {
      final response = await widget.apiService.searchAuto(query, topK: 5);
      if (!mounted) return;
      setState(() => _results = response.results);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.message;
        _results = [];
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _clearSearch() {
    setState(() {
      _controller.clear();
      _results = [];
      _hasSearchedOnce = false;
      _errorMessage = null;
    });
    _focusNode.requestFocus();
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.cream,
      appBar: AppBar(
        backgroundColor: AppColors.leaf,
        foregroundColor: Colors.white,
        titleTextStyle: Theme.of(context).appBarTheme.titleTextStyle?.copyWith(color: Colors.white),
        title: const Text('ค้นหาเมนูอาหาร'),
      ),
      body: Column(
        children: [
          Container(
            color: AppColors.leaf,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 8, offset: const Offset(0, 3)),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      focusNode: _focusNode,
                      decoration: const InputDecoration(
                        hintText: 'พิมพ์ชื่อเมนู หรือ วัตถุดิบ...',
                        border: InputBorder.none,
                        filled: false,
                      ),
                      textInputAction: TextInputAction.search,
                      onSubmitted: (_) => _search(),
                    ),
                  ),
                  if (_controller.text.isNotEmpty)
                    IconButton(
                      onPressed: _clearSearch,
                      icon: const Icon(Icons.close, color: AppColors.inkMuted, size: 20),
                    ),
                  IconButton(
                    onPressed: _isLoading ? null : () => _search(),
                    icon: const Icon(Icons.search, color: AppColors.leaf),
                  ),
                ],
              ),
            ),
          ),
          if (_errorMessage != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(_errorMessage!, style: const TextStyle(color: AppColors.chili)),
            ),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: _buildResultsArea(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResultsArea() {
    if (_isLoading) {
      return const Center(
        key: ValueKey('loading'),
        child: CircularProgressIndicator(color: AppColors.leaf),
      );
    }
    if (!_hasSearchedOnce) {
      return _buildSuggestions();
    }
    if (_results.isEmpty) {
      return _buildHint(key: 'empty', icon: Icons.search_off, message: 'ไม่พบเมนูที่เกี่ยวข้อง');
    }
    return ListView.separated(
      key: const ValueKey('results'),
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: _results.length,
      separatorBuilder: (_, _) => const Divider(height: 1, indent: 16, endIndent: 16),
      itemBuilder: (context, index) {
        final r = _results[index];
        return InkWell(
          onTap: () => _showRecipeDetail(r),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(r.menu, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                      const SizedBox(height: 4),
                      Text(
                        r.ingredients.take(5).join(', '),
                        style: const TextStyle(color: AppColors.inkMuted, fontSize: 12),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEAF3E3),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${(r.score * 100).toStringAsFixed(0)}%',
                    style: const TextStyle(color: AppColors.leaf, fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSuggestions() {
    return SingleChildScrollView(
      key: const ValueKey('suggestions'),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 12),
          Center(
            child: Icon(Icons.restaurant_menu, size: 40, color: AppColors.inkMuted),
          ),
          const SizedBox(height: 8),
          const Center(
            child: Text('พิมพ์คำค้นหาแล้วกดค้นหาได้เลย', style: TextStyle(color: AppColors.inkMuted)),
          ),
          const SizedBox(height: 20),
          const Text('ลองค้นหาดู', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _suggestions
                .map(
                  (s) => ActionChip(
                    label: Text(s),
                    backgroundColor: const Color(0xFFEAF3E3),
                    labelStyle: const TextStyle(color: AppColors.leaf, fontWeight: FontWeight.w600),
                    side: BorderSide.none,
                    onPressed: () => _search(s),
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildHint({required String key, required IconData icon, required String message}) {
    return Center(
      key: ValueKey(key),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 40, color: AppColors.inkMuted),
          const SizedBox(height: 8),
          Text(message, style: const TextStyle(color: AppColors.inkMuted)),
        ],
      ),
    );
  }

  void _showRecipeDetail(MenuResult r) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        builder: (context, scrollController) => SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: AppColors.line,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(r.menu, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              const Text('วัตถุดิบ', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.leaf)),
              const SizedBox(height: 6),
              ...r.ingredients.map((i) => Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text('•  $i'),
                  )),
              const SizedBox(height: 16),
              const Text('วิธีทำ', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.leaf)),
              const SizedBox(height: 6),
              Text(r.method, style: const TextStyle(height: 1.5)),
              const SizedBox(height: 20),
              // ใหม่: ลิงก์ไปหน้ารายละเอียดเต็ม (รูป/รีวิว/ให้ดาว) — ใช้หน้า
              // เดียวกับที่เปิดจากการ์ดเมนูในหน้าหลัก ให้ประสบการณ์สอดคล้องกัน
              // ทั้งแอพ ไม่มีรีวิวแยกอยู่แค่ในผลค้นหาแบบคนละที่คนละแบบ
              if (r.mid != null)
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.of(context).pop(); // ปิด bottom sheet ก่อนค่อยเปิดหน้าใหม่
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => MenuDetailScreen(
                            mid: r.mid!,
                            apiService: widget.apiService,
                            authService: widget.authService,
                            menuNameHint: r.menu,
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.reviews_outlined, size: 18),
                    label: const Text('ดูรีวิว & ให้คะแนน'),
                  ),
                ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
