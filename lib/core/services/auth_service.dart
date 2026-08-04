import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_model.dart';

class AuthService {
  static const String baseUrl = 'https://adam.podcast.io.vn/api';

  String? _token;
  String? get token => _token;

  // ─── Lấy SharedPreferences ──────────────────────────────────────────────────
  Future<void> _saveUserData(String token, Map<String, dynamic> userJson) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('auth_token', token);
    await prefs.setString('user_data', jsonEncode(userJson));
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('auth_token');
    await prefs.remove('user_data');
    _token = null;
  }

  Future<UserModel?> loadSavedUser() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');
    final userData = prefs.getString('user_data');
    if (token != null && userData != null) {
      _token = token;
      return UserModel.fromJson(jsonDecode(userData));
    }
    return null;
  }

  // ─── Login ────────────────────────────────────────────────────────────────
  Future<UserModel?> login(String email, String password) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email, 'password': password}),
    ).timeout(const Duration(seconds: 10));

    final data = jsonDecode(response.body);
    if (response.statusCode == 200 && data['success'] == true) {
      _token = data['data']['token'];
      final user = UserModel.fromJson(data['data']['user']);
      await _saveUserData(_token!, data['data']['user']);
      return user;
    }
    return null;
  }

  // ─── Google Login ─────────────────────────────────────────────────────────
  Future<UserModel?> googleLogin(String idToken) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/google-login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'idToken': idToken}),
    ).timeout(const Duration(seconds: 10));

    final data = jsonDecode(response.body);
    if (response.statusCode == 200 && data['success'] == true) {
      _token = data['data']['token'];
      final user = UserModel.fromJson(data['data']['user']);
      await _saveUserData(_token!, data['data']['user']);
      return user;
    }
    throw Exception(data['message'] ?? 'Đăng nhập Google thất bại');
  }

  // ─── Register ─────────────────────────────────────────────────────────────
  Future<void> requestRegisterOtp(String name, String email, String phone, String password) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/check-pre-register'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email, 'phone': phone}),
    ).timeout(const Duration(seconds: 10));
    final data = jsonDecode(response.body);
    if (response.statusCode != 200) throw Exception(data['message'] ?? 'Thông tin không hợp lệ');
  }

  Future<void> register(String name, String email, String phone, String password, String idToken) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/register'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'name': name, 'email': email, 'phone': phone, 'password': password, 'firebaseIdToken': idToken}),
    ).timeout(const Duration(seconds: 10));
    final data = jsonDecode(response.body);
    if (response.statusCode != 201) throw Exception(data['message'] ?? 'Đăng ký thất bại');
  }

  // ─── Forgot Password ──────────────────────────────────────────────────────
  Future<void> forgotPassword(String phone) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/check-phone-exists'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'phone': phone}),
    ).timeout(const Duration(seconds: 10));
    final data = jsonDecode(response.body);
    if (response.statusCode != 200) throw Exception(data['message'] ?? 'Số điện thoại không tồn tại');
  }

  Future<void> resetPassword(String phone, String idToken, String newPassword) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/reset-password'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'phone': phone, 'firebaseIdToken': idToken, 'newPassword': newPassword}),
    ).timeout(const Duration(seconds: 10));
    final data = jsonDecode(response.body);
    if (response.statusCode != 200) throw Exception(data['message'] ?? 'Đặt lại mật khẩu thất bại');
  }
}
