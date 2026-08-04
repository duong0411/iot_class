import 'package:flutter/foundation.dart';
import '../models/user_model.dart';
import '../services/auth_service.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

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
      if (kDebugMode) print("Lỗi load user: $e");
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
      } else {
        _status = AuthStatus.unauthenticated;
        _errorMessage = 'Tài khoản hoặc mật khẩu không đúng';
        notifyListeners();
        return false;
      }
    } catch (e) {
      _status = AuthStatus.unauthenticated;
      _errorMessage = 'Không thể kết nối server. Vui lòng kiểm tra lại đường truyền Internet!';
      notifyListeners();
      return false;
    }
  }

  Future<bool> loginWithGoogle() async {
    _status = AuthStatus.loading;
    _errorMessage = null;
    notifyListeners();

    try {
      final GoogleSignIn googleSignIn = GoogleSignIn(
        serverClientId: dotenv.env['GOOGLE_WEB_CLIENT_ID'],
      );

      GoogleSignInAccount? googleUser;
      try {
        googleUser = await googleSignIn.signIn();
      } catch (e) {
        if (kDebugMode) print("Lỗi GoogleSignIn: $e");
        _status = AuthStatus.unauthenticated;
        _errorMessage = 'Đã hủy đăng nhập hoặc lỗi kết nối.';
        notifyListeners();
        return false;
      }

      if (googleUser == null) {
        _status = AuthStatus.unauthenticated;
        notifyListeners();
        return false;
      }

      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      final String? idToken = googleAuth.idToken;

      if (idToken == null) {
        throw Exception('Không thể lấy ID Token từ Google');
      }

      final user = await _authService.googleLogin(idToken);
      if (user != null) {
        _user = user;
        _status = AuthStatus.authenticated;
        notifyListeners();
        return true;
      } else {
        _status = AuthStatus.unauthenticated;
        _errorMessage = 'Đăng nhập Google thất bại';
        notifyListeners();
        return false;
      }
    } catch (e) {
      if (kDebugMode) print("Lỗi Google Sign In: $e");
      _status = AuthStatus.unauthenticated;
      _errorMessage = 'Đăng nhập Google thất bại. Vui lòng thử lại!';
      notifyListeners();
      return false;
    }
  }

  Future<bool> requestRegisterOtp(String name, String email, String phone, String password) async {
    _status = AuthStatus.loading;
    _errorMessage = null;
    notifyListeners();

    try {
      await _authService.requestRegisterOtp(name, email, phone, password);
      _status = AuthStatus.unauthenticated;
      notifyListeners();
      return true;
    } catch (e) {
      if (kDebugMode) print("Lỗi: $e");
      _status = AuthStatus.unauthenticated;
      final errorStr = e.toString();
      _errorMessage = errorStr.startsWith('Exception: ')
          ? errorStr.replaceAll('Exception: ', '')
          : 'Lỗi kết nối. Vui lòng kiểm tra mạng và thử lại!';
      notifyListeners();
      return false;
    }
  }

  Future<bool> register(String name, String email, String phone, String password, String otp) async {
    _status = AuthStatus.loading;
    _errorMessage = null;
    notifyListeners();

    try {
      // OTP UI giữ lại cho flow cũ; không còn xác thực Firebase Phone Auth
      await _authService.register(name, email, phone, password, otp);

      _status = AuthStatus.unauthenticated;
      notifyListeners();
      return true;
    } catch (e) {
      if (kDebugMode) print("Lỗi: $e");
      _status = AuthStatus.unauthenticated;
      String errorStr = e.toString();
      if (errorStr.startsWith('Exception: ')) {
        _errorMessage = errorStr.replaceAll('Exception: ', '');
      } else {
        _errorMessage = 'Lỗi kết nối. Vui lòng kiểm tra mạng và thử lại!';
      }
      notifyListeners();
      return false;
    }
  }

  Future<bool> forgotPassword(String phone) async {
    _status = AuthStatus.loading;
    _errorMessage = null;
    notifyListeners();

    try {
      await _authService.forgotPassword(phone);
      _status = AuthStatus.unauthenticated;
      notifyListeners();
      return true;
    } catch (e) {
      if (kDebugMode) print("Lỗi: $e");
      _status = AuthStatus.unauthenticated;
      final errorStr = e.toString();
      _errorMessage = errorStr.startsWith('Exception: ')
          ? errorStr.replaceAll('Exception: ', '')
          : 'Lỗi kết nối. Vui lòng kiểm tra mạng và thử lại!';
      notifyListeners();
      return false;
    }
  }

  Future<bool> resetPassword(String phone, String otp, String newPassword) async {
    _status = AuthStatus.loading;
    _errorMessage = null;
    notifyListeners();

    try {
      await _authService.resetPassword(phone, otp, newPassword);

      _status = AuthStatus.unauthenticated;
      notifyListeners();
      return true;
    } catch (e) {
      if (kDebugMode) print("Lỗi: $e");
      _status = AuthStatus.unauthenticated;
      String errorStr = e.toString();
      if (errorStr.startsWith('Exception: ')) {
        _errorMessage = errorStr.replaceAll('Exception: ', '');
      } else {
        _errorMessage = 'Lỗi kết nối. Vui lòng kiểm tra mạng và thử lại!';
      }
      notifyListeners();
      return false;
    }
  }

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }
}
