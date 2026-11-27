import 'package:flutter/foundation.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/models/model.dart';
import 'package:flutter_hbb/models/platform_model.dart';

import 'uu_keymap.dart';

/// Built-in rendezvous/relay server for this client.
const uuDefaultServer = '120.26.144.120';

/// Public key of the built-in server (`id_ed25519.pub`).
const uuDefaultServerKey = 'RVLGia9OPjX4YfLTkL8PolQ82aznKixdV3D8ZAUE1yQ=';

/// Applies the built-in server only when the user has not configured one, so
/// settings changed from the UI are kept.
Future<void> applyUuServerDefaults() async {
  if (bind
      .mainGetOptionSync(key: 'custom-rendezvous-server')
      .trim()
      .isNotEmpty) {
    return;
  }
  await bind.mainSetOption(
    key: 'custom-rendezvous-server',
    value: uuDefaultServer,
  );
  await bind.mainSetOption(key: 'relay-server', value: uuDefaultServer);
  await bind.mainSetOption(key: 'key', value: uuDefaultServerKey);
}

/// 像 UU 远程一样默认在“鼠标指针”模式下显示滚轮和左右键，
/// 用户手动关掉后不再覆盖。
Future<void> applyUuInputDefaults() async {
  if (bind.mainGetLocalOption(key: kOptionShowVirtualMouse).isEmpty) {
    await bind.mainSetLocalOption(key: kOptionShowVirtualMouse, value: 'Y');
  }
  // 首次升级到触控板方案时，清掉旧版遗留的屏幕触控状态，避免同时显示
  // 触摸光标和触控板指针。
  if (bind.mainGetLocalOption(key: uuInputModeOption).isEmpty) {
    await bind.mainSetLocalOption(key: uuInputModeOption, value: 'trackpad');
    await bind.mainSetLocalOption(key: kOptionTouchMode, value: 'N');
  }
}

/// 桌面远控默认按窗口自适应缩放，避免 Retina 高分屏画面大于窗口、
/// 指针移动时画面跟着平移。用户手动选过缩放方式（非空）时保持其选择。
Future<void> applyUuViewStyle(FFI ffi) async {
  final style = await bind.sessionGetViewStyle(sessionId: ffi.sessionId);
  if (style == null || style.isNotEmpty) {
    return;
  }
  await bind.sessionSetViewStyle(
      sessionId: ffi.sessionId, value: kRemoteViewStyleAdaptive);
  await ffi.canvasModel.updateViewStyle();
}

/// “启用按键映射”：键盘按键直接以电脑按键发送，而不是走手机输入法。
const uuKeyMappingOption = 'uu-key-mapping';

bool uuKeyMappingEnabled() =>
    bind.mainGetLocalOption(key: uuKeyMappingOption) == 'Y';

Future<void> setUuKeyMapping(bool on) {
  uuKeymapHidden.value = false;
  return bind.mainSetLocalOption(
      key: uuKeyMappingOption, value: on ? 'Y' : 'N');
}

/// 移动端远控输入方式：触控板（默认）、屏幕触控、鼠标指针。
enum UuInputMode { touch, mouse, trackpad }

const uuInputModeOption = 'uu-input-mode';

UuInputMode uuInputMode() {
  switch (bind.mainGetLocalOption(key: uuInputModeOption)) {
    case 'touch':
      return UuInputMode.touch;
    case 'mouse':
      return UuInputMode.mouse;
    default:
      return UuInputMode.trackpad;
  }
}

final ValueNotifier<UuInputMode> uuInputModeNotifier =
    ValueNotifier(uuInputMode());

Future<void> setUuInputMode(UuInputMode mode) {
  uuInputModeNotifier.value = mode;
  return bind.mainSetLocalOption(key: uuInputModeOption, value: mode.name);
}

/// 触控板指针速度。
enum UuPointerSpeed { slow, normal, fast }

const uuPointerSpeedOption = 'uu-pointer-speed';

UuPointerSpeed uuPointerSpeed() {
  switch (bind.mainGetLocalOption(key: uuPointerSpeedOption)) {
    case 'slow':
      return UuPointerSpeed.slow;
    case 'fast':
      return UuPointerSpeed.fast;
    default:
      return UuPointerSpeed.normal;
  }
}

final ValueNotifier<UuPointerSpeed> uuPointerSpeedNotifier =
    ValueNotifier(uuPointerSpeed());

Future<void> setUuPointerSpeed(UuPointerSpeed speed) {
  uuPointerSpeedNotifier.value = speed;
  return bind.mainSetLocalOption(
      key: uuPointerSpeedOption, value: speed.name);
}

/// 远控窗口默认使用 UU 顶栏，隐藏 stock 浮动工具栏。
const uuRemoteToolbarOption = 'uu-show-remote-toolbar';

final ValueNotifier<bool> uuRemoteToolbarVisible = ValueNotifier<bool>(
    bind.mainGetLocalOption(key: uuRemoteToolbarOption) == 'Y');

Future<void> setUuRemoteToolbarVisible(bool visible) {
  uuRemoteToolbarVisible.value = visible;
  return bind.mainSetLocalOption(
      key: uuRemoteToolbarOption, value: visible ? 'Y' : 'N');
}

/// 小窗模式打开期间不再发起新的远控，同一时间只维持一个会话。
final ValueNotifier<bool> uuMiniWindowOpen = ValueNotifier<bool>(false);
