import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_logo_mark.dart';
import '../widgets/google_logo.dart';
import 'signup_screen.dart';

/// หน้าเข้าสู่ระบบ — ทำตามภาพตัวอย่าง (รูปที่ 1.4 ในเอกสารโครงงาน)
///
/// **ปรับรอบนี้ (ให้สวยขึ้น + ใช้งานง่ายขึ้น):**
///   - เปลี่ยนปุ่ม Google จากตัวอักษร "G" สีเดียว เป็นโลโก้ 4 สีของจริง (`GoogleLogo`)
///   - ฟอร์มกรอกข้อมูลย้ายไปอยู่ใน "การ์ด" ลอยเหนือพื้นหลัง แทนวางบนพื้นขาวเฉยๆ
///     — แยกส่วนหัว (โลโก้) กับส่วนกรอกข้อมูลชัดเจนขึ้น ดูมีมิติมากขึ้น
///   - กด Enter ที่ช่อง Email แล้วโฟกัสกระโดดไปช่อง Password ต่ออัตโนมัติ
///     (`TextInputAction.next` + `FocusNode`) กด Enter ที่ Password แล้วล็อกอิน
///     ได้เลย — ไม่ต้องกดปุ่ม Login ทุกครั้ง เร็วขึ้นสำหรับคนคุ้นเคยแป้นพิมพ์
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.authService});

  final AuthService authService;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _passwordFocusNode = FocusNode();
  bool _obscurePassword = true;
  bool _rememberMe = false;
  bool _isLoading = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _passwordFocusNode.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('กรุณากรอกอีเมลและรหัสผ่าน')),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      await widget.authService.login(email: email, password: password);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleGoogleLogin() async {
    setState(() => _isLoading = true);
    try {
      await widget.authService.loginWithGoogle();
      if (!mounted) return;
      if (widget.authService.isLoggedIn) {
        Navigator.of(context).pop(true);
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('เข้าสู่ระบบด้วย Google ไม่สำเร็จ: $e')),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _goToSignUp() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => SignUpScreen(authService: widget.authService)),
    );
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
              margin: const EdgeInsets.only(top: 4),
              padding: const EdgeInsets.fromLTRB(24, 32, 24, 28),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(28),
                  topRight: Radius.circular(28),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildFieldLabel('Email', textTheme),
                  TextField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    autofillHints: const [AutofillHints.email],
                    onSubmitted: (_) => _passwordFocusNode.requestFocus(),
                    decoration: const InputDecoration(hintText: 'example@gmail.com'),
                  ),
                  const SizedBox(height: 18),
                  _buildFieldLabel('Password', textTheme),
                  TextField(
                    controller: _passwordController,
                    focusNode: _passwordFocusNode,
                    obscureText: _obscurePassword,
                    textInputAction: TextInputAction.done,
                    autofillHints: const [AutofillHints.password],
                    onSubmitted: (_) => _handleLogin(),
                    decoration: InputDecoration(
                      hintText: 'Enter Your Password',
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                          color: AppColors.inkMuted,
                        ),
                        onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Checkbox(
                            value: _rememberMe,
                            onChanged: (v) => setState(() => _rememberMe = v ?? false),
                          ),
                          Text('Remember Me', style: textTheme.bodyMedium),
                        ],
                      ),
                      TextButton(
                        onPressed: () {
                          // TODO: ทำหน้า/flow ลืมรหัสผ่าน
                        },
                        style: TextButton.styleFrom(foregroundColor: AppColors.chili),
                        child: const Text('Forgot Password?'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  ElevatedButton(
                    onPressed: _isLoading ? null : _handleLogin,
                    child: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Login'),
                  ),
                  const SizedBox(height: 18),
                  Center(
                    child: RichText(
                      text: TextSpan(
                        style: textTheme.bodyMedium,
                        children: [
                          const TextSpan(text: "Don't have an account ? "),
                          TextSpan(
                            text: 'Sign Up',
                            style: const TextStyle(
                              color: AppColors.leaf,
                              fontWeight: FontWeight.bold,
                            ),
                            recognizer: TapGestureRecognizer()..onTap = _goToSignUp,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 26),
                  Row(
                    children: [
                      const Expanded(child: Divider()),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Text('Or With', style: textTheme.bodySmall),
                      ),
                      const Expanded(child: Divider()),
                    ],
                  ),
                  const SizedBox(height: 18),
                  OutlinedButton(
                    onPressed: _isLoading ? null : _handleGoogleLogin,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const GoogleLogo(size: 20),
                        const SizedBox(width: 10),
                        const Text('Login with Google'),
                      ],
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
      padding: const EdgeInsets.symmetric(vertical: 36),
      decoration: const BoxDecoration(gradient: AppTheme.headerGradient),
      child: Column(
        children: [
          Container(
            width: 84,
            height: 84,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: AppColors.forest,
              borderRadius: BorderRadius.circular(22),
              boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 4))],
            ),
            child: const AppLogoMark(),
          ),
          const SizedBox(height: 12),
          Text(
            'AI RECIPE',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: Colors.white,
                  letterSpacing: 1.5,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildFieldLabel(String text, TextTheme textTheme) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: textTheme.bodyMedium?.copyWith(color: AppColors.leaf, fontWeight: FontWeight.w600),
      ),
    );
  }
}
