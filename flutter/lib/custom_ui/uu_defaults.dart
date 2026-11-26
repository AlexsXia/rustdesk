import 'package:flutter/foundation.dart';
import 'package:flutter_hbb/consts.dart';
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
  if (bind.mainGetLocalOption(key: kOptionShowVirtualMouse).isNotEmpty) {
    return;
  }
  await bind.mainSetLocalOption(key: kOptionShowVirtualMouse, value: 'Y');
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

/// 小窗模式打开期间不再发起新的远控，同一时间只维持一个会话。
final ValueNotifier<bool> uuMiniWindowOpen = ValueNotifier<bool>(false);
