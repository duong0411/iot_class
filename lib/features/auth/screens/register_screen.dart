import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/utils/responsive.dart';
import '../widgets/gradient_button.dart';
import '../widgets/custom_text_field.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _otpFormKey = GlobalKey<FormState>();

  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _otpController = TextEditingController();

  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _isOtpStep = false;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  Future<void> _handleRequestOtp() async {
    if (!_formKey.currentState!.validate()) return;

    final authProvider = context.read<AuthProvider>();
    final success = await authProvider.requestRegisterOtp(
      _nameController.text.trim(),
      _emailController.text.trim(),
      _phoneController.text.trim(),
      _passwordController.text,
    );

    if (!mounted) return;

    if (success) {
      setState(() {
        _isOtpStep = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Mã OTP đã được gửi đến số điện thoại của bạn'),
          backgroundColor: AppTheme.success,
          behavior: SnackBarBehavior.floating,
          margin: EdgeInsets.only(bottom: R.bottom(context) + 16, left: 16, right: 16),
        ),
      );
    } else {
      _showError(authProvider.errorMessage ?? 'Yêu cầu OTP thất bại');
    }
  }

  Future<void> _handleRegister() async {
    if (!_otpFormKey.currentState!.validate()) return;

    final authProvider = context.read<AuthProvider>();
    final success = await authProvider.register(
      _nameController.text.trim(),
      _emailController.text.trim(),
      _phoneController.text.trim(),
      _passwordController.text,
      _otpController.text.trim(),
    );

    if (!mounted) return;

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Đăng ký thành công! Vui lòng đăng nhập.'),
          backgroundColor: AppTheme.success,
          behavior: SnackBarBehavior.floating,
          margin: EdgeInsets.only(bottom: R.bottom(context) + 16, left: 16, right: 16),
        ),
      );
      Navigator.of(context).pop();
    } else {
      _showError(authProvider.errorMessage ?? 'Đăng ký thất bại');
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppTheme.danger,
        behavior: SnackBarBehavior.floating,
        margin: EdgeInsets.only(bottom: R.bottom(context) + 16, left: 16, right: 16),
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
        leading: IconButton(
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
        ),
      ),
      body: SafeArea(
        bottom: true,
        child: SingleChildScrollView(
          padding: EdgeInsets.only(left: hp, right: hp, bottom: R.bottom(context) + 16),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: _isOtpStep ? _buildOtpForm() : _buildRegisterForm(),
          ),
        ),
      ),
    );
  }

  Widget _buildRegisterForm() {
    return Column(
      key: const ValueKey('register'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(height: R.sp(context, 8)),
        Text(
          'Tạo tài khoản',
          style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                color: AppTheme.textPrimary,
                fontSize: R.fs(context, 28),
              ),
        ).animate().fadeIn().slideY(begin: 0.2),
        SizedBox(height: R.sp(context, 32)),

        Form(
          key: _formKey,
          child: Column(
            children: [
              CustomTextField(
                controller: _nameController,
                label: 'Họ và tên',
                hint: 'Nguyễn Văn A',
                prefixIcon: Icons.person_rounded,
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Vui lòng nhập tên';
                  if (v.length < 2) return 'Tên ít nhất 2 ký tự';
                  return null;
                },
              ).animate(delay: 200.ms).fadeIn().slideX(begin: -0.2),
              SizedBox(height: R.sp(context, 16)),

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
              ).animate(delay: 300.ms).fadeIn().slideX(begin: 0.2),
              SizedBox(height: R.sp(context, 16)),

              CustomTextField(
                controller: _phoneController,
                label: 'Số điện thoại',
                hint: '09xxxxxx',
                prefixIcon: Icons.phone_rounded,
                keyboardType: TextInputType.phone,
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Vui lòng nhập số điện thoại';
                  final regex = RegExp(r'^(0[3|5|7|8|9])+([0-9]{8})$');
                  if (!regex.hasMatch(v)) return 'Số điện thoại không hợp lệ';
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
                    _obscurePassword ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                    color: AppTheme.textMuted,
                  ),
                  onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                ),
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Vui lòng nhập mật khẩu';
                  if (v.length < 6) return 'Mật khẩu ít nhất 6 ký tự';
                  return null;
                },
              ).animate(delay: 500.ms).fadeIn().slideX(begin: 0.2),
              SizedBox(height: R.sp(context, 16)),

              CustomTextField(
                controller: _confirmPasswordController,
                label: 'Xác nhận mật khẩu',
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
                  if (v != _passwordController.text) return 'Mật khẩu không khớp';
                  return null;
                },
              ).animate(delay: 600.ms).fadeIn().slideX(begin: -0.2),
              SizedBox(height: R.sp(context, 28)),

              Consumer<AuthProvider>(
                builder: (_, auth, __) => GradientButton(
                  onPressed: auth.status == AuthStatus.loading ? null : _handleRequestOtp,
                  isLoading: auth.status == AuthStatus.loading,
                  text: 'Tiếp tục',
                  icon: Icons.arrow_forward_rounded,
                  gradient: const LinearGradient(colors: [AppTheme.secondary, AppTheme.primary]),
                ),
              ).animate(delay: 700.ms).fadeIn().slideY(begin: 0.3),
            ],
          ),
        ),
        SizedBox(height: R.sp(context, 32)),
      ],
    );
  }

  Widget _buildOtpForm() {
    return Column(
      key: const ValueKey('otp'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(height: R.sp(context, 8)),
        Text(
          'Xác thực OTP',
          style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                color: AppTheme.textPrimary,
                fontSize: R.fs(context, 28),
              ),
        ).animate().fadeIn().slideY(begin: 0.2),
        SizedBox(height: R.sp(context, 8)),
        Text(
          'Mã OTP đã được gửi đến số điện thoại ${_phoneController.text}',
          style: TextStyle(
            color: AppTheme.textSecondary,
            fontSize: R.fs(context, 14),
            height: 1.5,
          ),
        ).animate(delay: 100.ms).fadeIn(),
        SizedBox(height: R.sp(context, 32)),

        Form(
          key: _otpFormKey,
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
              ).animate(delay: 200.ms).fadeIn().slideX(begin: 0.2),
              SizedBox(height: R.sp(context, 28)),

              Consumer<AuthProvider>(
                builder: (_, auth, __) => GradientButton(
                  onPressed: auth.status == AuthStatus.loading ? null : _handleRegister,
                  isLoading: auth.status == AuthStatus.loading,
                  text: 'Đăng Ký',
                  icon: Icons.person_add_rounded,
                  gradient: const LinearGradient(colors: [AppTheme.secondary, AppTheme.primary]),
                ),
              ).animate(delay: 300.ms).fadeIn().slideY(begin: 0.3),
            ],
          ),
        ),
      ],
    );
  }
}
