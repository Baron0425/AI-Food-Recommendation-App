import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_logo_mark.dart';

/// หน้าสมัครสมาชิก — ทำตามภาพตัวอย่างในเอกสาร (Create an account)
///
/// **ปรับรอบนี้:** เดิมหน้านี้เป็นพื้นขาวล้วน ไม่มีโลโก้/สีเขียวเลย ทำให้รู้สึก
/// "หลุด" จากหน้า Login ที่อยู่ก่อนหน้าไปทันที (สลับหน้าแล้วเหมือนคนละแอพ) —
/// เพิ่ม header เขียว+โลโก้แบบเดียวกับหน้า Login ให้ต่อเนื่องกัน และไล่โฟกัส
/// ช่องกรอกข้อมูลอัตโนมัติด้วย `TextInputAction`/`FocusNode` เหมือนกัน
class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key, required this.authService});

  final AuthService authService;

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _fullnameController = TextEditingController();
  final _emailController = TextEditingController();
  final _telController = TextEditingController();
  final _passwordController = TextEditingController();

  final _emailFocusNode = FocusNode();
  final _telFocusNode = FocusNode();
  final _passwordFocusNode = FocusNode();

  bool _obscurePassword = true;
  bool _isLoading = false;

  @override
  void dispose() {
    _fullnameController.dispose();
    _emailController.dispose();
    _telController.dispose();
    _passwordController.dispose();
    _emailFocusNode.dispose();
    _telFocusNode.dispose();
    _passwordFocusNode.dispose();
    super.dispose();
  }

  Future<void> _handleSignUp() async {
    final fullname = _fullnameController.text.trim();
    final email = _emailController.text.trim();
    final tel = _telController.text.trim();
    final password = _passwordController.text;

    if (fullname.isEmpty || email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('กรุณากรอกชื่อผู้ใช้ อีเมล และรหัสผ่านให้ครบ')),
      );
      return;
    }
    if (password.length < 8) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('รหัสผ่านต้องมีอย่างน้อย 8 ตัวอักษร')),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      await widget.authService.register(
        email: email,
        fullname: fullname,
        password: password,
        tel: tel.isEmpty ? null : tel,
      );
      if (!mounted) return;
      // สมัครสำเร็จ = ล็อกอินให้อัตโนมัติแล้ว (ดู AuthService.register) —
      // pop กลับไปหน้าที่เปิด Login มา
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: AppColors.leaf,
      body: SingleChildScrollView(
        child: Column(
          children: [
            _buildHeader(context),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(28),
                  topRight: Radius.circular(28),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Create an account',
                    textAlign: TextAlign.center,
                    style: textTheme.headlineSmall?.copyWith(color: AppColors.leaf),
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: _fullnameController,
                    textInputAction: TextInputAction.next,
                    onSubmitted: (_) => _emailFocusNode.requestFocus(),
                    decoration: const InputDecoration(hintText: 'Enter Your Username'),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _emailController,
                    focusNode: _emailFocusNode,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    onSubmitted: (_) => _telFocusNode.requestFocus(),
                    decoration: const InputDecoration(hintText: 'Enter Your Email'),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _telController,
                    focusNode: _telFocusNode,
                    keyboardType: TextInputType.phone,
                    textInputAction: TextInputAction.next,
                    onSubmitted: (_) => _passwordFocusNode.requestFocus(),
                    decoration: const InputDecoration(hintText: 'Enter Your Phone Number'),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _passwordController,
                    focusNode: _passwordFocusNode,
                    obscureText: _obscurePassword,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _handleSignUp(),
                    decoration: InputDecoration(
                      hintText: 'Enter Your Password',
                      helperText: 'อย่างน้อย 8 ตัวอักษร',
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                          color: AppColors.inkMuted,
                        ),
                        onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  ElevatedButton(
                    onPressed: _isLoading ? null : _handleSignUp,
                    child: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Sign Up'),
                  ),
                  const SizedBox(height: 16),
                  Center(
                    child: TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: RichText(
                        text: TextSpan(
                          style: textTheme.bodyMedium,
                          children: const [
                            TextSpan(
                              text: 'Already have an account? ',
                              style: TextStyle(decoration: TextDecoration.underline),
                            ),
                            TextSpan(
                              text: 'Login',
                              style: TextStyle(color: AppColors.leaf, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 28),
      decoration: const BoxDecoration(gradient: AppTheme.headerGradient),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.arrow_back, color: Colors.white),
              ),
            ],
          ),
          Container(
            width: 64,
            height: 64,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.forest,
              borderRadius: BorderRadius.circular(18),
              boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 8, offset: Offset(0, 3))],
            ),
            child: const AppLogoMark(size: 36),
          ),
        ],
      ),
    );
  }
}
