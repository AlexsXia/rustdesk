import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_hbb/common.dart' hide Dialog;
import 'package:flutter_hbb/desktop/pages/desktop_setting_page.dart';
import 'package:get/get.dart';
import 'package:url_launcher/url_launcher_string.dart';

import 'design/uu_tokens.dart';
import 'theme.dart';
import 'uu_login_dialog.dart';
import 'widgets/uu_account.dart';
import 'widgets/uu_feedback.dart';

/// UU 远程风格的设置弹框：左侧分组列表，账号 / 关于为自定义页，
/// 其余分组复用桌面端设置内容，底部可进入完整的高级设置。
Future<void> showUuSettingsDialog(
  BuildContext context, {
  SettingsTabKey initialTab = SettingsTabKey.general,
}) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black.withOpacity(0.32),
    builder: (_) => _UuSettingsDialog(initialTab: initialTab),
  );
}

enum _UuPane { account, about }

class _UuNavItem {
  const _UuNavItem({
    required this.label,
    required this.icon,
    this.tab,
    this.pane,
  });

  final String label;
  final IconData icon;
  final SettingsTabKey? tab;
  final _UuPane? pane;

  Object get value => tab ?? pane!;
}

final _stockTabs = <SettingsTabKey, _UuNavItem>{
  SettingsTabKey.general: _UuNavItem(
      label: translate('General settings'), icon: Icons.tune, tab: SettingsTabKey.general),
  SettingsTabKey.safety: _UuNavItem(
      label: translate('Security'),
      icon: Icons.enhanced_encryption_outlined,
      tab: SettingsTabKey.safety),
  SettingsTabKey.network:
      _UuNavItem(label: translate('Network'), icon: Icons.link, tab: SettingsTabKey.network),
  SettingsTabKey.display: _UuNavItem(
      label: translate('Display'),
      icon: Icons.desktop_windows_outlined,
      tab: SettingsTabKey.display),
  SettingsTabKey.printer: _UuNavItem(
      label: translate('Printer'), icon: Icons.print_outlined, tab: SettingsTabKey.printer),
};

class _UuSettingsDialog extends StatefulWidget {
  const _UuSettingsDialog({required this.initialTab});

  final SettingsTabKey initialTab;

  @override
  State<_UuSettingsDialog> createState() => _UuSettingsDialogState();
}

class _UuSettingsDialogState extends State<_UuSettingsDialog> {
  late final List<_UuNavItem> _items = [
    _UuNavItem(
        label: translate('Account'), icon: Icons.account_circle_outlined, pane: _UuPane.account),
    for (final tab in DesktopSettingPage.tabKeys)
      if (_stockTabs[tab] != null) _stockTabs[tab]!,
    _UuNavItem(
        label: translate('About'), icon: Icons.info_outline, pane: _UuPane.about),
  ];

  late Object _selected = _items
          .any((item) => item.tab == widget.initialTab)
      ? widget.initialTab
      : _items.first.value;

  void _openAdvanced() {
    Navigator.of(context).pop();
    DesktopSettingPage.switch2page(SettingsTabKey.general);
  }

