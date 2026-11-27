import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart' hide Dialog;

import 'design/uu_tokens.dart';
import 'theme.dart';
import 'uu_auth.dart';
import 'widgets/uu_account.dart';
import 'widgets/uu_feedback.dart';

/// UU 风格的登录 / 注册弹窗。
///
/// 成功后写入 `access_token` 与 `user_info`，与内置登录弹窗的持久化方式一致，
/// 之后由账号模型拉取账号地址簿。
Future<bool?> uuLoginDialog(BuildContext context) {
  return showDialog<bool>(
    context: context,
    builder: (dialogContext) => const _UuAuthDialog(),
  );
}

/// 已登录时展示账号信息与退出入口，未登录时打开登录弹窗。
Future<void> uuAccountDialog(BuildContext context) async {
  if (!gFFI.userModel.isLogin) {
    final ok = await uuLoginDialog(context);
    if (ok == true) {
      uuToast(translate('Signed in'));
    }
    return;
  }
  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      UuColors.apply(dialogContext);
      final displayName = gFFI.userModel.displayNameOrUserName;
      final userName = gFFI.userModel.userName.value;
      final initial =
          displayName.isEmpty ? '?' : displayName.substring(0, 1).toUpperCase();
      return Dialog(
        backgroundColor: UuColors.surface,
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
                  style: TextStyle(
                    color: UuTheme.textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '@$userName',
                  style: TextStyle(
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
                          await uuRefreshDevices();
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: UuTheme.textPrimary,
                          side: BorderSide(color: UuTheme.divider),
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(translate('Refresh devices')),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        onPressed: () async {
                          Navigator.pop(dialogContext);
                          if (!await uuConfirmLogout(context)) {
                            return;
                          }
                          await gFFI.userModel.logOut();
                        },
                        style: FilledButton.styleFrom(
                          backgroundColor: UuColors.danger,
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(translate('Sign out')),
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
      setState(() => _error = translate('Please enter a username'));
      return;
    }
    if (password.length < 6) {
      setState(() => _error = translate('Password must be at least 6 characters'));
      return;
    }
    if (_register && password != _confirm.text) {
      setState(() => _error = translate('Passwords do not match'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await uuAuthRequest(
        register: _register,
        username: username,
        password: password,
        displayName: _register ? _displayName.text : null,
      );
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } on UuAuthException catch (e) {
      if (mounted) {
        setState(() => _error = e.message);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = translate('Network error: {$e}'));
      }
    } finally {
      if (mounted) {
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
        fillColor: UuColors.background,
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
    UuColors.apply(context);
    return Dialog(
      backgroundColor: UuColors.surface,
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
                    _register ? translate('Create account') : translate('Login'),
                    style: TextStyle(
                      color: UuTheme.textPrimary,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: _busy ? null : () => Navigator.pop(context),
                    icon: Icon(
                      Icons.close,
                      size: 20,
                      color: UuTheme.textSecondary,
                    ),
                  ),
                ],
              ),
              Text(
                _register ? translate('After registering, this device joins your account device list automatically') : translate('Sign in to see and connect to all devices in this account'),
                style: TextStyle(
                  color: UuTheme.textSecondary,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 20),
              _field(
                controller: _username,
                label: translate('Username'),
                icon: Icons.person_outline,
                autofocus: true,
              ),
              const SizedBox(height: 12),
              _field(
                controller: _password,
                label: translate('Password'),
                icon: Icons.lock_outline,
                obscure: true,
              ),
              if (_register) ...[
                const SizedBox(height: 12),
                _field(
                  controller: _confirm,
                  label: translate('Confirm password'),
                  icon: Icons.lock_outline,
                  obscure: true,
                ),
                const SizedBox(height: 12),
                _field(
                  controller: _displayName,
                  label: translate('Display name (optional)'),
                  icon: Icons.badge_outlined,
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: const TextStyle(
                    color: UuColors.danger,
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
                          _register ? translate('Register and sign in') : translate('Login'),
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
                  _register ? translate('Already have an account? Sign in') : translate('No account yet? Register now'),
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
