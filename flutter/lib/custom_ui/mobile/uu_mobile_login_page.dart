import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart' show translate;

import '../design/uu_tokens.dart';
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
        setState(() => _error = translate('Network error: {$e}'));
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
      fillColor: UuColors.background,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: UuTheme.accent, width: 1.2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    );
  }

  @override
  Widget build(BuildContext context) {
    UuColors.apply(context);
    return Scaffold(
      backgroundColor: UuColors.surface,
      appBar: AppBar(
        backgroundColor: UuColors.surface,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.close, color: UuTheme.textPrimary),
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
                _register ? translate('Create account') : translate('Login'),
                style: TextStyle(
                  color: UuTheme.textPrimary,
                  fontSize: 30,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _register
                    ? translate('After registering, this device joins your account device list automatically')
                    : translate('Sign in to control all devices in this account from your phone'),
                style: TextStyle(
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
                decoration: _decoration(translate('Username'), Icons.person_outline),
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
                decoration: _decoration(translate('Password'), Icons.lock_outline).copyWith(
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
                  decoration: _decoration(translate('Confirm password'), Icons.lock_outline),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _displayName,
                  enabled: !_busy,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => unawaited(_submit()),
                  decoration: _decoration(translate('Display name (optional)'), Icons.badge_outlined),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 14),
                Text(
                  _error!,
                  style: const TextStyle(
                    color: UuColors.danger,
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
                          _register ? translate('Register and sign in') : translate('Login'),
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
                  _register ? translate('Already have an account? Sign in') : translate('No account yet? Register now'),
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
