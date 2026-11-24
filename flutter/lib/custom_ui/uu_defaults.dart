import 'package:flutter_hbb/models/platform_model.dart';

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
