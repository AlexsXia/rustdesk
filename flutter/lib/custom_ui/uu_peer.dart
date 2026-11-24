import 'package:flutter_hbb/models/peer_model.dart';

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
