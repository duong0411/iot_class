import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_model.dart';

/// Local-only auth — users stored on device via SharedPreferences.
class AuthService {
  static const _usersKey = 'local_users';
  static const _sessionTokenKey = 'auth_token';
  static const _sessionUserKey = 'user_data';

  String? _token;
  String? get token => _token;

  Future<List<Map<String, dynamic>>> _loadUsers() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_usersKey);
    if (raw == null || raw.isEmpty) return [];
    final list = jsonDecode(raw) as List<dynamic>;
    return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<void> _saveUsers(List<Map<String, dynamic>> users) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_usersKey, jsonEncode(users));
  }

  Future<void> _saveSession(String token, Map<String, dynamic> userJson) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_sessionTokenKey, token);
    await prefs.setString(_sessionUserKey, jsonEncode(userJson));
    _token = token;
  }

  Map<String, dynamic> _publicUser(Map<String, dynamic> stored) {
    return {
      'id': stored['id'],
      'name': stored['name'],
      'email': stored['email'],
      'phone': stored['phone'] ?? '',
      'avatar': stored['avatar'],
      'createdAt': stored['createdAt'],
    };
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
    final users = await _loadUsers();
    final emailNorm = email.trim().toLowerCase();

    Map<String, dynamic>? match;
    for (final u in users) {
      if ((u['email'] as String).toLowerCase() == emailNorm &&
          u['password'] == password) {
        match = u;
        break;
      }
    }

    if (match == null) return null;

    final public = _publicUser(match);
    final token = 'local_${match['id']}';
    await _saveSession(token, public);
    return UserModel.fromJson(public);
  }

  Future<void> register({
    required String name,
    required String email,
    required String phone,
    required String password,
  }) async {
    final users = await _loadUsers();
    final emailNorm = email.trim().toLowerCase();
    final phoneNorm = phone.trim();

    if (users.any((u) => (u['email'] as String).toLowerCase() == emailNorm)) {
      throw Exception('Email đã được sử dụng');
    }
    if (users.any((u) => (u['phone'] as String) == phoneNorm)) {
      throw Exception('Số điện thoại đã được sử dụng');
    }

    final now = DateTime.now();
    final user = {
      'id': now.millisecondsSinceEpoch.toString(),
      'name': name.trim(),
      'email': emailNorm,
      'phone': phoneNorm,
      'password': password,
      'avatar': null,
      'createdAt': now.toIso8601String(),
    };
    users.add(user);
    await _saveUsers(users);
  }

  Future<void> checkPhoneExists(String phone) async {
    final users = await _loadUsers();
    final phoneNorm = phone.trim();
    final exists = users.any((u) => (u['phone'] as String) == phoneNorm);
    if (!exists) {
      throw Exception('Số điện thoại không tồn tại');
    }
  }

  Future<void> resetPassword({
    required String phone,
    required String newPassword,
  }) async {
    final users = await _loadUsers();
    final phoneNorm = phone.trim();
    final index = users.indexWhere((u) => (u['phone'] as String) == phoneNorm);
    if (index < 0) {
      throw Exception('Không tìm thấy tài khoản');
    }
    users[index]['password'] = newPassword;
    await _saveUsers(users);
  }
}
