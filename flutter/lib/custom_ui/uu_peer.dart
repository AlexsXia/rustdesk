import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/models/peer_model.dart';
import 'package:flutter_hbb/models/platform_model.dart';

/// The account-wide secret that every signed-in device uses as its permanent
/// password. Empty until this device has synced it with the account server.
String uuAccountDevicePassword() =>
    bind.mainGetLocalOption(key: 'uu-device-secret');

/// Password to hand to `connect()` for [peer]: the peer's own saved password
/// first, then the account secret for devices of the same account.
String? uuPeerPassword(Peer peer) {
  if (peer.password.isNotEmpty) {
    return peer.password;
  }
  if (!gFFI.abModel.currentAbPeers.any((p) => p.id == peer.id)) {
    return null;
  }
  final secret = uuAccountDevicePassword();
  return secret.isEmpty ? null : secret;
}

String uuPeerName(Peer peer) {
  if (peer.alias.isNotEmpty) {
    return peer.alias;
  }
  if (peer.hostname.isNotEmpty) {
    return peer.hostname;
  }
  return peer.id;
}

String uuPeerSubtitle(Peer peer) {
  final parts = <String>[];
  if (peer.username.isNotEmpty) {
    parts.add(peer.username);
  }
  if (peer.platform.isNotEmpty) {
    parts.add(peer.platform);
  }
  if (parts.isEmpty) {
    return peer.id;
  }
  return parts.join(' · ');
}
