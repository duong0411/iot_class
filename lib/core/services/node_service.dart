import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/node_model.dart';

class NodeService {
  static const String baseUrl = 'https://adam.podcast.io.vn/api';

  Future<String?> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('auth_token');
  }

  Future<List<NodeModel>> getNodes() async {
    final token = await _getToken();
    if (token == null) return [];

    try {
      final response = await http.get(
        Uri.parse('$baseUrl/nodes'),
        headers: {'Authorization': 'Bearer $token'},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          final List nodesData = data['data']['nodes'];
          return nodesData.map((e) => NodeModel.fromJson(e)).toList();
        }
      }
    } catch (e) {
      print('Lỗi fetch nodes: $e');
    }
    return [];
  }

  Future<NodeModel?> createNode(String name, String chipId, String templateType) async {
    final token = await _getToken();
    if (token == null) return null;

    try {
      final response = await http.post(
        Uri.parse('$baseUrl/nodes'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'name': name,
          'chipId': chipId,
          'templateType': templateType,
          'state': {},
        }),
      ).timeout(const Duration(seconds: 10));

      final data = jsonDecode(response.body);
      if (response.statusCode == 201 && data['success'] == true) {
        return NodeModel.fromJson(data['data']['node']);
      } else {
        throw Exception(data['message'] ?? 'Thêm thiết bị thất bại');
      }
    } catch (e) {
      print('Lỗi create node: $e');
      rethrow;
    }
  }

  Future<bool> deleteNode(String id) async {
    final token = await _getToken();
    if (token == null) return false;

    try {
      final response = await http.delete(
        Uri.parse('$baseUrl/nodes/$id'),
        headers: {'Authorization': 'Bearer $token'},
      ).timeout(const Duration(seconds: 10));

      return response.statusCode == 200;
    } catch (e) {
      print('Lỗi delete node: $e');
      return false;
    }
  }

  Future<bool> updateNodeState(String id, Map<String, dynamic> state) async {
    final token = await _getToken();
    if (token == null) return false;

    try {
      final response = await http.put(
        Uri.parse('$baseUrl/nodes/$id'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'state': state}),
      ).timeout(const Duration(seconds: 10));

      return response.statusCode == 200;
    } catch (e) {
      print('Lỗi update node state: $e');
      return false;
    }
  }
}
