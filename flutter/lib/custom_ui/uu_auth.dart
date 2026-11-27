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
    throw UuAuthException(translate('Account server is not configured'));
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
    throw UuAuthException(translate('The server returned incomplete data'));
  }
  await bind.mainSetLocalOption(key: 'access_token', value: token);
  await bind.mainSetLocalOption(
    key: 'user_info',
    value: jsonEncode(data['user'] ?? const <String, dynamic>{}),
  );
  await uuApplyDeviceSecret(data['device_secret']?.toString() ?? '');
  gFFI.userModel.refreshCurrentUser();
  return data;
}

/// Mirrors the account-wide device secret into this device's permanent password.
/// Every device of the account does the same, which is what lets peers of the
/// same account connect without a password prompt.
Future<void> uuApplyDeviceSecret(String secret) async {
  if (secret.isEmpty) {
    return;
  }
  if (bind.mainGetLocalOption(key: 'uu-device-secret') == secret) {
    return;
  }
  final applied =
      await bind.mainSetPermanentPasswordWithResult(password: secret);
  if (!applied) {
    return;
  }
  await bind.mainSetLocalOption(key: 'uu-device-secret', value: secret);
}

/// Fetches the account device secret for an already signed-in session and applies
/// it, so devices signed in before this feature shipped pick it up without a
/// re-login. Silent no-op when signed out or on errors.
Future<void> uuSyncDeviceSecret() async {
  final token = bind.mainGetLocalOption(key: 'access_token');
  if (token.isEmpty) {
    return;
  }
  final apiServer = await bind.mainGetApiServer();
  if (apiServer.isEmpty) {
    return;
  }
  Object deviceInfo = const <String, dynamic>{};
  try {
    deviceInfo = jsonDecode(bind.mainGetLoginDeviceInfo());
  } catch (_) {}
  Object? decoded;
  try {
    final resp = await http.post(
      Uri.parse('$apiServer/api/currentUser'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode(<String, dynamic>{
        'id': await bind.mainGetMyId(),
        'uuid': await bind.mainGetUuid(),
        'deviceInfo': deviceInfo,
      }),
    );
    if (resp.statusCode != 200) {
      return;
    }
    decoded = jsonDecode(decode_http_response(resp));
  } catch (_) {
    return;
  }
  if (decoded is! Map<String, dynamic>) {
    return;
  }
  await uuApplyDeviceSecret(decoded['device_secret']?.toString() ?? '');
}
