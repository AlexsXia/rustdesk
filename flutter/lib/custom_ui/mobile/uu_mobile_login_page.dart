import 'dart:async';

import 'package:flutter/material.dart';

import '../theme.dart';
import '../uu_auth.dart';

class UuMobileLoginPage extends StatefulWidget {
  const UuMobileLoginPage({super.key, this.initialRegister = false});

  final bool initialRegister;

  @override
  State<UuMobileLoginPage> createState() => _UuMobileLoginPageState();
}

class _UuMobileLoginPageState extends State<UuMobileLoginPage> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _displayName = TextEditingController();
  late bool _register = widget.initialRegister;
  bool _busy = false;
  bool _obscure = true;
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
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await uuAuthRequest(
        register: _register,
        username: username,
        password: password,
        displayName: _displayName.text,
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
        setState(() => _error = '网络错误：$e');
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  InputDecoration _decoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: UuTheme.textSecondary, size: 20),
      filled: true,
      fillColor: const Color(0xFFF4F5F8),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: UuTheme.accent, width: 1.2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: UuTheme.textPrimary),
          onPressed: () => Navigator.of(context).pop(false),
        ),
      ),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _register ? '创建账号' : '登录',
                style: const TextStyle(
                  color: UuTheme.textPrimary,
                  fontSize: 30,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _register
                    ? '注册成功后，本机会自动加入账号设备列表'
                    : '登录后即可在手机上控制该账号下的所有设备',
                style: const TextStyle(
                  color: UuTheme.textSecondary,
                  fontSize: 14,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 32),
              TextField(
                controller: _username,
                enabled: !_busy,
                autofocus: true,
                autocorrect: false,
                textInputAction: TextInputAction.next,
                decoration: _decoration('用户名', Icons.person_outline),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _password,
                enabled: !_busy,
                obscureText: _obscure,
                textInputAction: _register
                    ? TextInputAction.next
                    : TextInputAction.done,
                onSubmitted: (_) {
                  if (!_register) unawaited(_submit());
                },
                decoration: _decoration('密码', Icons.lock_outline).copyWith(
                  suffixIcon: IconButton(
                    onPressed: () => setState(() => _obscure = !_obscure),
                    icon: Icon(
                      _obscure ? Icons.visibility_off : Icons.visibility,
                      size: 20,
                      color: UuTheme.textSecondary,
                    ),
                  ),
                ),
              ),
              if (_register) ...[
                const SizedBox(height: 14),
                TextField(
                  controller: _confirm,
                  enabled: !_busy,
                  obscureText: _obscure,
                  textInputAction: TextInputAction.next,
                  decoration: _decoration('确认密码', Icons.lock_outline),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _displayName,
                  enabled: !_busy,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => unawaited(_submit()),
                  decoration: _decoration('昵称（可选）', Icons.badge_outlined),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 14),
                Text(
                  _error!,
                  style: const TextStyle(
                    color: Color(0xFFDC2626),
                    fontSize: 13,
                  ),
                ),
              ],
              const SizedBox(height: 28),
              SizedBox(
                height: 52,
                child: FilledButton(
                  onPressed: _busy ? null : () => unawaited(_submit()),
                  style: FilledButton.styleFrom(
                    backgroundColor: UuTheme.accent,
                    disabledBackgroundColor: UuTheme.accent.withOpacity(0.4),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: _busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          _register ? '注册并登录' : '登录',
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 14),
              TextButton(
                onPressed: _busy
                    ? null
                    : () => setState(() {
                          _register = !_register;
                          _error = null;
                        }),
                child: Text(
                  _register ? '已有账号？去登录' : '还没有账号？立即注册',
                  style: const TextStyle(color: UuTheme.accent, fontSize: 14),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
