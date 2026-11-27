import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/mobile/pages/settings_page.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:get/get.dart';
import 'package:url_launcher/url_launcher_string.dart';

import '../design/uu_tokens.dart';
import '../theme.dart';
import '../uu_defaults.dart';
import '../uu_keymap.dart';
import '../widgets/uu_account.dart';
import '../widgets/uu_feedback.dart';
import 'uu_keymap_overlay.dart';
import 'uu_mobile_login_page.dart';

const _danger = UuColors.danger;

/// UU 风格的移动端设置页。
class UuSettingsPage extends StatefulWidget {
  const UuSettingsPage({super.key});

  @override
  State<UuSettingsPage> createState() => _UuSettingsPageState();
}

class _UuSettingsPageState extends State<UuSettingsPage> {
  List<List<String>> _langs = const [];
  String _lang = '';
  String _myId = '';
  bool _keyMapping = false;

  Color get _bg => UuColors.background;
  Color get _muted => UuColors.textSecondary;
  Color get _hairline => UuColors.divider;
  Color get _chevron => UuColors.textTertiary;

  @override
  void initState() {
    super.initState();
    _lang = bind.mainGetLocalOption(key: kCommConfKeyLang);
    _keyMapping = uuKeyMappingEnabled();
    _loadLangs();
    _loadId();
  }

  Future<void> _loadLangs() async {
    try {
      final raw = await bind.mainGetLangs();
      final list = (json.decode(raw) as List)
          .map((e) => [(e as List)[0] as String, e[1] as String])
          .toList();
      if (mounted) setState(() => _langs = list);
    } catch (e) {
      debugPrint('load languages failed: $e');
    }
  }

  Future<void> _loadId() async {
    final id = await bind.mainGetMyId();
    if (mounted) setState(() => _myId = id);
  }

  String get _langLabel {
    if (_lang.isEmpty || _lang == defaultOptionLang) return translate('Follow System');
    for (final item in _langs) {
      if (item[0] == _lang) return translate(item[1]);
    }
    return _lang;
  }

  String get _themeLabel {
    switch (MyTheme.getThemeModePreference()) {
      case ThemeMode.light:
        return translate('Light');
      case ThemeMode.dark:
        return translate('Dark');
      default:
        return translate('Follow System');
    }
  }