  @override
  Widget build(BuildContext context) {
    UuColors.apply(context);
    final size = MediaQuery.of(context).size;
    final width = math.min(800.0, size.width - 64);
    final height = math.min(640.0, size.height - 96);
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.all(24),
      child: Container(
        width: width,
        height: height,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: UuTheme.surface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.18),
              blurRadius: 40,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Material(
          type: MaterialType.transparency,
          child: Column(
            children: [
              _titleBar(),
              Divider(height: 1, thickness: 1, color: UuTheme.divider),
              Expanded(
                child: Row(
                  children: [
                    _sidebar(),
                    VerticalDivider(
                        width: 1, thickness: 1, color: UuTheme.divider),
                    Expanded(child: _content()),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _titleBar() {
    return SizedBox(
      height: 54,
      child: Stack(
        children: [
          Center(
            child: Text(
              translate('Settings'),
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: UuTheme.textPrimary,
              ),
            ),
          ),
          Positioned(
            right: 8,
            top: 9,
            child: IconButton(
              onPressed: () => Navigator.of(context).pop(),
              icon: Icon(Icons.close,
                  size: 20, color: UuTheme.textSecondary),
              style: IconButton.styleFrom(hoverColor: UuColors.hoverTint),
              visualDensity: VisualDensity.compact,
            ),
          ),
        ],
      ),
    );
  }

  Widget _sidebar() {
    return Container(
      width: 180,
      color: UuColors.surfaceAlt,
      padding: const EdgeInsets.fromLTRB(10, 12, 10, 12),
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final item in _items) _navItem(item),
            const Spacer(),
            Divider(height: 18, color: UuTheme.divider),
            InkWell(
              hoverColor: UuColors.hoverTint,
              borderRadius: BorderRadius.circular(10),
              onTap: _openAdvanced,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(
                  children: [
                    Icon(Icons.open_in_new,
                        size: 18, color: UuTheme.textSecondary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        translate('Advanced settings'),
                        style: TextStyle(
                          color: UuTheme.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _navItem(_UuNavItem item) {
    final selected = item.value == _selected;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: InkWell(
        hoverColor: UuColors.hoverTint,
        borderRadius: BorderRadius.circular(10),
        onTap: () => setState(() => _selected = item.value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: selected
                ? UuTheme.accentSoft
                : UuTheme.accentSoft.withOpacity(0),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Icon(
                item.icon,
                size: 18,
                color: selected ? UuTheme.accent : UuTheme.textSecondary,
              ),
              const SizedBox(width: 10),
              Text(
                item.label,
                style: TextStyle(
                  fontSize: 13,
                  color: selected ? UuTheme.accent : UuTheme.textPrimary,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _content() {
    if (_selected is SettingsTabKey) {
      return Center(
        child: SizedBox(
          width: 570,
          child: _UuSettingsTheme(
            child: DesktopSettingContent(tabKey: _selected as SettingsTabKey),
          ),
        ),
      );
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: _selected == _UuPane.account
          ? const _UuAccountPane()
          : const _UuAboutPane(),
    );
  }
}

/// Re-skins the stock setting panes with the UU palette, without touching the
/// shared widgets used by the classic desktop settings page.
class _UuSettingsTheme extends StatelessWidget {
  const _UuSettingsTheme({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    UuColors.apply(context);
    final base = Theme.of(context);
    final extensions = [
      for (final extension in base.extensions.values)
        if (extension is ColorThemeExtension)
          extension.copyWith(
            border: UuColors.border,
            border2: UuColors.border,
            divider: UuColors.divider,
            highlight: UuColors.hoverTint,
          )
        else
          extension,
    ];
    return Theme(
      data: base.copyWith(
        visualDensity: VisualDensity.compact,
        colorScheme: base.colorScheme.copyWith(
          primary: UuColors.primary,
          surface: UuColors.surface,
          background: UuColors.background,
          onSurface: UuColors.textPrimary,
          outline: UuColors.border,
        ),
        canvasColor: UuColors.surface,
        cardTheme: base.cardTheme.copyWith(
          color: UuColors.surface,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(UuRadius.lg),
            side: BorderSide(color: UuColors.border),
          ),
        ),
        textTheme: base.textTheme.apply(
          bodyColor: UuColors.textPrimary,
          displayColor: UuColors.textPrimary,
        ),
        iconTheme: IconThemeData(color: UuColors.textSecondary),
        dividerTheme: DividerThemeData(
          color: UuColors.divider,
          thickness: 1,
          space: 1,
        ),
        hoverColor: UuColors.hoverTint,
        highlightColor: UuColors.hoverTint,
        splashColor: Colors.transparent,
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            elevation: 0,
            backgroundColor: UuColors.primary,
            foregroundColor: Colors.white,
            minimumSize: const Size(0, 34),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(UuRadius.sm),
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: UuColors.textPrimary,
            minimumSize: const Size(0, 34),
            side: BorderSide(color: UuColors.border),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(UuRadius.sm),
            ),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: UuColors.primary,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(UuRadius.sm),
            ),
          ),
        ),
        radioTheme: base.radioTheme.copyWith(
          fillColor: MaterialStateProperty.resolveWith(
            (states) => states.contains(MaterialState.selected)
                ? UuColors.primary
                : UuColors.border,
          ),
          overlayColor: MaterialStateProperty.all(Colors.transparent),
        ),
        checkboxTheme: base.checkboxTheme.copyWith(
          fillColor: MaterialStateProperty.resolveWith(
            (states) => states.contains(MaterialState.selected)
                ? UuColors.primary
                : Colors.transparent,
          ),
          checkColor: MaterialStateProperty.all(Colors.white),
          side: BorderSide(color: UuColors.border),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(4),
          ),
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        switchTheme: base.switchTheme.copyWith(
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          trackColor: MaterialStateProperty.resolveWith(
            (states) => states.contains(MaterialState.selected)
                ? UuColors.primary
                : UuColors.divider,
          ),
          trackOutlineColor:
              MaterialStateProperty.all(Colors.transparent),
          thumbColor: MaterialStateProperty.resolveWith(
            (states) => states.contains(MaterialState.selected)
                ? Colors.white
                : UuColors.surface,
          ),
        ),
        inputDecorationTheme: base.inputDecorationTheme.copyWith(
          filled: true,
          fillColor: UuColors.background,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(UuRadius.sm + 2),
            borderSide: BorderSide(color: UuColors.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(UuRadius.sm + 2),
            borderSide: BorderSide(color: UuColors.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(UuRadius.sm + 2),
            borderSide: BorderSide(color: UuColors.primary),
          ),
        ),
        extensions: extensions,
      ),
      child: MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: const TextScaler.linear(0.9)),
        child: child,
      ),
    );
  }
}

class _UuAccountPane extends StatelessWidget {
  const _UuAccountPane();

  @override
  Widget build(BuildContext context) {
    UuColors.apply(context);
    return Obx(() {
      final loggedIn = gFFI.userModel.isLogin;
      final name =
          loggedIn ? gFFI.userModel.displayNameOrUserName : translate('Not signed in');
      final userName = gFFI.userModel.userName.value;
      final initial =
          loggedIn && name.isNotEmpty ? name.substring(0, 1).toUpperCase() : '';
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor:
                    loggedIn ? UuColors.primarySoft : UuColors.hover,
                child: loggedIn
                    ? Text(
                        initial,
                        style: const TextStyle(
                          color: UuColors.primary,
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                        ),
                      )
                    : Icon(Icons.person_outline,
                        color: UuColors.textTertiary),
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
                        color: UuColors.textPrimary,
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      loggedIn ? '@$userName' : translate('Sign in to sync account devices'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: UuColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          if (!loggedIn) ...[
            Text(
              translate('After signing in, your computers and phones appear in the device list automatically; no manual ID entry needed.'),
              style: TextStyle(
                color: UuColors.textSecondary,
                fontSize: 13,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton(
                onPressed: () async {
                  final ok = await uuLoginDialog(context);
                  if (ok == true) {
                    uuToast(translate('Signed in'));
                  }
                },
                style: FilledButton.styleFrom(
                  backgroundColor: UuColors.primary,
                  minimumSize: const Size(120, 40),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(translate('Login / Register')),
              ),
            ),
          ] else
            Row(
              children: [
                OutlinedButton(
                  onPressed: () => uuRefreshDevices(),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: UuColors.textPrimary,
                    side: BorderSide(color: UuColors.border),
                    minimumSize: const Size(104, 40),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(translate('Refresh devices')),
                ),
                const SizedBox(width: 10),
                OutlinedButton(
                  onPressed: () async {
                    if (!await uuConfirmLogout(context)) {
                      return;
                    }
                    await gFFI.userModel.logOut();
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: UuColors.danger,
                    side: const BorderSide(color: UuColors.danger),
                    minimumSize: const Size(104, 40),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(translate('Sign out')),
                ),
              ],
            ),
          const SizedBox(height: 24),
          Divider(height: 1, color: UuColors.divider),
          const SizedBox(height: 16),
          Text(
            translate('Account data is stored on the self-hosted account server; local remote passwords are never uploaded.'),
            style: TextStyle(
              color: UuColors.textTertiary,
              fontSize: 12,
              height: 1.5,
            ),
          ),
        ],
      );
    });
  }
}

class _UuAboutPane extends StatelessWidget {
  const _UuAboutPane();

  @override
  Widget build(BuildContext context) {
    UuColors.apply(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: UuColors.primarySoft,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.desktop_windows,
                  color: UuColors.primary, size: 26),
            ),
            const SizedBox(width: 14),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  translate('UU Remote'),
                  style: TextStyle(
                    color: UuColors.textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: 3),
                Text(
                  translate('Secure, smooth remote desktop'),
                  style:
                      TextStyle(color: UuColors.textSecondary, fontSize: 12),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 20),
        _row(translate('Version'), version),
        _divider(),
        _row(
          translate('Local ID'),
          gFFI.serverModel.serverId.text,
          onTap: () {
            Clipboard.setData(
                ClipboardData(text: gFFI.serverModel.serverId.text));
            uuToast(translate('Copied'));
          },
        ),
        _divider(),
        _row(translate('Help and feedback'), '',
            onTap: () => launchUrlString('https://rustdesk.com/docs/')),
        _divider(),
        _row(translate('Privacy policy'), '',
            onTap: () => launchUrlString('https://rustdesk.com/privacy.html')),
      ],
    );
  }

  Widget _row(String label, String value, {VoidCallback? onTap}) {
    return InkWell(
      hoverColor: UuColors.hoverTint,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 13),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                    color: UuColors.textPrimary, fontSize: 14),
              ),
            ),
            Text(
              value,
              style:
                  TextStyle(color: UuColors.textSecondary, fontSize: 13),
            ),
            if (onTap != null) ...[
              const SizedBox(width: 4),
              Icon(Icons.chevron_right,
                  size: 18, color: UuColors.textTertiary),
            ],
          ],
        ),
      ),
    );
  }

  Widget _divider() =>
      Divider(height: 1, thickness: 1, color: UuColors.divider);
}
