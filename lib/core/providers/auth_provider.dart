import 'package:flutter/foundation.dart';
import 'dart:async';
import '../models/user_model.dart';
import '../services/auth_service.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

enum AuthStatus { initial, loading, authenticated, unauthenticated, error }

class AuthProvider extends ChangeNotifier {
  AuthStatus _status = AuthStatus.initial;
  UserModel? _user;
  String? _errorMessage;
  String? _verificationId;

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

      Completer<bool> completer = Completer<bool>();
      String formattedPhone = phone;
      if (phone.startsWith('0')) {
        formattedPhone = '+84${phone.substring(1)}';
      }

      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: formattedPhone,
        verificationCompleted: (PhoneAuthCredential credential) async {},
        verificationFailed: (FirebaseAuthException e) {
          _status = AuthStatus.unauthenticated;
          _errorMessage = e.message ?? 'Lỗi gửi SMS. Vui lòng thử lại.';
          notifyListeners();
          if (!completer.isCompleted) completer.complete(false);
        },
        codeSent: (String verificationId, int? resendToken) {
          _verificationId = verificationId;
          _status = AuthStatus.unauthenticated;
          notifyListeners();
          if (!completer.isCompleted) completer.complete(true);
        },
        codeAutoRetrievalTimeout: (String verificationId) {
          _verificationId = verificationId;
        },
      );

      return await completer.future;
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
      if (_verificationId == null) throw Exception('Chưa có mã xác nhận, vui lòng thử lại');

      PhoneAuthCredential credential = PhoneAuthProvider.credential(
        verificationId: _verificationId!,
        smsCode: otp,
      );

      UserCredential userCredential = await FirebaseAuth.instance.signInWithCredential(credential);
      final idToken = await userCredential.user?.getIdToken();

      if (idToken == null) throw Exception('Không thể xác thực số điện thoại.');

      await _authService.register(name, email, phone, password, idToken);
      
      await FirebaseAuth.instance.signOut();
      _verificationId = null;

      _status = AuthStatus.unauthenticated;
      notifyListeners();
      return true;
    } catch (e) {
      if (kDebugMode) print("Lỗi: $e");
      _status = AuthStatus.unauthenticated;
      String errorStr = e.toString();
      if (e is FirebaseAuthException && e.code == 'invalid-verification-code') {
        _errorMessage = 'Mã OTP không chính xác';
      } else if (errorStr.startsWith('Exception: ')) {
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

      Completer<bool> completer = Completer<bool>();
      String formattedPhone = phone;
      if (phone.startsWith('0')) {
        formattedPhone = '+84${phone.substring(1)}';
      }

      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: formattedPhone,
        verificationCompleted: (PhoneAuthCredential credential) async {},
        verificationFailed: (FirebaseAuthException e) {
          _status = AuthStatus.unauthenticated;
          _errorMessage = e.message ?? 'Lỗi gửi SMS. Vui lòng thử lại.';
          notifyListeners();
          if (!completer.isCompleted) completer.complete(false);
        },
        codeSent: (String verificationId, int? resendToken) {
          _verificationId = verificationId;
          _status = AuthStatus.unauthenticated;
          notifyListeners();
          if (!completer.isCompleted) completer.complete(true);
        },
        codeAutoRetrievalTimeout: (String verificationId) {
          _verificationId = verificationId;
        },
      );

      return await completer.future;
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
      if (_verificationId == null) throw Exception('Chưa có mã xác nhận, vui lòng thử lại');

      PhoneAuthCredential credential = PhoneAuthProvider.credential(
        verificationId: _verificationId!,
        smsCode: otp,
      );

      UserCredential userCredential = await FirebaseAuth.instance.signInWithCredential(credential);
      final idToken = await userCredential.user?.getIdToken();

      if (idToken == null) throw Exception('Không thể xác thực số điện thoại.');

      await _authService.resetPassword(phone, idToken, newPassword);
      
      await FirebaseAuth.instance.signOut();
      _verificationId = null;

      _status = AuthStatus.unauthenticated;
      notifyListeners();
      return true;
    } catch (e) {
      if (kDebugMode) print("Lỗi: $e");
      _status = AuthStatus.unauthenticated;
      String errorStr = e.toString();
      if (e is FirebaseAuthException && e.code == 'invalid-verification-code') {
        _errorMessage = 'Mã OTP không chính xác';
      } else if (errorStr.startsWith('Exception: ')) {
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