  Future<void> _openLogin() async {
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const UuMobileLoginPage()),
    );
    if (ok == true) {
      uuToast(translate('Signed in'));
      if (mounted) setState(() {});
    }
  }

  void _showAccountSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: UuColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        UuColors.apply(sheetContext);
        final name = gFFI.userModel.displayNameOrUserName;
        final userName = gFFI.userModel.userName.value;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircleAvatar(
                  radius: 28,
                  backgroundColor: UuTheme.accent,
                  child: Icon(Icons.person, color: Colors.white, size: 36),
                ),
                const SizedBox(height: 10),
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: UuTheme.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '@$userName',
                  style: TextStyle(color: _muted, fontSize: 13),
                ),
                const SizedBox(height: 14),
                Divider(height: 1, color: _hairline),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.sync, color: UuTheme.accent),
                  title: Text(translate('Refresh devices')),
                  onTap: () async {
                    Navigator.of(sheetContext).pop();
                    await uuRefreshDevices();
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.logout, color: _danger),
                  title: Text(translate('Sign out'),
                      style: TextStyle(color: _danger)),
                  onTap: () async {
                    Navigator.of(sheetContext).pop();
                    if (!await uuConfirmLogout(context)) {
                      return;
                    }
                    await gFFI.userModel.logOut();
                    if (mounted) setState(() {});
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _pickLanguage() async {
    if (isOptionFixed(kCommConfKeyLang)) {
      uuToast(translate('Language is locked by the administrator'));
      return;
    }
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: UuColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.only(top: 18, bottom: 16),
          children: [
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                translate('Language'),
                style: TextStyle(
                  color: UuTheme.textPrimary,
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 8),
            _sheetOption(
              translate('Follow System'),
              _lang.isEmpty || _lang == defaultOptionLang,
              () => Navigator.of(sheetContext).pop(defaultOptionLang),
            ),
            for (final item in _langs)
              _sheetOption(
                translate(item[1]),
                item[0] == _lang,
                () => Navigator.of(sheetContext).pop(item[0]),
              ),
          ],
        ),
      ),
    );
    if (picked == null || picked == _lang) return;
    await bind.mainSetLocalOption(key: kCommConfKeyLang, value: picked);
    if (mounted) setState(() => _lang = picked);
  }

  Future<void> _pickTheme() async {
    if (isOptionFixed(kCommConfKeyTheme)) {
      uuToast(translate('Appearance is locked by the administrator'));
      return;
    }
    final current = MyTheme.getThemeModePreference();
    final picked = await showModalBottomSheet<ThemeMode>(
      context: context,
      backgroundColor: UuColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.only(top: 18, bottom: 16),
          children: [
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                translate('Appearance'),
                style: TextStyle(
                  color: UuTheme.textPrimary,
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 8),
            _sheetOption(translate('Follow System'), current == ThemeMode.system,
                () => Navigator.of(sheetContext).pop(ThemeMode.system)),
            _sheetOption(translate('Light'), current == ThemeMode.light,
                () => Navigator.of(sheetContext).pop(ThemeMode.light)),
            _sheetOption(translate('Dark'), current == ThemeMode.dark,
                () => Navigator.of(sheetContext).pop(ThemeMode.dark)),
          ],
        ),
      ),
    );
    if (picked == null || picked == current) return;
    await MyTheme.changeDarkMode(picked);
    if (mounted) setState(() {});
  }

  Widget _sheetOption(String label, bool selected, VoidCallback onTap) {
    return ListTile(
      title: Text(
        label,
        style: TextStyle(
          color: selected ? UuTheme.accent : UuTheme.textPrimary,
          fontSize: 16,
        ),
      ),
      trailing: selected
          ? const Icon(Icons.check, size: 20, color: UuTheme.accent)
          : null,
      onTap: onTap,
    );
  }

  Future<void> _pickKeyProfile() async {
    final profile = await showUuKeymapChooser(context);
    if (profile == null || !mounted) return;
    setState(() {});
    uuToast(translate('Switched to {${profile.name}}'));
  }

  Future<bool?> _confirmBlockService() {
    return showUuConfirm(
      context,
      title: translate('Block remote assistance'),
      message: translate('When blocked, other devices cannot connect to this device until you turn it back on.'),
      confirmText: translate('Block'),
      danger: true,
    );
  }

  void _openAdvancedSettings() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: _bg,
          appBar: AppBar(
            backgroundColor: UuColors.surface,
            foregroundColor: UuTheme.textPrimary,
            elevation: 0,
            centerTitle: true,
            title: Text(translate('Advanced settings')),
          ),
          body: SettingsPage(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    UuColors.apply(context);
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        foregroundColor: UuTheme.textPrimary,
        title: Text(
          translate('Settings'),
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
          children: [
            _accountCard(),
            _sectionLabel(translate('General settings')),
            _card(children: [
              _navRow(
                icon: Icons.translate,
                title: translate('Language'),
                value: _langLabel,
                onTap: _pickLanguage,
              ),
              _divider(),
              _navRow(
                icon: Icons.contrast,
                title: translate('Appearance'),
                value: _themeLabel,
                onTap: _pickTheme,
              ),
            ]),
            _sectionLabel(translate('Actions')),
            _card(children: [
              _switchRow(
                icon: Icons.keyboard_alt_outlined,
                title: translate('Enable key mapping'),
                subtitle: translate('Send keys directly to the computer, bypassing the phone IME'),
                value: _keyMapping,
                onChanged: (v) async {
                  await setUuKeyMapping(v);
                  if (mounted) setState(() => _keyMapping = v);
                },
              ),
              _divider(),
              _navRow(
                icon: Icons.grid_view_rounded,
                title: translate('Key mapping profile'),
                value: uuActiveKeyProfile()?.name ?? translate('Not selected'),
                onTap: _pickKeyProfile,
              ),
            ]),
            if (isAndroid) ...[
              _sectionLabel(translate('Security')),
              ListenableBuilder(
                listenable: gFFI.serverModel,
                builder: (context, _) {
                  final running = gFFI.serverModel.isStart;
                  return _card(children: [
                    _switchRow(
                      icon: Icons.shield_outlined,
                      title: translate('Block remote assistance'),
                      subtitle: running
                          ? translate('When off, other devices cannot connect to this device')
                          : translate('Other devices cannot connect to this device right now'),
                      value: !running,
                      onChanged: (block) async {
                        if (block) {
                          final ok = await _confirmBlockService();
                          if (ok == true) {
                            await gFFI.serverModel.stopService();
                          }
                        } else {
                          await gFFI.serverModel.toggleService();
                        }
                      },
                    ),
                  ]);
                },
              ),
            ],
            _sectionLabel(translate('About')),
            _card(children: [
              _navRow(icon: Icons.info_outline, title: translate('Version'), value: version),
              _divider(),
              _navRow(
                icon: Icons.perm_identity,
                title: translate('Local ID'),
                value: _myId,
                onTap: () => onCopyId(_myId),
              ),
              _divider(),
              _navRow(
                icon: Icons.help_outline,
                title: translate('Help and feedback'),
                onTap: () =>
                    launchUrlString('https://rustdesk.com/docs/'),
              ),
              _divider(),
              _navRow(
                icon: Icons.privacy_tip_outlined,
                title: translate('Privacy policy'),
                onTap: () =>
                    launchUrlString('https://rustdesk.com/privacy.html'),
              ),
              _divider(),
              _navRow(
                icon: Icons.tune,
                title: translate('Advanced settings'),
                subtitle: translate('Full settings for network, security, display, and more'),
                onTap: _openAdvancedSettings,
              ),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _accountCard() {
    return Obx(() {
      final loggedIn = gFFI.userModel.isLogin;
      final name =
          loggedIn ? gFFI.userModel.displayNameOrUserName : translate('Login / Register');
      final subtitle = loggedIn
          ? '@${gFFI.userModel.userName.value}'
          : translate('Sign in to sync account devices');
      return _card(children: [
        InkWell(
          onTap: loggedIn ? _showAccountSheet : _openLogin,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: Row(
              children: [
                const CircleAvatar(
                  radius: 24,
                  backgroundColor: UuTheme.accent,
                  child: Icon(Icons.person, color: Colors.white, size: 30),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: UuTheme.textPrimary,
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: _muted, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, size: 20, color: _chevron),
              ],
            ),
          ),
        ),
      ]);
    });
  }

  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
      child: Text(
        text,
        style: TextStyle(
          color: _muted,
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _card({required List<Widget> children}) {
    return Container(
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: UuColors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(children: children),
    );
  }

  Widget _divider() {
    return Divider(
      height: 0.5,
      thickness: 0.5,
      indent: 52,
      endIndent: 16,
      color: _hairline,
    );
  }

  Widget _navRow({
    required IconData icon,
    required String title,
    String? subtitle,
    String? value,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 22, color: UuTheme.textPrimary),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: UuTheme.textPrimary,
                      fontSize: 16,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(color: _muted, fontSize: 12),
                    ),
                  ],
                ],
              ),
            ),
            if (value != null)
              Padding(
                padding: const EdgeInsets.only(left: 10),
                child: Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: _muted, fontSize: 14),
                ),
              ),
            if (onTap != null) ...[
              const SizedBox(width: 4),
              Icon(Icons.chevron_right, size: 20, color: _chevron),
            ],
          ],
        ),
      ),
    );
  }

  Widget _switchRow({
    required IconData icon,
    required String title,
    String? subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 22, color: UuTheme.textPrimary),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: UuTheme.textPrimary,
                    fontSize: 16,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(color: _muted, fontSize: 12),
                  ),
                ],
              ],
            ),
          ),
          Switch(
            value: value,
            activeColor: UuTheme.accent,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}
