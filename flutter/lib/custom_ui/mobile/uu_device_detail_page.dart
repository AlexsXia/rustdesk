import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/mobile/pages/remote_page.dart';
import 'package:flutter_hbb/models/peer_model.dart';
import 'package:flutter_hbb/models/platform_model.dart';

import '../theme.dart';
import '../uu_peer.dart';
import '../uu_session_intent.dart';
import '../uu_wallpaper.dart';

/// UU 远程风格的设备详情页：预览图 + 进入桌面 + 快捷工具。
class UuDeviceDetailPage extends StatefulWidget {
  const UuDeviceDetailPage({super.key, required this.peer});

  final Peer peer;

  @override
  State<UuDeviceDetailPage> createState() => _UuDeviceDetailPageState();
}

class _UuDeviceDetailPageState extends State<UuDeviceDetailPage> {
  static const _bg = Color(0xFFF2F3F7);

  late Peer _peer;
  Timer? _onlineTimer;

  @override
  void initState() {
    super.initState();
    _peer = widget.peer;
    _peerListeners();
    _queryOnline();
    _onlineTimer = Timer.periodic(
      const Duration(seconds: 8),
      (_) => _queryOnline(),
    );
  }

  @override
  void dispose() {
    _onlineTimer?.cancel();
    for (final peers in _trackedModels) {
      peers.removeListener(_onPeersChanged);
    }
    super.dispose();
  }

  List<Peers> get _trackedModels => [
        gFFI.abModel.peersModel,
        gFFI.favoritePeersModel,
        gFFI.recentPeersModel,
      ];

  void _peerListeners() {
    for (final peers in _trackedModels) {
      peers.addListener(_onPeersChanged);
    }
  }

  void _onPeersChanged() {
    if (mounted) setState(() {});
  }

  void _queryOnline() {
    unawaited(bind.queryOnlines(ids: [_peer.id]));
  }

  bool get _online => _peer.online;

  String get _name => uuPeerName(_peer);

  IconData get _brandIcon {
    final p = _peer.platform.toLowerCase();
    if (p.contains('mac') ||
        p.contains('ios') ||
        p.contains('iphone') ||
        p.contains('ipad')) {
      return Icons.apple;
    }
    if (p.contains('win')) return Icons.desktop_windows;
    if (p.contains('android')) return Icons.android;
    if (p.contains('linux')) return Icons.computer;
    return Icons.devices;
  }

  List<Color> get _heroColors {
    final p = _peer.platform.toLowerCase();
    if (p.contains('mac') || p.contains('ios')) {
      return const [Color(0xFF5B7CFA), Color(0xFFB18CFF)];
    }
    if (p.contains('win')) {
      return const [Color(0xFF22C1C3), Color(0xFF2563EB)];
    }
    if (p.contains('android')) {
      return const [Color(0xFF34D399), Color(0xFF0EA5E9)];
    }
    if (p.contains('linux')) {
      return const [Color(0xFFF59E0B), Color(0xFFEF4444)];
    }
    return const [Color(0xFF94A3B8), Color(0xFF475569)];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _header(),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
                children: [
                  _hero(),
                  const SizedBox(height: 14),
                  _actionRow(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 6, 6, 4),
      child: Row(
        children: [
          _RoundIconButton(
            icon: Icons.arrow_back_ios_new,
            onTap: () => Navigator.of(context).maybePop(),
          ),
          const SizedBox(width: 10),
          _StatusPill(online: _online),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              _name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: UuTheme.textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const Spacer(),
          IconButton(
            onPressed: _showMoreMenu,
            icon: const Icon(Icons.more_vert, color: UuTheme.textPrimary),
          ),
        ],
      ),
    );
  }

