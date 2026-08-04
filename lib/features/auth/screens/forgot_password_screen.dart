import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/utils/responsive.dart';
import '../widgets/gradient_button.dart';
import '../widgets/custom_text_field.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _phoneFormKey = GlobalKey<FormState>();
  final _resetFormKey = GlobalKey<FormState>();

  final _phoneController = TextEditingController();
  final _otpController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _obscureNew = true;
  bool _obscureConfirm = true;
  bool _isOtpStep = false;
  bool _success = false;

  @override
  void dispose() {
    _phoneController.dispose();
    _otpController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _handleRequestOtp() async {
    if (!_phoneFormKey.currentState!.validate()) return;

    final authProvider = context.read<AuthProvider>();
    final ok = await authProvider.forgotPassword(_phoneController.text.trim());

    if (!mounted) return;

    if (ok) {
      setState(() => _isOtpStep = true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Mã OTP đã được gửi đến số điện thoại của bạn'),
          backgroundColor: AppTheme.success,
          behavior: SnackBarBehavior.floating,
          margin: EdgeInsets.only(bottom: R.bottom(context) + 16, left: 16, right: 16),
        ),
      );
    } else {
      _showError(authProvider.errorMessage ?? 'Gửi OTP thất bại');
    }
  }

  Future<void> _handleReset() async {
    if (!_resetFormKey.currentState!.validate()) return;

    final authProvider = context.read<AuthProvider>();
    final ok = await authProvider.resetPassword(
      _phoneController.text.trim(),
      _otpController.text.trim(),
      _newPasswordController.text,
    );

    if (!mounted) return;

    if (ok) {
      setState(() => _success = true);
    } else {
      _showError(authProvider.errorMessage ?? 'Đặt lại mật khẩu thất bại');
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppTheme.danger,
        behavior: SnackBarBehavior.floating,
        margin: EdgeInsets.only(bottom: R.bottom(context) + 16, left: 16, right: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hp = R.hPad(context);

    return Scaffold(
      backgroundColor: AppTheme.bgDark,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        leading: !_success
            ? IconButton(
                icon: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.bgCard,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.arrow_back_ios_rounded, size: 18),
                ),
                onPressed: () {
                  if (_isOtpStep) {
                    setState(() => _isOtpStep = false);
                  } else {
                    Navigator.pop(context);
                  }
                },
              )
            : null,
      ),
      body: SafeArea(
        bottom: true,
        child: SingleChildScrollView(
          padding: EdgeInsets.only(left: hp, right: hp, bottom: R.bottom(context) + 16),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 400),
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween<Offset>(begin: const Offset(0, 0.1), end: Offset.zero).animate(animation),
                child: child,
              ),
            ),
            child: _success
                ? _buildSuccess()
                : (_isOtpStep ? _buildResetForm() : _buildPhoneForm()),
          ),
        ),
      ),
    );
  }

  Widget _buildPhoneForm() {
    return Column(
      key: const ValueKey('phoneForm'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(height: R.sp(context, 8)),
        Container(
          width: 70,
          height: 70,
          decoration: BoxDecoration(
            color: AppTheme.warning.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Icon(Icons.lock_reset_rounded, size: 36, color: AppTheme.warning),
        ).animate().scale(duration: 600.ms, curve: Curves.elasticOut),
        SizedBox(height: R.sp(context, 24)),
        Text(
          'Quên mật khẩu',
          style: TextStyle(
            color: AppTheme.textPrimary,
            fontSize: R.fs(context, 28),
            fontWeight: FontWeight.bold,
          ),
        ).animate(delay: 100.ms).fadeIn().slideY(begin: 0.2),
        SizedBox(height: R.sp(context, 8)),
        Text(
          'Nhập số điện thoại đã đăng ký, chúng tôi sẽ gửi mã OTP để bạn đặt lại mật khẩu.',
          style: TextStyle(color: AppTheme.textSecondary, fontSize: R.fs(context, 14), height: 1.5),
        ).animate(delay: 200.ms).fadeIn(),
        SizedBox(height: R.sp(context, 36)),

        Form(
          key: _phoneFormKey,
          child: Column(
            children: [
              CustomTextField(
                controller: _phoneController,
                label: 'Số điện thoại',
                hint: '09xxxxxx',
                prefixIcon: Icons.phone_rounded,
                keyboardType: TextInputType.phone,
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Vui lòng nhập số điện thoại';
                  return null;
                },
              ).animate(delay: 300.ms).fadeIn().slideX(begin: -0.2),
              SizedBox(height: R.sp(context, 32)),

              Consumer<AuthProvider>(
                builder: (_, auth, __) => GradientButton(
                  onPressed: auth.status == AuthStatus.loading ? null : _handleRequestOtp,
                  isLoading: auth.status == AuthStatus.loading,
                  text: 'Nhận mã OTP',
                  icon: Icons.send_rounded,
                  gradient: const LinearGradient(colors: [AppTheme.warning, Color(0xFFFF8C00)]),
                ),
              ).animate(delay: 400.ms).fadeIn().slideY(begin: 0.3),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildResetForm() {
    return Column(
      key: const ValueKey('resetForm'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(height: R.sp(context, 8)),
        Text(
          'Tạo mật khẩu mới',
          style: TextStyle(
            color: AppTheme.textPrimary,
            fontSize: R.fs(context, 28),
            fontWeight: FontWeight.bold,
          ),
        ).animate().fadeIn().slideY(begin: 0.2),
        SizedBox(height: R.sp(context, 8)),
        Text(
          'Vui lòng nhập mã OTP đã được gửi đến số ${_phoneController.text}',
          style: TextStyle(color: AppTheme.textSecondary, fontSize: R.fs(context, 14), height: 1.5),
        ).animate(delay: 100.ms).fadeIn(),
        SizedBox(height: R.sp(context, 36)),

        Form(
          key: _resetFormKey,
          child: Column(
            children: [
              CustomTextField(
                controller: _otpController,
                label: 'Mã OTP (6 số)',
                hint: 'Ví dụ: 123456',
                prefixIcon: Icons.message_rounded,
                keyboardType: TextInputType.number,
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Vui lòng nhập mã OTP';
                  if (v.length != 6) return 'Mã OTP phải có 6 chữ số';
                  return null;
                },
              ).animate(delay: 200.ms).fadeIn().slideX(begin: -0.2),
              SizedBox(height: R.sp(context, 16)),

              CustomTextField(
                controller: _newPasswordController,
                label: 'Mật khẩu mới',
                hint: '••••••••',
                prefixIcon: Icons.lock_rounded,
                obscureText: _obscureNew,
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscureNew ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                    color: AppTheme.textMuted,
                  ),
                  onPressed: () => setState(() => _obscureNew = !_obscureNew),
                ),
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Vui lòng nhập mật khẩu mới';
                  if (v.length < 6) return 'Mật khẩu ít nhất 6 ký tự';
                  return null;
                },
              ).animate(delay: 300.ms).fadeIn().slideX(begin: 0.2),
              SizedBox(height: R.sp(context, 16)),

              CustomTextField(
                controller: _confirmPasswordController,
                label: 'Xác nhận mật khẩu mới',
                hint: '••••••••',
                prefixIcon: Icons.lock_outline_rounded,
                obscureText: _obscureConfirm,
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscureConfirm ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                    color: AppTheme.textMuted,
                  ),
                  onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                ),
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Vui lòng xác nhận mật khẩu';
                  if (v != _newPasswordController.text) return 'Mật khẩu không khớp';
                  return null;
                },
              ).animate(delay: 400.ms).fadeIn().slideX(begin: -0.2),
              SizedBox(height: R.sp(context, 32)),

              Consumer<AuthProvider>(
                builder: (_, auth, __) => GradientButton(
                  onPressed: auth.status == AuthStatus.loading ? null : _handleReset,
                  isLoading: auth.status == AuthStatus.loading,
                  text: 'Xác nhận',
                  icon: Icons.check_circle_rounded,
                  gradient: const LinearGradient(colors: [AppTheme.warning, Color(0xFFFF8C00)]),
                ),
              ).animate(delay: 500.ms).fadeIn().slideY(begin: 0.3),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSuccess() {
    return Center(
      key: const ValueKey('success'),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(height: R.sp(context, 60)),
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(color: AppTheme.success.withValues(alpha: 0.15), shape: BoxShape.circle),
            child: const Icon(Icons.check_circle_rounded, size: 60, color: AppTheme.success),
          ).animate().scale(duration: 800.ms, curve: Curves.elasticOut),
          SizedBox(height: R.sp(context, 32)),
          Text(
            'Thành công!',
            style: TextStyle(color: AppTheme.textPrimary, fontSize: R.fs(context, 28), fontWeight: FontWeight.bold),
          ).animate(delay: 200.ms).fadeIn(),
          SizedBox(height: R.sp(context, 12)),
          Text(
            'Mật khẩu của bạn đã được đặt lại.\nVui lòng đăng nhập bằng mật khẩu mới.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.textSecondary, fontSize: R.fs(context, 15), height: 1.6),
          ).animate(delay: 300.ms).fadeIn(),
          SizedBox(height: R.sp(context, 48)),
          GradientButton(
            onPressed: () => Navigator.pop(context),
            text: 'Quay lại đăng nhập',
            icon: Icons.login_rounded,
          ).animate(delay: 400.ms).fadeIn().slideY(begin: 0.3),
        ],
      ),
    );
  }
}
