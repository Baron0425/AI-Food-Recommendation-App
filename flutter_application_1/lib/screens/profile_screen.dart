import 'package:flutter/material.dart';

import '../models/user.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';

/// หน้าโปรไฟล์ผู้ใช้ที่ล็อกอินแล้ว — แสดงข้อมูล + แก้ไขข้อมูลส่วนตัว (ขอบเขต
/// งานข้อ 2.2 ในเอกสาร: ชื่อนามสกุล, รหัสผ่าน, เบอร์โทรศัพท์) + ปุ่ม Logout
///
/// **ปรับรอบนี้:** เดิมฟิลด์ทั้งหมดเรียงเป็น list เดียวยาวๆ แยกไม่ออกว่าส่วนไหน
/// คือ "ข้อมูลส่วนตัว" ส่วนไหนคือ "เปลี่ยนรหัสผ่าน" — จัดกลุ่มเป็นการ์ดแยกส่วน
/// ให้เห็นชัดเจนขึ้น พร้อมเพิ่มพื้นหลังเขียวด้านบนให้ดูมีมิติแทนพื้นขาวล้วน
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, required this.authService});

  final AuthService authService;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late final TextEditingController _fullnameController;
  late final TextEditingController _telController;
  final _newPasswordController = TextEditingController();
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final user = widget.authService.currentUser.value;
    _fullnameController = TextEditingController(text: user?.fullname ?? '');
    _telController = TextEditingController(text: user?.tel ?? '');
  }

  @override
  void dispose() {
    _fullnameController.dispose();
    _telController.dispose();
    _newPasswordController.dispose();
    super.dispose();
  }

  Future<void> _handleSave() async {
    setState(() => _isSaving = true);
    try {
      await widget.authService.updateProfile(
        fullname: _fullnameController.text.trim(),
        tel: _telController.text.trim(),
        password: _newPasswordController.text.isEmpty ? null : _newPasswordController.text,
      );
      _newPasswordController.clear();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('บันทึกข้อมูลเรียบร้อย')),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _handleLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ออกจากระบบ'),
        content: const Text('ต้องการออกจากระบบใช่ไหม'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('ยกเลิก')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.chili),
            child: const Text('ออกจากระบบ'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await widget.authService.logout();
    if (!mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return ValueListenableBuilder<AppUser?>(
      valueListenable: widget.authService.currentUser,
      builder: (context, user, _) {
        if (user == null) {
          return const Scaffold(body: Center(child: Text('กรุณาเข้าสู่ระบบก่อน')));
        }
        return Scaffold(
          backgroundColor: AppColors.cream,
          body: CustomScrollView(
            slivers: [
              SliverAppBar(
                pinned: true,
                expandedHeight: 190,
                backgroundColor: AppColors.leaf,
                iconTheme: const IconThemeData(color: Colors.white),
                flexibleSpace: FlexibleSpaceBar(
                  background: Container(
                    decoration: const BoxDecoration(gradient: AppTheme.headerGradient),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 76,
                            height: 76,
                            decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                            child: const Icon(Icons.person, size: 42, color: AppColors.leaf),
                          ),
                          const SizedBox(height: 10),
                          Text(user.fullname,
                              style: textTheme.titleLarge?.copyWith(color: Colors.white)),
                          Text(user.email,
                              style: textTheme.bodySmall?.copyWith(color: Colors.white70)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _sectionCard(
                        title: 'ข้อมูลส่วนตัว',
                        icon: Icons.badge_outlined,
                        children: [
                          _fieldLabel('ชื่อ-นามสกุล', textTheme),
                          TextField(controller: _fullnameController),
                          const SizedBox(height: 14),
                          _fieldLabel('เบอร์โทรศัพท์', textTheme),
                          TextField(controller: _telController, keyboardType: TextInputType.phone),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _sectionCard(
                        title: 'เปลี่ยนรหัสผ่าน',
                        icon: Icons.lock_outline,
                        children: [
                          Text(
                            'เว้นว่างไว้ถ้าไม่ต้องการเปลี่ยนรหัสผ่าน',
                            style: textTheme.bodySmall,
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _newPasswordController,
                            obscureText: true,
                            decoration: const InputDecoration(hintText: 'รหัสผ่านใหม่'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton(
                        onPressed: _isSaving ? null : _handleSave,
                        child: _isSaving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Text('บันทึก'),
                      ),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        onPressed: _handleLogout,
                        icon: const Icon(Icons.logout, size: 18, color: AppColors.chili),
                        label: const Text('ออกจากระบบ'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.chili,
                          side: const BorderSide(color: AppColors.chili),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _sectionCard({required String title, required IconData icon, required List<Widget> children}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: AppColors.leaf),
              const SizedBox(width: 8),
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }

  Widget _fieldLabel(String text, TextTheme textTheme) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(text, style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
    );
  }
}
