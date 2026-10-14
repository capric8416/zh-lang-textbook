import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AccountApiException implements Exception {
  const AccountApiException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;
  @override
  String toString() => message;
}

class AccountApi {
  AccountApi({HttpClient? client, FlutterSecureStorage? storage})
    : _client = client ?? HttpClient(),
      _storage = storage ?? const FlutterSecureStorage();

  static const apiBaseUrl = String.fromEnvironment('API_BASE_URL');
  static const _tokenKey = 'account_session_token';
  static const _accountIdKey = 'account_session_account_id';
  static const passwordIterations = 600000;
  final HttpClient _client;
  final FlutterSecureStorage _storage;

  bool get configured => apiBaseUrl.trim().isNotEmpty;
  Future<String?> get token => _storage.read(key: _tokenKey);
  Future<String?> get accountId => _storage.read(key: _accountIdKey);

  Future<void> rememberAccountId(String id) =>
      _storage.write(key: _accountIdKey, value: id);

  Future<Map<String, dynamic>> request(
    String path, {
    String method = 'GET',
    Map<String, Object?>? body,
    Map<String, String>? queryParameters,
    bool authenticated = true,
    String? tokenOverride,
  }) async {
    if (!configured) {
      throw const AccountApiException(
        '账号服务尚未配置，请使用 --dart-define=API_BASE_URL=https://你的 Worker 地址/api/v1',
      );
    }
    final base = Uri.tryParse(apiBaseUrl);
    if (base == null || !base.hasScheme || base.host.isEmpty) {
      throw const AccountApiException('API_BASE_URL 格式无效');
    }
    final url = base.replace(
      path: '${base.path.replaceFirst(RegExp(r'/$'), '')}/$path',
      queryParameters: queryParameters,
    );
    final request = await _client.openUrl(method, url);
    request.headers.contentType = ContentType.json;
    if (authenticated) {
      final value = tokenOverride ?? await token;
      if (value != null) {
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $value');
      }
    }
    if (body != null) request.write(jsonEncode(body));
    final response = await request.close();
    final text = await response.transform(utf8.decoder).join();
    Map<String, dynamic> decoded = <String, dynamic>{};
    if (text.isNotEmpty) {
      try {
        decoded = jsonDecode(text) as Map<String, dynamic>;
      } on FormatException {
        decoded = <String, dynamic>{};
      }
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      if (response.statusCode == 401) {
        await _storage.delete(key: _tokenKey);
        await _storage.delete(key: _accountIdKey);
      }
      throw AccountApiException(
        decoded['error'] as String? ?? '请求失败（${response.statusCode}）',
        statusCode: response.statusCode,
      );
    }
    return decoded;
  }

  Future<Map<String, dynamic>> login(String username, String password) async {
    final parameters = await passwordParameters(username);
    final verifier = await deriveVerifier(
      password,
      parameters['salt'] as String,
      parameters['iterations'] as int,
    );
    final result = await request(
      'auth/login',
      method: 'POST',
      authenticated: false,
      body: {
        'username': username,
        'salt': parameters['salt'],
        'iterations': parameters['iterations'],
        'verifier': verifier,
      },
    );
    final session = result['token'];
    if (session is String) await _storage.write(key: _tokenKey, value: session);
    final account = result['account'];
    if (account is Map && account['id'] is String) {
      await rememberAccountId(account['id'] as String);
    }
    return result;
  }

  Future<Map<String, dynamic>> passwordParameters(String username) => request(
    'auth/parameters',
    method: 'POST',
    authenticated: false,
    body: {'username': username},
  );

  static Future<Map<String, Object>> newPasswordProof(String password) async {
    final random = Random.secure();
    final saltBytes = List<int>.generate(16, (_) => random.nextInt(256));
    final salt = base64Encode(saltBytes);
    return {
      'salt': salt,
      'iterations': passwordIterations,
      'verifier': await deriveVerifier(password, salt, passwordIterations),
    };
  }

  static Future<String> deriveVerifier(
    String password,
    String salt,
    int iterations,
  ) async {
    final algorithm = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: iterations,
      bits: 256,
    );
    final key = await algorithm.deriveKey(
      secretKey: SecretKey(utf8.encode(password)),
      nonce: base64Decode(salt),
    );
    return base64Encode(await key.extractBytes());
  }

  Future<void> logout() async {
    try {
      await request('auth/logout', method: 'POST');
    } finally {
      await _storage.delete(key: _tokenKey);
      await _storage.delete(key: _accountIdKey);
    }
  }

  Future<void> clearToken() async {
    await _storage.delete(key: _tokenKey);
    await _storage.delete(key: _accountIdKey);
  }
}
