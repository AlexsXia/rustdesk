import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

/// 保存或删除壁纸预览后自增，设备卡片据此刷新。
final ValueNotifier<int> uuWallpaperRevision = ValueNotifier<int>(0);

Directory? _dir;

Future<Directory?> _wallpaperDir() async {
  if (_dir != null) return _dir;
  try {
    final support = await getApplicationSupportDirectory();
    final dir = Directory('${support.path}/uu_wallpapers');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _dir = dir;
    return dir;
  } catch (_) {
    return null;
  }
}

String _fileName(String peerId) =>
    '${peerId.replaceAll(RegExp(r'[^0-9a-zA-Z_.-]'), '_')}.jpg';

/// 把一帧远端画面压成小图存为该设备的预览图，下次连接时覆盖。
Future<void> saveUuWallpaper(String peerId, ui.Image source) async {
  final dir = await _wallpaperDir();
  if (dir == null) return;
  const maxWidth = 960;
  final scale = source.width > maxWidth ? maxWidth / source.width : 1.0;
  final width = (source.width * scale).round().clamp(1, source.width);
  final height = (source.height * scale).round().clamp(1, source.height);
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawImageRect(
    source,
    Rect.fromLTWH(0, 0, source.width.toDouble(), source.height.toDouble()),
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    Paint()..filterQuality = FilterQuality.medium,
  );
  final picture = recorder.endRecording();
  final scaled = await picture.toImage(width, height);
  final data = await scaled.toByteData(format: ui.ImageByteFormat.rawRgba);
  picture.dispose();
  scaled.dispose();
  if (data == null) return;
  final frame = img.Image.fromBytes(
    width: width,
    height: height,
    bytes: data.buffer,
    numChannels: 4,
    rowStride: width * 4,
    order: img.ChannelOrder.rgba,
  );
  final file = File('${dir.path}/${_fileName(peerId)}');
  await file.writeAsBytes(img.encodeJpg(frame, quality: 80), flush: true);
  await FileImage(file).evict();
  uuWallpaperRevision.value++;
}

/// 设备卡片上的预览图；没有保存过壁纸时显示 [fallback]。
class UuWallpaperLayer extends StatefulWidget {
  const UuWallpaperLayer({
    super.key,
    required this.peerId,
    required this.fallback,
    this.fit = BoxFit.cover,
  });

  final String peerId;
  final Widget fallback;
  final BoxFit fit;

  @override
  State<UuWallpaperLayer> createState() => _UuWallpaperLayerState();
}

class _UuWallpaperLayerState extends State<UuWallpaperLayer> {
  File? _file;
  int _loadedRevision = -1;

  @override
  void initState() {
    super.initState();
    uuWallpaperRevision.addListener(_refresh);
    _refresh();
  }

  @override
  void didUpdateWidget(UuWallpaperLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.peerId != widget.peerId) {
      _refresh();
    }
  }

  @override
  void dispose() {
    uuWallpaperRevision.removeListener(_refresh);
    super.dispose();
  }

  Future<void> _refresh() async {
    final revision = uuWallpaperRevision.value;
    if (revision == _loadedRevision) return;
    _loadedRevision = revision;
    final dir = await _wallpaperDir();
    final file = dir == null
        ? null
        : File('${dir.path}/${_fileName(widget.peerId)}');
    final exists = file != null && await file.exists();
    if (!mounted || revision != uuWallpaperRevision.value) return;
    setState(() => _file = exists ? file : null);
  }

  @override
  Widget build(BuildContext context) {
    final file = _file;
    if (file == null) return widget.fallback;
    return Image.file(
      file,
      fit: widget.fit,
      width: double.infinity,
      height: double.infinity,
      gaplessPlayback: true,
      errorBuilder: (_, __, ___) => widget.fallback,
    );
  }
}
