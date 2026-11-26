import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_hbb/desktop/pages/desktop_setting_page.dart';

import 'theme.dart';

/// UU 远程风格的设置弹框：顶部图标分页，每个设置分组一页。
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

class _UuTab {
  const _UuTab(this.key, this.label, this.icon, this.selectedIcon);

  final SettingsTabKey key;
  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

const _allTabs = <_UuTab>[
  _UuTab(SettingsTabKey.general, '常规', Icons.settings_outlined, Icons.settings),
  _UuTab(SettingsTabKey.safety, '安全', Icons.enhanced_encryption_outlined,
      Icons.enhanced_encryption),
  _UuTab(SettingsTabKey.network, '网络', Icons.link_outlined, Icons.link),
  _UuTab(SettingsTabKey.display, '显示', Icons.desktop_windows_outlined,
      Icons.desktop_windows),
  _UuTab(SettingsTabKey.printer, '打印机', Icons.print_outlined, Icons.print),
];

class _UuSettingsDialog extends StatefulWidget {
  const _UuSettingsDialog({required this.initialTab});

  final SettingsTabKey initialTab;

  @override
  State<_UuSettingsDialog> createState() => _UuSettingsDialogState();
}

class _UuSettingsDialogState extends State<_UuSettingsDialog> {
  late final List<_UuTab> _tabs = _allTabs
      .where((tab) => DesktopSettingPage.tabKeys.contains(tab.key))
      .toList();
  late SettingsTabKey _selected = _tabs.any((tab) => tab.key == widget.initialTab)
      ? widget.initialTab
      : _tabs.first.key;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final width = math.min(620.0, size.width - 64);
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
        child: Column(
          children: [
            _titleBar(),
            _tabBar(),
            const Divider(height: 1, thickness: 1, color: UuTheme.divider),
            Expanded(
              child: Center(
                child: SizedBox(
                  width: 570,
                  child: DesktopSettingContent(tabKey: _selected),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _titleBar() {
    return SizedBox(
      height: 54,
      child: Stack(
        children: [
          const Center(
            child: Text(
              '设置',
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
              icon: const Icon(Icons.close, size: 20,
                  color: UuTheme.textSecondary),
              visualDensity: VisualDensity.compact,
            ),
          ),
        ],
      ),
    );
  }

  Widget _tabBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 2, 12, 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (final tab in _tabs)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: _tabItem(tab),
            ),
        ],
      ),
    );
  }

  Widget _tabItem(_UuTab tab) {
    final selected = tab.key == _selected;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => setState(() => _selected = tab.key),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 72,
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: selected ? UuTheme.accentSoft : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Icon(
              selected ? tab.selectedIcon : tab.icon,
              size: 22,
              color: selected ? UuTheme.accent : UuTheme.textSecondary,
            ),
            const SizedBox(height: 5),
            Text(
              tab.label,
              style: TextStyle(
                fontSize: 12,
                color: selected ? UuTheme.accent : UuTheme.textSecondary,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
