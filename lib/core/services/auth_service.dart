import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_model.dart';

/// Auth qua tunnel Cloudflare. /api/auth trên duynguyen.io.vn vào backend
/// dùng chung MongoDB alot_db với classroom-backend.
class AuthService {
  static const _sessionTokenKey = 'auth_token';
  static const _sessionUserKey = 'user_data';

  static const String apiRoot = 'https://duynguyen.io.vn/api';

  String? _token;
  String? get token => _token;

  Future<Map<String, dynamic>> _post(String path, Map<String, dynamic> body) async {
    final response = await http
        .post(
          Uri.parse('$apiRoot$path'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 12));
    final decoded = jsonDecode(response.body);
    final map = decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
    if (response.statusCode >= 400 || map['success'] == false) {
      throw Exception(map['message']?.toString() ?? 'Yêu cầu thất bại');
    }
    return map;
  }

  Future<void> _saveSession(String token, Map<String, dynamic> userJson) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_sessionTokenKey, token);
    await prefs.setString(_sessionUserKey, jsonEncode(userJson));
    _token = token;
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_sessionTokenKey);
    await prefs.remove(_sessionUserKey);
    _token = null;
  }

  Future<UserModel?> loadSavedUser() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_sessionTokenKey);
    final userData = prefs.getString(_sessionUserKey);
    if (token != null && userData != null) {
      _token = token;
      return UserModel.fromJson(jsonDecode(userData));
    }
    return null;
  }

  Future<UserModel?> login(String email, String password) async {
    final map = await _post('/auth/login', {
      'email': email.trim(),
      'password': password,
    });
    final data = map['data'] as Map<String, dynamic>? ?? {};
    final token = data['token']?.toString() ?? '';
    final user = Map<String, dynamic>.from(data['user'] as Map? ?? {});
    if (token.isEmpty) return null;
    await _saveSession(token, user);
    return UserModel.fromJson(user);
  }

  Future<void> register({
    required String name,
    required String email,
    required String phone,
    required String password,
  }) async {
    await _post('/auth/register', {
      'name': name.trim(),
      'email': email.trim(),
      'phone': phone.trim(),
      'password': password,
    });
  }

  Future<void> checkPhoneExists(String phone) async {
    await _post('/auth/check-phone-exists', {'phone': phone.trim()});
  }

  Future<void> resetPassword({
    required String phone,
    required String newPassword,
  }) async {
    await _post('/auth/reset-password', {
      'phone': phone.trim(),
      'newPassword': newPassword,
    });
  }
}
