import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/utils/responsive.dart';
import '../widgets/gradient_button.dart';
import '../widgets/custom_text_field.dart';
import 'register_screen.dart';
import 'forgot_password_screen.dart';
import '../../home/screens/home_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;

    final authProvider = context.read<AuthProvider>();
    final success = await authProvider.login(
      _emailController.text.trim(),
      _passwordController.text,
    );

    if (!mounted) return;

    if (success) {
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (_, __, ___) => const HomeScreen(),
          transitionDuration: const Duration(milliseconds: 600),
          transitionsBuilder: (_, animation, __, child) => SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(1.0, 0.0),
              end: Offset.zero,
            ).animate(CurvedAnimation(parent: animation, curve: Curves.easeInOut)),
            child: child,
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(authProvider.errorMessage ?? 'Đăng nhập thất bại'),
          backgroundColor: AppTheme.danger,
          behavior: SnackBarBehavior.floating,
          margin: EdgeInsets.only(
            bottom: R.bottom(context) + 16,
            left: 16,
            right: 16,
          ),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final hp = R.hPad(context);
    final logoSize = (R.w(context) * 0.2).clamp(70.0, 100.0);

    return Scaffold(
      backgroundColor: AppTheme.bgDark,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0D1130), Color(0xFF0A0E21), Color(0xFF0D1130)],
          ),
        ),
        child: SafeArea(
          bottom: true,
          child: SingleChildScrollView(
            padding: EdgeInsets.only(
              left: hp,
              right: hp,
              bottom: R.bottom(context) + 16,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(height: R.sp(context, 40)),
                Center(
                  child: Column(
                    children: [
                      Container(
                        width: logoSize,
                        height: logoSize,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: const LinearGradient(
                            colors: [AppTheme.primary, AppTheme.secondary],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: AppTheme.primary.withValues(alpha: 0.4),
                              blurRadius: 20,
                              spreadRadius: 5,
                            ),
                          ],
                        ),
                        child: Icon(Icons.school_rounded,
                            size: logoSize * 0.5, color: Colors.white),
                      ).animate().scale(duration: 600.ms, curve: Curves.elasticOut),
                      SizedBox(height: R.sp(context, 16)),
                      Text(
                        'Lớp Học Thông Minh',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                              color: AppTheme.textPrimary,
                              fontWeight: FontWeight.bold,
                              fontSize: R.fs(context, 26),
                            ),
                      ).animate(delay: 200.ms).fadeIn().slideY(begin: 0.2),
                      SizedBox(height: R.sp(context, 8)),
                      Text(
                        'Đăng nhập trên thiết bị (local)',
                        style: TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: R.fs(context, 13),
                        ),
                      ).animate(delay: 250.ms).fadeIn(),
                    ],
                  ),
                ),
                SizedBox(height: R.sp(context, 40)),
                Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      CustomTextField(
                        controller: _emailController,
                        label: 'Email',
                        hint: 'example@email.com',
                        prefixIcon: Icons.email_rounded,
                        keyboardType: TextInputType.emailAddress,
                        validator: (v) {
                          if (v == null || v.isEmpty) return 'Vui lòng nhập email';
                          if (!v.contains('@')) return 'Email không hợp lệ';
                          return null;
                        },
                      ).animate(delay: 400.ms).fadeIn().slideX(begin: -0.2),
                      SizedBox(height: R.sp(context, 16)),
                      CustomTextField(
                        controller: _passwordController,
                        label: 'Mật khẩu',
                        hint: '••••••••',
                        prefixIcon: Icons.lock_rounded,
                        obscureText: _obscurePassword,
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_off_rounded
                                : Icons.visibility_rounded,
                            color: AppTheme.textMuted,
                          ),
                          onPressed: () =>
                              setState(() => _obscurePassword = !_obscurePassword),
                        ),
                        validator: (v) {
                          if (v == null || v.isEmpty) return 'Vui lòng nhập mật khẩu';
                          if (v.length < 6) return 'Mật khẩu ít nhất 6 ký tự';
                          return null;
                        },
                      ).animate(delay: 500.ms).fadeIn().slideX(begin: 0.2),
                      SizedBox(height: R.sp(context, 8)),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const ForgotPasswordScreen()),
                          ),
                          child: Text(
                            'Quên mật khẩu?',
                            style: TextStyle(
                              color: AppTheme.primaryLight,
                              fontSize: R.fs(context, 13),
                            ),
                          ),
                        ),
                      ).animate(delay: 600.ms).fadeIn(),
                      SizedBox(height: R.sp(context, 16)),
                      Consumer<AuthProvider>(
                        builder: (_, auth, __) => GradientButton(
                          onPressed:
                              auth.status == AuthStatus.loading ? null : _handleLogin,
                          isLoading: auth.status == AuthStatus.loading,
                          text: 'Đăng Nhập',
                          icon: Icons.login_rounded,
                        ),
                      ).animate(delay: 700.ms).fadeIn().slideY(begin: 0.3),
                    ],
                  ),
                ),
                SizedBox(height: R.sp(context, 28)),
                Center(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Chưa có tài khoản? ',
                        style: TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: R.fs(context, 14)),
                      ),
                      TextButton(
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const RegisterScreen()),
                        ),
                        child: Text(
                          'Đăng ký ngay',
                          style: TextStyle(
                            color: AppTheme.secondary,
                            fontWeight: FontWeight.bold,
                            fontSize: R.fs(context, 14),
                          ),
                        ),
                      ),
                    ],
                  ),
                ).animate(delay: 800.ms).fadeIn(),
                SizedBox(height: R.sp(context, 20)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
