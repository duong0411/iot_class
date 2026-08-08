import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/responsive.dart';
import 'package:provider/provider.dart';
import '../../../core/providers/auth_provider.dart';
import '../../home/screens/home_screen.dart';
import 'login_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _navigate();
  }

  Future<void> _navigate() async {
    // Chờ 1.5s để hiện Splash Screen đẹp mắt
    await Future.delayed(const Duration(milliseconds: 1500));
    if (!mounted) return;

    // Tự động vào thẳng HomeScreen không qua màn hình Đăng Nhập
    final authProvider = context.read<AuthProvider>();
    await authProvider.checkAuthStatus();

    if (mounted) {
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (_, __, ___) => const HomeScreen(),
          transitionDuration: const Duration(milliseconds: 800),
          transitionsBuilder: (_, animation, __, child) =>
              FadeTransition(opacity: animation, child: child),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final logoSize = (R.w(context) * 0.28).clamp(90.0, 130.0);

    return Scaffold(
      backgroundColor: AppTheme.bgDark,
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.center,
            radius: 1.5,
            colors: [Color(0xFF1A1F38), Color(0xFF0A0E21)],
          ),
        ),
        child: SafeArea(
          bottom: true,
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Logo
                Container(
                  width: logoSize,
                  height: logoSize,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [AppTheme.primary, AppTheme.secondary],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.primary.withValues(alpha: 0.4),
                        blurRadius: 40,
                        spreadRadius: 10,
                      ),
                    ],
                  ),
                  child: Icon(
                    Icons.school_rounded,
                    size: logoSize * 0.5,
                    color: Colors.white,
                  ),
                ).animate().scale(
                      duration: const Duration(milliseconds: 800),
                      curve: Curves.elasticOut,
                    ),

                SizedBox(height: R.sp(context, 32)),

                // App Name
                Text(
                  'Lớp Học Thông Minh',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: R.fs(context, 32),
                    fontWeight: FontWeight.bold,
                    foreground: Paint()
                      ..shader = const LinearGradient(
                        colors: [AppTheme.primary, AppTheme.secondary],
                      ).createShader(const Rect.fromLTWH(0, 0, 300, 70)),
                  ),
                ).animate(delay: 400.ms).fadeIn().slideY(begin: 0.3, duration: 600.ms),

                SizedBox(height: R.sp(context, 8)),

                Text(
                  'Hệ Thống Lớp Học IoT ESP32',
                  style: TextStyle(
                    fontSize: R.fs(context, 15),
                    color: AppTheme.textSecondary,
                    letterSpacing: 1.5,
                  ),
                ).animate(delay: 600.ms).fadeIn(),

                SizedBox(height: R.sp(context, 80)),

                // Loading bar
                SizedBox(
                  width: R.w(context) * 0.5,
                  child: LinearProgressIndicator(
                    backgroundColor: AppTheme.bgCardLight,
                    valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.primary),
                    borderRadius: BorderRadius.circular(10),
                  ),
                ).animate(delay: 800.ms).fadeIn(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
