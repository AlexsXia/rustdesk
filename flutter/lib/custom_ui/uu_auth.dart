import 'dart:convert';

import 'package:flutter_hbb/common.dart' hide Dialog;
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/utils/http_service.dart' as http;

class UuAuthException implements Exception {
  UuAuthException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 登录或注册自建账号，成功后写入 `access_token` / `user_info` 并刷新地址簿。
Future<Map<String, dynamic>> uuAuthRequest({
  required bool register,
  required String username,
  required String password,
  String? displayName,
}) async {
  final apiServer = await bind.mainGetApiServer();
  if (apiServer.isEmpty) {
    throw UuAuthException('未配置账号服务器');
  }
  Object deviceInfo = const <String, dynamic>{};
  try {
    deviceInfo = jsonDecode(bind.mainGetLoginDeviceInfo());
  } catch (_) {}
  final body = <String, dynamic>{
    'username': username,
    'password': password,
    'id': await bind.mainGetMyId(),
    'uuid': await bind.mainGetUuid(),
    'deviceInfo': deviceInfo,
  };
  if (register) {
    body['type'] = 'account';
    body['autoLogin'] = true;
    final name = (displayName ?? '').trim();
    if (name.isNotEmpty) {
      body['display_name'] = name;
    }
  }
  final resp = await http.post(
    Uri.parse('$apiServer/api/${register ? 'register' : 'login'}'),
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode(body),
  );
  Map<String, dynamic> data = const {};
  try {
    final decoded = jsonDecode(decode_http_response(resp));
    if (decoded is Map<String, dynamic>) {
      data = decoded;
    }
  } catch (_) {}
  final error = data['error'];
  if (resp.statusCode != 200 || error != null) {
    throw UuAuthException(error?.toString() ?? 'HTTP ${resp.statusCode}');
  }
  final token = data['access_token']?.toString() ?? '';
  if (token.isEmpty) {
    throw UuAuthException('服务器返回的数据不完整');
  }
  await bind.mainSetLocalOption(key: 'access_token', value: token);
  await bind.mainSetLocalOption(
    key: 'user_info',
    value: jsonEncode(data['user'] ?? const <String, dynamic>{}),
  );
  gFFI.userModel.refreshCurrentUser();
  return data;
}
