import 'dart:convert';
import 'package:http/http.dart' as http;

const _baseUrl = 'http://localhost:8000';

class ApiService {
  final String? token;

  const ApiService({this.token});

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };

  // ─── Auth ────────────────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> signup(
      String username, String password) async {
    final res = await http.post(
      Uri.parse('$_baseUrl/api/auth/signup'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'username': username, 'password': password}),
    );
    final data = jsonDecode(res.body);
    if (res.statusCode != 200) {
      throw data['detail'] ?? 'Signup failed';
    }
    return data;
  }

  static Future<Map<String, dynamic>> login(
      String username, String password) async {
    final res = await http.post(
      Uri.parse('$_baseUrl/api/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'username': username, 'password': password}),
    );
    final data = jsonDecode(res.body);
    if (res.statusCode != 200) {
      throw data['detail'] ?? 'Login failed';
    }
    return data;
  }

  // ─── Documents ───────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> createDocument() async {
    final res = await http.post(
      Uri.parse('$_baseUrl/api/documents'),
      headers: _headers,
    );
    final data = jsonDecode(res.body);
    if (res.statusCode != 200) throw data['detail'] ?? 'Create failed';
    return data;
  }

  Future<List<Map<String, dynamic>>> listDocuments() async {
    final res = await http.get(
      Uri.parse('$_baseUrl/api/documents'),
      headers: _headers,
    );
    if (res.statusCode != 200) return [];
    final data = jsonDecode(res.body) as List;
    return data.cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>?> getDocument(String docId) async {
    final res = await http.get(
      Uri.parse('$_baseUrl/api/documents/$docId'),
      headers: _headers,
    );
    if (res.statusCode != 200) return null;
    return jsonDecode(res.body);
  }

  Future<bool> renameDocument(String docId, String title) async {
    final res = await http.patch(
      Uri.parse('$_baseUrl/api/documents/$docId/rename'),
      headers: _headers,
      body: jsonEncode({'title': title}),
    );
    return res.statusCode == 200;
  }

  Future<bool> deleteDocument(String docId) async {
    final res = await http.delete(
      Uri.parse('$_baseUrl/api/documents/$docId'),
      headers: _headers,
    );
    return res.statusCode == 200;
  }

  // ─── Users & Collaborators ──────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> searchUsers(String query) async {
    final res = await http.get(
      Uri.parse('$_baseUrl/api/users/search?q=$query'),
      headers: _headers,
    );
    if (res.statusCode != 200) return [];
    final data = jsonDecode(res.body) as List;
    return data.cast<Map<String, dynamic>>();
  }

  Future<void> addCollaborator(String docId, String username) async {
    final res = await http.post(
      Uri.parse('$_baseUrl/api/documents/$docId/collaborators'),
      headers: _headers,
      body: jsonEncode({'username': username}),
    );
    if (res.statusCode != 200) {
      final data = jsonDecode(res.body);
      throw data['detail'] ?? 'Failed to add collaborator';
    }
  }

  Future<bool> removeCollaborator(String docId, String username) async {
    final res = await http.delete(
      Uri.parse('$_baseUrl/api/documents/$docId/collaborators/$username'),
      headers: _headers,
    );
    return res.statusCode == 200;
  }

  Future<Map<String, dynamic>> listCollaborators(String docId) async {
    final res = await http.get(
      Uri.parse('$_baseUrl/api/documents/$docId/collaborators'),
      headers: _headers,
    );
    if (res.statusCode != 200) throw 'Failed to list collaborators';
    return jsonDecode(res.body);
  }
}
