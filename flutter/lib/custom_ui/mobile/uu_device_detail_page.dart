import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/mobile/pages/remote_page.dart';
import 'package:flutter_hbb/models/peer_model.dart';
import 'package:flutter_hbb/models/platform_model.dart';

import '../design/uu_tokens.dart';
import '../theme.dart';
import '../uu_peer.dart';
import '../uu_session_intent.dart';
import '../uu_wallpaper.dart';
import '../widgets/uu_components.dart';
import '../widgets/uu_feedback.dart';
import '../widgets/uu_platform_icon.dart';
import '../widgets/uu_rename_dialog.dart';

/// UU 远程风格的设备详情页：预览图 + 进入桌面 + 快捷工具。
class UuDeviceDetailPage extends StatefulWidget {
  const UuDeviceDetailPage({super.key, required this.peer});

  final Peer peer;

  @override
  State<UuDeviceDetailPage> createState() => _UuDeviceDetailPageState();
}

class _UuDeviceDetailPageState extends State<UuDeviceDetailPage> {
  Color get _bg => UuColors.background;

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

  bool get _inAddressBook =>
      gFFI.abModel.currentAbPeers.any((p) => p.id == _peer.id);

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
    UuColors.apply(context);
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
                  const SizedBox(height: 14),
                  _infoCard(),
                  const SizedBox(height: 20),
                  Center(
                    child: UuPillButton(
                      label: translate('Delete device'),
                      icon: Icons.delete_outline,
                      filled: false,
                      danger: true,
                      onPressed: () => unawaited(_deleteDevice()),
                    ),
                  ),
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
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: UuTheme.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Icon(
                      UuPeerPlatformIcon.iconFor(_peer.platform),
                      size: 13,
                      color: UuTheme.textSecondary,
                    ),
                    if (_peer.platform.isNotEmpty) ...[
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          _peer.platform,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: UuTheme.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(width: 8),
                    _StatusPill(online: _online),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: _showMoreMenu,
            icon: Icon(Icons.more_vert, color: UuTheme.textPrimary),
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
                UuPeerPlatformIcon.iconFor(_peer.platform),
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
                    _online ? translate('Enter desktop') : translate('Device offline'),
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
      (Icons.desktop_windows_outlined, translate('Enter desktop'), _enterDesktop),
      (Icons.swap_horiz, translate('File transfer'), _openFileTransfer),
      (Icons.play_circle_outline, translate('View only'), _openViewOnly),
      (Icons.terminal, translate('Terminal'), _openTerminal),
    ];
    return Container(
      height: 86,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: UuColors.surface,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          for (var i = 0; i < actions.length; i++) ...[
            if (i > 0)
              SizedBox(
                height: 34,
                child: VerticalDivider(width: 1, color: UuColors.divider),
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
                      style: TextStyle(
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

  Widget _infoCard() {
    return UuCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        children: [
          _infoRow(
            translate('Device ID'),
            _peer.id,
            trailing: IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: translate('Copy ID'),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: _peer.id));
                uuToast(translate('Device ID copied'));
              },
              icon: Icon(Icons.copy_rounded,
                  size: 18, color: UuColors.textSecondary),
            ),
          ),
          _infoDivider(),
          _infoRow(
            translate('Alias'),
            _peer.alias.isEmpty ? translate('Not set') : _peer.alias,
            trailing: IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: translate('Rename'),
              onPressed: _rename,
              icon: Icon(Icons.edit_outlined,
                  size: 18, color: UuColors.textSecondary),
            ),
          ),
          if (_peer.platform.isNotEmpty) ...[
            _infoDivider(),
            _infoRow(translate('Platform'), _peer.platform),
          ],
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value, {Widget? trailing}) {
    return SizedBox(
      height: 46,
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(
              color: UuColors.textSecondary,
              fontSize: 13,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: UuColors.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          if (trailing != null) trailing,
        ],
      ),
    );
  }

  Widget _infoDivider() => Divider(
        height: 0.5,
        thickness: 0.5,
        color: UuColors.divider,
      );

  Future<void> _rename() async {
    final renamed = await showUuRenameDevice(
      context,
      id: _peer.id,
      currentAlias: _peer.alias,
    );
    if (renamed != null && mounted) {
      _peer.alias = renamed;
      setState(() {});
    }
  }

  Future<void> _deleteDevice() async {
    final inAddressBook = _inAddressBook;
    final ok = await showUuConfirm(
      context,
      title: translate('Delete device'),
      message: inAddressBook
          ? translate('This will remove {$_name} from your account devices; you will need to add it again.')
          : translate('This will remove {$_name} from recent connections.'),
      confirmText: translate('Delete'),
      danger: true,
    );
    if (!ok || !mounted) return;
    var deleted = false;
    if (inAddressBook) {
      deleted = await gFFI.abModel.deletePeers([_peer.id]);
    } else {
      await bind.mainRemovePeer(id: _peer.id);
      deleted = true;
    }
    if (!mounted) return;
    if (deleted) {
      uuToast(translate('Deleted'));
      Navigator.of(context).maybePop();
    } else {
      uuToast(translate('Delete failed. Please try again later.'));
    }
  }

  void _offlineTip() {
    uuToast(translate('Device is offline'));
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
    final isRestart = action == UuSessionIntent.restart;
    final ok = await showUuConfirm(
      context,
      title: isRestart
          ? translate('Restart device')
          : translate('Shut down device'),
      message: isRestart
          ? translate('Are you sure you want to restart {$_name}?')
          : translate('Are you sure you want to shut down {$_name}?'),
      confirmText: isRestart ? translate('Restart') : translate('Shut down'),
      danger: true,
    );
    if (!ok || !mounted) {
      return;
    }
    UuSessionIntent.schedule(_peer.id, action);
    await connect(context, _peer.id, password: uuPeerPassword(_peer));
  }

  void _showMoreMenu() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: UuColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.grid_view, size: 22),
              title: Text(translate('More tools')),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _openMoreTools();
              },
            ),
            ListTile(
              leading: const Icon(Icons.copy_rounded, size: 22),
              title: Text(translate('Copy device ID')),
              onTap: () {
                Navigator.of(sheetContext).pop();
                Clipboard.setData(ClipboardData(text: _peer.id));
                uuToast(translate('Device ID copied'));
              },
            ),
            ListTile(
              leading: const Icon(Icons.refresh_rounded, size: 22),
              title: Text(translate('Refresh status')),
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
    UuColors.apply(context);
    return Scaffold(
      backgroundColor: UuColors.background,
      appBar: AppBar(
        backgroundColor: UuColors.surface,
        foregroundColor: UuTheme.textPrimary,
        elevation: 0,
        centerTitle: true,
        title: Text(translate('More tools')),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: UuColors.surface,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              children: [
                _row(context, Icons.swap_horiz, translate('File transfer'),
                    state._openFileTransfer),
                _divider(),
                _row(context, Icons.play_circle_outline, translate('View only'),
                    state._openViewOnly),
                _divider(),
                _row(context, Icons.terminal, translate('Terminal'), state._openTerminal),
                _divider(),
                _row(context, Icons.restart_alt_rounded, translate('Restart'),
                    () => state._confirmPower(UuSessionIntent.restart)),
                _divider(),
                _row(context, Icons.power_settings_new_rounded, translate('Shut down'),
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
                style: TextStyle(
                  color: UuTheme.textPrimary,
                  fontSize: 17,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            Icon(Icons.chevron_right,
                size: 22, color: UuColors.textTertiary),
          ],
        ),
      ),
    );
  }

  Widget _divider() => Divider(
        height: 0.5,
        thickness: 0.5,
        indent: 56,
        endIndent: 16,
        color: UuColors.divider,
      );
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: UuColors.surface,
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
    final color = online ? UuColors.success : UuColors.textTertiary;
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
            online ? translate('Online') : translate('Offline'),
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
