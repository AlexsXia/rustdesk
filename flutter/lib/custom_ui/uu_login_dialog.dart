import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart' hide Dialog;
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/models/user_model.dart';
import 'package:flutter_hbb/utils/http_service.dart' as http;

import 'theme.dart';

/// UU 风格的登录 / 注册弹窗。
///
/// 成功后写入 `access_token` 与 `user_info`，与内置登录弹窗的持久化方式一致，
/// 之后由 [UserModel.refreshCurrentUser] 拉取账号地址簿。
Future<bool?> uuLoginDialog(BuildContext context) {
  return showDialog<bool>(
    context: context,
    builder: (dialogContext) => const _UuAuthDialog(),
  );
}

/// 已登录时展示账号信息与退出入口，未登录时打开登录弹窗。
Future<void> uuAccountDialog(BuildContext context) async {
  if (!gFFI.userModel.isLogin) {
    await uuLoginDialog(context);
    return;
  }
  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      final displayName = gFFI.userModel.displayNameOrUserName;
      final userName = gFFI.userModel.userName.value;
      final initial =
          displayName.isEmpty ? '?' : displayName.substring(0, 1).toUpperCase();
      return Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 340),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 28, 28, 22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircleAvatar(
                  radius: 30,
                  backgroundColor: UuTheme.accentSoft,
                  child: Text(
                    initial,
                    style: const TextStyle(
                      color: UuTheme.accent,
                      fontSize: 24,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: UuTheme.textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '@$userName',
                  style: const TextStyle(
                    color: UuTheme.textSecondary,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 22),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () async {
                          Navigator.pop(dialogContext);
                          await UserModel.updateOtherModels();
                          showToast('设备已刷新');
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: UuTheme.textPrimary,
                          side: const BorderSide(color: UuTheme.divider),
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text('刷新设备'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        onPressed: () {
                          Navigator.pop(dialogContext);
                          unawaited(gFFI.userModel.logOut());
                        },
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFFE5484D),
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text('退出登录'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class _UuAuthDialog extends StatefulWidget {
  const _UuAuthDialog();

  @override
  State<_UuAuthDialog> createState() => _UuAuthDialogState();
}

class _UuAuthDialogState extends State<_UuAuthDialog> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _displayName = TextEditingController();
  bool _register = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    _confirm.dispose();
    _displayName.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final username = _username.text.trim();
    final password = _password.text;
    if (username.isEmpty) {
      setState(() => _error = '请输入用户名');
      return;
    }
    if (password.length < 6) {
      setState(() => _error = '密码至少需要 6 个字符');
      return;
    }
    if (_register && password != _confirm.text) {
      setState(() => _error = '两次输入的密码不一致');
      return;
    }
    final apiServer = await bind.mainGetApiServer();
    if (apiServer.isEmpty) {
      setState(() => _error = '未配置账号服务器');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
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
      if (_register) {
        body['type'] = 'account';
        body['autoLogin'] = true;
        final displayName = _displayName.text.trim();
        if (displayName.isNotEmpty) {
          body['display_name'] = displayName;
        }
      }
      final resp = await http.post(
        Uri.parse('$apiServer/api/${_register ? 'register' : 'login'}'),
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
        setState(() => _error = error?.toString() ?? 'HTTP ${resp.statusCode}');
        return;
      }
      final token = data['access_token']?.toString() ?? '';
      if (token.isEmpty) {
        setState(() => _error = '服务器返回的数据不完整');
        return;
      }
      await bind.mainSetLocalOption(key: 'access_token', value: token);
      await bind.mainSetLocalOption(
        key: 'user_info',
        value: jsonEncode(data['user'] ?? const <String, dynamic>{}),
      );
      gFFI.userModel.refreshCurrentUser();
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = '网络错误：$e');
      }
    } finally {
      if (mounted && _busy) {
        setState(() => _busy = false);
      }
    }
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool obscure = false,
    bool autofocus = false,
  }) {
    return TextField(
      controller: controller,
      autofocus: autofocus,
      obscureText: obscure,
      enabled: !_busy,
      onSubmitted: (_) {
        if (!_register) {
          unawaited(_submit());
        }
      },
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 18, color: UuTheme.textSecondary),
        isDense: true,
        filled: true,
        fillColor: const Color(0xFFF7F8FB),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: UuTheme.accent, width: 1.2),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 22, 28, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Text(
                    _register ? '创建账号' : '登录',
                    style: const TextStyle(
                      color: UuTheme.textPrimary,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: _busy ? null : () => Navigator.pop(context),
                    icon: const Icon(
                      Icons.close,
                      size: 20,
                      color: UuTheme.textSecondary,
                    ),
                  ),
                ],
              ),
              Text(
                _register ? '注册成功后，本机会自动加入账号设备列表' : '登录后即可看到并连接该账号下的所有设备',
                style: const TextStyle(
                  color: UuTheme.textSecondary,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 20),
              _field(
                controller: _username,
                label: '用户名',
                icon: Icons.person_outline,
                autofocus: true,
              ),
              const SizedBox(height: 12),
              _field(
                controller: _password,
                label: '密码',
                icon: Icons.lock_outline,
                obscure: true,
              ),
              if (_register) ...[
                const SizedBox(height: 12),
                _field(
                  controller: _confirm,
                  label: '确认密码',
                  icon: Icons.lock_outline,
                  obscure: true,
                ),
                const SizedBox(height: 12),
                _field(
                  controller: _displayName,
                  label: '昵称（可选）',
                  icon: Icons.badge_outlined,
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: const TextStyle(
                    color: Color(0xFFDC2626),
                    fontSize: 12,
                  ),
                ),
              ],
              const SizedBox(height: 20),
              SizedBox(
                height: 44,
                child: FilledButton(
                  onPressed: _busy ? null : () => unawaited(_submit()),
                  style: FilledButton.styleFrom(
                    backgroundColor: UuTheme.accent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          _register ? '注册并登录' : '登录',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: _busy
                    ? null
                    : () => setState(() {
                          _register = !_register;
                          _error = null;
                        }),
                child: Text(
                  _register ? '已有账号？去登录' : '还没有账号？立即注册',
                  style: const TextStyle(color: UuTheme.accent, fontSize: 13),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
