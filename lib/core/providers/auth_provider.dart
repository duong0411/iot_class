import 'package:flutter/foundation.dart';
import '../models/user_model.dart';
import '../services/auth_service.dart';

enum AuthStatus { initial, loading, authenticated, unauthenticated, error }

class AuthProvider extends ChangeNotifier {
  AuthStatus _status = AuthStatus.initial;
  UserModel? _user;
  String? _errorMessage;

  AuthStatus get status => _status;
  UserModel? get user => _user;
  String? get errorMessage => _errorMessage;
  bool get isAuthenticated => _status == AuthStatus.authenticated;

  final AuthService _authService = AuthService();

  Future<bool> checkAuthStatus() async {
    _status = AuthStatus.loading;
    notifyListeners();

    try {
      final savedUser = await _authService.loadSavedUser();
      if (savedUser != null) {
        _user = savedUser;
        _status = AuthStatus.authenticated;
        notifyListeners();
        return true;
      }
    } catch (e) {
      if (kDebugMode) print('Lỗi load user: $e');
    }

    _status = AuthStatus.unauthenticated;
    notifyListeners();
    return false;
  }

  Future<void> logout() async {
    await _authService.logout();
    _user = null;
    _status = AuthStatus.unauthenticated;
    notifyListeners();
  }

  Future<bool> login(String email, String password) async {
    _status = AuthStatus.loading;
    _errorMessage = null;
    notifyListeners();

    try {
      final user = await _authService.login(email, password);
      if (user != null) {
        _user = user;
        _status = AuthStatus.authenticated;
        notifyListeners();
        return true;
      }
      _status = AuthStatus.unauthenticated;
      _errorMessage = 'Tài khoản hoặc mật khẩu không đúng';
      notifyListeners();
      return false;
    } catch (e) {
      _status = AuthStatus.unauthenticated;
      _errorMessage = 'Đăng nhập thất bại. Vui lòng thử lại!';
      notifyListeners();
      return false;
    }
  }

  Future<bool> register(String name, String email, String phone, String password) async {
    _status = AuthStatus.loading;
    _errorMessage = null;
    notifyListeners();

    try {
      await _authService.register(
        name: name,
        email: email,
        phone: phone,
        password: password,
      );
      _status = AuthStatus.unauthenticated;
      notifyListeners();
      return true;
    } catch (e) {
      if (kDebugMode) print('Lỗi đăng ký: $e');
      _status = AuthStatus.unauthenticated;
      final errorStr = e.toString();
      _errorMessage = errorStr.startsWith('Exception: ')
          ? errorStr.replaceAll('Exception: ', '')
          : 'Đăng ký thất bại. Vui lòng thử lại!';
      notifyListeners();
      return false;
    }
  }

  Future<bool> forgotPassword(String phone) async {
    _status = AuthStatus.loading;
    _errorMessage = null;
    notifyListeners();

    try {
      await _authService.checkPhoneExists(phone);
      _status = AuthStatus.unauthenticated;
      notifyListeners();
      return true;
    } catch (e) {
      _status = AuthStatus.unauthenticated;
      final errorStr = e.toString();
      _errorMessage = errorStr.startsWith('Exception: ')
          ? errorStr.replaceAll('Exception: ', '')
          : 'Không tìm thấy số điện thoại';
      notifyListeners();
      return false;
    }
  }

  Future<bool> resetPassword(String phone, String newPassword) async {
    _status = AuthStatus.loading;
    _errorMessage = null;
    notifyListeners();

    try {
      await _authService.resetPassword(phone: phone, newPassword: newPassword);
      _status = AuthStatus.unauthenticated;
      notifyListeners();
      return true;
    } catch (e) {
      _status = AuthStatus.unauthenticated;
      final errorStr = e.toString();
      _errorMessage = errorStr.startsWith('Exception: ')
          ? errorStr.replaceAll('Exception: ', '')
          : 'Đặt lại mật khẩu thất bại';
      notifyListeners();
      return false;
    }
  }

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }
}
