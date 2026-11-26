import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../models/model.dart';

/// 把远控画面投到 iOS 系统画中画悬浮窗，可浮在其他 App 之上继续实时显示。
class UuPip {
  UuPip._();

  static final UuPip instance = UuPip._();

  static const _channel = MethodChannel('uu/pip');

  static bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  bool _active = false;
  bool get active => _active;

  Timer? _timer;
  bool _pushing = false;
  FFI? _ffi;
  ValueChanged<String>? _onStopped;

  /// 返回是否成功进入画中画。失败时调用方可以退回 App 内小窗。
  Future<bool> start(FFI ffi, {ValueChanged<String>? onStopped}) async {
    if (!supported) return false;
    if (_active) return true;
    _channel.setMethodCallHandler(_handleCall);
    bool nativeSupported = false;
    try {
      nativeSupported =
          await _channel.invokeMethod<bool>('isSupported') ?? false;
    } catch (_) {
      return false;
    }
    if (!nativeSupported) return false;
    _ffi = ffi;
    _onStopped = onStopped;
    _timer?.cancel();
    _timer = Timer.periodic(
        const Duration(milliseconds: 100), (_) => _pushFrame());
    // 先送一帧，画中画窗口才有内容可显示。
    for (var i = 0; i < 6; i++) {
      if (await _pushFrame()) break;
      await Future.delayed(const Duration(milliseconds: 80));
    }
    bool started = false;
    try {
      started = await _channel.invokeMethod<bool>('startPip') ?? false;
    } catch (_) {
      started = false;
    }
    if (!started) {
      _stopPump();
      _onStopped = null;
      return false;
    }
    _active = true;
    return true;
  }

  Future<void> stop() async {
    if (!supported) return;
    _stopPump();
    _active = false;
    _onStopped = null;
    try {
      await _channel.invokeMethod<void>('stopPip');
    } catch (_) {}
  }

  void _stopPump() {
    _timer?.cancel();
    _timer = null;
    _ffi = null;
  }

  Future<dynamic> _handleCall(MethodCall call) async {
    if (call.method != 'pipStopped') return null;
    final reason =
        call.arguments is String ? call.arguments as String : 'closed';
    final wasActive = _active;
    _stopPump();
    _active = false;
    final onStopped = _onStopped;
    _onStopped = null;
    if (wasActive) onStopped?.call(reason);
    return null;
  }

  Future<bool> _pushFrame() async {
    final ffi = _ffi;
    if (_pushing || ffi == null) return false;
    final image = ffi.imageModel.image;
    if (image == null) return false;
    _pushing = true;
    ui.Image? clone;
    try {
      // 帧到达时会替换并释放旧图，先克隆一份再异步编码。
      clone = image.clone();
      final encoded = await _encode(clone);
      if (encoded == null) return false;
      await _channel.invokeMethod<void>('pushFrame', encoded);
      return true;
    } catch (_) {
      return false;
    } finally {
      clone?.dispose();
      _pushing = false;
    }
  }

  Future<Map<String, Object>?> _encode(ui.Image image) async {
    const maxSide = 480.0;
    final srcW = image.width.toDouble();
    final srcH = image.height.toDouble();
    final scale = math.min(1.0, maxSide / math.max(srcW, srcH));
    final width = math.max(1, (srcW * scale).round());
    final height = math.max(1, (srcH * scale).round());
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawImageRect(
      image,
      ui.Rect.fromLTWH(0, 0, srcW, srcH),
      ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      ui.Paint()..filterQuality = ui.FilterQuality.low,
    );
    final picture = recorder.endRecording();
    ui.Image? scaled;
    try {
      scaled = await picture.toImage(width, height);
      final data = await scaled.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (data == null) return null;
      return {
        'bytes': data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        'width': width,
        'height': height,
      };
    } finally {
      scaled?.dispose();
      picture.dispose();
    }
  }
}
