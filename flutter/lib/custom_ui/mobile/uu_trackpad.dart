import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/models/input_model.dart';
import 'package:flutter_hbb/models/model.dart';

import '../uu_defaults.dart';

/// UU 触控板：单指滑动移动指针、轻点左键、双指滚动、双指轻点右键、
/// 长按后拖动、双指捏合缩放画面。直接处理原始指针事件，避免单双击识别器
/// 带来的点击延迟。
class UuTrackpadRegion extends StatefulWidget {
  const UuTrackpadRegion({super.key, required this.ffi, required this.child});

  final FFI ffi;
  final Widget child;

  @override
  State<UuTrackpadRegion> createState() => _UuTrackpadRegionState();
}

class _UuTrackpadRegionState extends State<UuTrackpadRegion> {
  static const _slop = 8.0;
  static const _scrollStep = 10.0;
  static const _longPressDelay = Duration(milliseconds: 420);
  static const _twoFingerTapTime = Duration(milliseconds: 300);

  final Map<int, Offset> _pointers = {};
  Offset _downPosition = Offset.zero;
  Offset _lastPosition = Offset.zero;
  Timer? _longPress;
  bool _moved = false;
  bool _dragging = false;
  bool _dragArmed = false;

  bool _twoFinger = false;
  int _twoFingerMode = 0; // 0 未决定，1 滚动，2 缩放，3 平移画面
  Offset _twoStartCentroid = Offset.zero;
  double _twoStartDistance = 0;
  Offset _lastCentroid = Offset.zero;
  double _lastDistance = 0;
  DateTime _twoFingerStart = DateTime.now();
  double _scrollAccum = 0;

  InputModel get _input => widget.ffi.inputModel;

  Offset _centroid() {
    final points = _pointers.values.toList();
    if (points.isEmpty) return Offset.zero;
    if (points.length == 1) return points.first;
    return (points[0] + points[1]) / 2;
  }

  double _distance() {
    final points = _pointers.values.toList();
    if (points.length < 2) return 0;
    return (points[0] - points[1]).distance;
  }

  Offset _accelerate(Offset delta) {
    final base = switch (uuPointerSpeedNotifier.value) {
      UuPointerSpeed.slow => 1.0,
      UuPointerSpeed.normal => 1.5,
      UuPointerSpeed.fast => 2.0,
    };
    final speed = base + math.min(delta.distance / 26, 1.0) * base;
    return delta * speed;
  }

  bool _isTouchKind(PointerEvent event) {
    return event.kind == PointerDeviceKind.touch ||
        event.kind == PointerDeviceKind.stylus ||
        event.kind == PointerDeviceKind.invertedStylus;
  }

  void _onDown(PointerDownEvent event) {
    if (!_isTouchKind(event)) return;
    _pointers[event.pointer] = event.localPosition;
    if (_pointers.length == 1) {
      _twoFinger = false;
      _moved = false;
      _dragging = false;
      _dragArmed = false;
      _downPosition = event.localPosition;
      _lastPosition = event.localPosition;
      _longPress?.cancel();
      _longPress = Timer(_longPressDelay, _startDrag);
      return;
    }
    if (_pointers.length == 2) {
      _longPress?.cancel();
      _dragArmed = false;
      if (_dragging) {
        _dragging = false;
        unawaited(_input.tapUp(MouseButtons.left));
      }
      _twoFinger = true;
      _moved = false;
      _twoFingerMode = 0;
      _twoFingerStart = DateTime.now();
      _twoStartCentroid = _centroid();
      _twoStartDistance = _distance();
      _lastCentroid = _twoStartCentroid;
      _lastDistance = _twoStartDistance;
      _scrollAccum = 0;
    }
  }

  void _startDrag() {
    if (!mounted || _pointers.length != 1 || _moved || _dragging) return;
    _dragArmed = true;
    HapticFeedback.mediumImpact();
  }

  void _onMove(PointerMoveEvent event) {
    if (!_pointers.containsKey(event.pointer)) return;
    _pointers[event.pointer] = event.localPosition;
    if (_pointers.length >= 2) {
      _moveTwoFingers();
      return;
    }
    final delta = event.localPosition - _lastPosition;
    _lastPosition = event.localPosition;
    if (!_moved && (event.localPosition - _downPosition).distance > _slop) {
      _moved = true;
      _longPress?.cancel();
    }
    if (_dragArmed && !_dragging) {
      _dragging = true;
      unawaited(_input.tapDown(MouseButtons.left));
    }
    if (!_moved && !_dragging) return;
    final moved = _accelerate(delta);
    if (moved != Offset.zero) {
      unawaited(widget.ffi.cursorModel.updatePan(moved, Offset.zero, false));
    }
  }

