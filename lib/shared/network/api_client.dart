import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_config.dart';
import 'session_store.dart';

class ApiException implements Exception {
  ApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class ApiClient {
  ApiClient(this._sessionStore, [http.Client? client])
      : _client = client ?? http.Client();

  static const Duration _requestTimeout = Duration(seconds: 12);

  final SessionStore _sessionStore;
  final http.Client _client;

  Future<dynamic> get(
    String path, {
    Map<String, String>? query,
    bool authRequired = true,
  }) {
    return _request(
      method: 'GET',
      path: path,
      query: query,
      authRequired: authRequired,
    );
  }

  Future<dynamic> post(
    String path, {
    Map<String, dynamic>? body,
    bool authRequired = true,
  }) {
    return _request(
      method: 'POST',
      path: path,
      body: body,
      authRequired: authRequired,
    );
  }

  Future<dynamic> put(
    String path, {
    Map<String, dynamic>? body,
    bool authRequired = true,
  }) {
    return _request(
      method: 'PUT',
      path: path,
      body: body,
      authRequired: authRequired,
    );
  }

  Future<dynamic> delete(
    String path, {
    Map<String, dynamic>? body,
    bool authRequired = true,
  }) {
    return _request(
      method: 'DELETE',
      path: path,
      body: body,
      authRequired: authRequired,
    );
  }

  Future<dynamic> _request({
    required String method,
    required String path,
    Map<String, String>? query,
    Map<String, dynamic>? body,
    required bool authRequired,
  }) async {
    await _sessionStore.ensureInitialized();

    final uri =
        Uri.parse('${ApiConfig.baseUrl}$path').replace(queryParameters: query);
    final headers = <String, String>{
      'Content-Type': 'application/json',
    };

    if (authRequired) {
      final token = _sessionStore.token;
      if (token == null || token.isEmpty) {
        throw ApiException('Sessiya muddati tugagan. Qaytadan login qiling.',
            statusCode: 401);
      }
      headers['Authorization'] = 'Bearer $token';
    }

    late http.Response response;

    try {
      if (method == 'GET') {
        response =
            await _client.get(uri, headers: headers).timeout(_requestTimeout);
      } else if (method == 'POST') {
        response = await _client
            .post(uri, headers: headers, body: jsonEncode(body ?? const {}))
            .timeout(_requestTimeout);
      } else if (method == 'PUT') {
        response = await _client
            .put(uri, headers: headers, body: jsonEncode(body ?? const {}))
            .timeout(_requestTimeout);
      } else if (method == 'DELETE') {
        response = await _client
            .delete(uri, headers: headers, body: jsonEncode(body ?? const {}))
            .timeout(_requestTimeout);
      } else {
        throw ApiException('Qollab-quvvatlanmagan HTTP method: $method');
      }
    } on TimeoutException {
      throw ApiException(
        "Server javobi kechikdi. Internet yoki backend holatini tekshiring.",
      );
    } catch (_) {
      throw ApiException(
          "Backend serverga ulanib bo'lmadi. Server yoqilganini tekshiring.");
    }

    dynamic decoded;
    if (response.body.trim().isNotEmpty) {
      try {
        decoded = jsonDecode(response.body);
      } catch (_) {
        decoded = response.body;
      }
    }

    if (response.statusCode >= 400) {
      final message = _readErrorMessage(decoded) ??
          'Server xatoligi: ${response.statusCode}';
      throw ApiException(message, statusCode: response.statusCode);
    }

    return decoded;
  }

  String? _readErrorMessage(dynamic decoded) {
    if (decoded is Map<String, dynamic>) {
      final top = decoded['message'];
      if (top is String && top.isNotEmpty) return top;

      final error = decoded['error'];
      if (error is Map<String, dynamic>) {
        final nested = error['message'];
        if (nested is String && nested.isNotEmpty) return nested;
      }
    }

    if (decoded is String && decoded.isNotEmpty) return decoded;
    return null;
  }
}