  Widget _hero() {
    return GestureDetector(
      onTap: _online ? _enterDesktop : _offlineTip,
      child: Container(
        height: 240,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: LinearGradient(
            colors: _online
                ? _heroColors
                : const [Color(0xFFB8BDC7), Color(0xFF8E949F)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Center(
              child: Icon(
                _brandIcon,
                size: 96,
                color: Colors.white.withOpacity(0.22),
              ),
            ),
            Positioned.fill(
              child: UuWallpaperLayer(
                peerId: _peer.id,
                fallback: const SizedBox.shrink(),
              ),
            ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Color(0x59000000)],
                ),
              ),
            ),
            Align(
              alignment: const Alignment(0, 0.62),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _online ? '进入桌面' : '设备已离线',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 21,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (_online) ...[
                    const SizedBox(width: 2),
                    const Icon(Icons.chevron_right,
                        color: Colors.white, size: 24),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _actionRow() {
    final actions = <(IconData, String, VoidCallback)>[
      (Icons.drive_folder_upload_outlined, '文件传输', _openFileTransfer),
      (Icons.play_circle_outline, '观看模式', _openViewOnly),
      (Icons.terminal_rounded, '终端', _openTerminal),
      (Icons.grid_view_rounded, '更多', _openMoreTools),
    ];
    return Container(
      height: 86,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          for (var i = 0; i < actions.length; i++) ...[
            if (i > 0)
              const SizedBox(
                height: 34,
                child: VerticalDivider(width: 1, color: Color(0xFFEFF1F5)),
              ),
            Expanded(
              child: InkWell(
                onTap: actions[i].$3,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(actions[i].$1,
                        size: 24, color: UuTheme.textPrimary),
                    const SizedBox(height: 7),
                    Text(
                      actions[i].$2,
                      style: const TextStyle(
                        color: UuTheme.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _offlineTip() {
    showToast('设备当前离线');
  }

  Future<void> _enterDesktop() async {
    if (!_online) {
      _offlineTip();
      return;
    }
    await connect(context, _peer.id, password: uuPeerPassword(_peer));
  }

  Future<void> _openFileTransfer() async {
    if (!_online) {
      _offlineTip();
      return;
    }
    await connect(
      context,
      _peer.id,
      password: uuPeerPassword(_peer),
      isFileTransfer: true,
    );
  }

  Future<void> _openTerminal() async {
    if (!_online) {
      _offlineTip();
      return;
    }
    await connect(
      context,
      _peer.id,
      password: uuPeerPassword(_peer),
      isTerminal: true,
    );
  }

  void _openViewOnly() {
    if (!_online) {
      _offlineTip();
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RemotePage(
          id: _peer.id,
          password: uuPeerPassword(_peer),
          initialViewOnly: true,
        ),
      ),
    );
  }

  void _openMoreTools() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => _UuMoreToolsPage(state: this)),
    );
  }

  Future<void> _confirmPower(String action) async {
    if (!_online) {
      _offlineTip();
      return;
    }
    final verb = action == UuSessionIntent.restart ? '重启' : '关机';
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('$verb设备'),
        content: Text('确定要$verb「$_name」吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFE5484D)),
            child: Text(verb),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) {
      return;
    }
    UuSessionIntent.schedule(_peer.id, action);
    await connect(context, _peer.id, password: uuPeerPassword(_peer));
  }

  void _showMoreMenu() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.copy_rounded, size: 22),
              title: const Text('复制设备 ID'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                Clipboard.setData(ClipboardData(text: _peer.id));
                showToast('已复制设备 ID');
              },
            ),
            ListTile(
              leading: const Icon(Icons.refresh_rounded, size: 22),
              title: const Text('刷新状态'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _queryOnline();
                setState(() {});
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _UuMoreToolsPage extends StatelessWidget {
  const _UuMoreToolsPage({required this.state});

  final _UuDeviceDetailPageState state;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F3F7),
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: UuTheme.textPrimary,
        elevation: 0,
        centerTitle: true,
        title: const Text('更多工具'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              children: [
                _row(context, Icons.drive_folder_upload_outlined, '文件传输',
                    state._openFileTransfer),
                _divider(),
                _row(context, Icons.play_circle_outline, '观看模式',
                    state._openViewOnly),
                _divider(),
                _row(context, Icons.terminal_rounded, '终端', state._openTerminal),
                _divider(),
                _row(context, Icons.restart_alt_rounded, '重启',
                    () => state._confirmPower(UuSessionIntent.restart)),
                _divider(),
                _row(context, Icons.power_settings_new_rounded, '关机',
                    () => state._confirmPower(UuSessionIntent.shutdown)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(
      BuildContext context, IconData icon, String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 17),
        child: Row(
          children: [
            Icon(icon, size: 23, color: UuTheme.textPrimary),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  color: UuTheme.textPrimary,
                  fontSize: 17,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const Icon(Icons.chevron_right,
                size: 22, color: Color(0xFFC7CBD3)),
          ],
        ),
      ),
    );
  }

  Widget _divider() => const Divider(
        height: 0.5,
        thickness: 0.5,
        indent: 56,
        endIndent: 16,
        color: Color(0xFFEDEFF3),
      );
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(icon, size: 18, color: UuTheme.textPrimary),
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.online});

  final bool online;

  @override
  Widget build(BuildContext context) {
    final color =
        online ? const Color(0xFF16A34A) : const Color(0xFF9CA3AF);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(
            online ? '在线' : '离线',
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