  void _moveTwoFingers() {
    final centroid = _centroid();
    final distance = _distance();
    if (distance <= 0 || _lastDistance <= 0) return;
    if (_twoFingerMode == 0) {
      final scaleChange = (distance / _twoStartDistance - 1).abs();
      final scrollChange = (centroid.dy - _twoStartCentroid.dy).abs();
      if (scaleChange > 0.10) {
        _twoFingerMode = 2;
      } else if (scrollChange > _slop) {
        _twoFingerMode =
            widget.ffi.canvasModel.scale > 1.01 ? 3 : 1;
      } else {
        _lastCentroid = centroid;
        _lastDistance = distance;
        return;
      }
    }
    if (_twoFingerMode == 1) {
      _scrollAccum += centroid.dy - _lastCentroid.dy;
      while (_scrollAccum > _scrollStep) {
        unawaited(_input.scroll(1));
        _scrollAccum -= _scrollStep;
      }
      while (_scrollAccum < -_scrollStep) {
        unawaited(_input.scroll(-1));
        _scrollAccum += _scrollStep;
      }
    } else if (_twoFingerMode == 2 &&
        widget.ffi.imageModel.image != null) {
      widget.ffi.canvasModel.updateScale(distance / _lastDistance, centroid);
      widget.ffi.canvasModel.panX(centroid.dx - _lastCentroid.dx);
      widget.ffi.canvasModel.panY(centroid.dy - _lastCentroid.dy);
    } else if (_twoFingerMode == 3) {
      widget.ffi.canvasModel.panX(centroid.dx - _lastCentroid.dx);
      widget.ffi.canvasModel.panY(centroid.dy - _lastCentroid.dy);
    }
    _lastCentroid = centroid;
    _lastDistance = distance;
  }

  void _onUp(PointerUpEvent event) {
    if (!_pointers.containsKey(event.pointer)) return;
    _pointers.remove(event.pointer);
    _longPress?.cancel();
    if (_twoFinger) {
      if (_pointers.isEmpty) {
        final quick =
            DateTime.now().difference(_twoFingerStart) < _twoFingerTapTime;
        if (_twoFingerMode == 0 && quick && !_moved) {
          HapticFeedback.selectionClick();
          unawaited(_input.tap(MouseButtons.right));
        }
        _resetTwoFinger();
      } else {
        _lastPosition = _pointers.values.first;
        _lastCentroid = _centroid();
        _lastDistance = _distance();
      }
      return;
    }
    if (_dragging) {
      _dragging = false;
      _dragArmed = false;
      unawaited(_input.tapUp(MouseButtons.left));
      return;
    }
    if (_dragArmed) {
      _dragArmed = false;
      HapticFeedback.selectionClick();
      unawaited(_input.tap(MouseButtons.right));
      return;
    }
    if (!_moved) {
      HapticFeedback.selectionClick();
      unawaited(_input.tap(MouseButtons.left));
    }
  }

  void _onCancel(PointerCancelEvent event) {
    _pointers.remove(event.pointer);
    _longPress?.cancel();
    _dragArmed = false;
    if (_dragging) {
      _dragging = false;
      unawaited(_input.tapUp(MouseButtons.left));
    }
    if (_twoFinger) {
      _twoFingerMode = -1;
      _moved = true;
      if (_pointers.isNotEmpty) {
        _lastPosition = _pointers.values.first;
      }
    }
    if (_pointers.isEmpty) {
      _resetTwoFinger();
    }
  }

  void _resetTwoFinger() {
    _twoFinger = false;
    _twoFingerMode = 0;
    _moved = false;
    _dragArmed = false;
    _scrollAccum = 0;
  }

  @override
  void dispose() {
    _longPress?.cancel();
    if (_dragging) {
      unawaited(_input.tapUp(MouseButtons.left));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: _onDown,
      onPointerMove: _onMove,
      onPointerUp: _onUp,
      onPointerCancel: _onCancel,
      child: widget.child,
    );
  }
}
