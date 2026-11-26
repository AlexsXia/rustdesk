import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/models/platform_model.dart';

/// One-shot power action to run as soon as the next session to a peer is up.
/// The device page has no session yet, so the action waits for the remote page
/// to report its first image, then runs against that session.
class UuSessionIntent {
  UuSessionIntent._();

  static const restart = 'restart';
  static const shutdown = 'shutdown';

  static final Map<String, String> _pending = {};

  static void schedule(String peerId, String action) {
    _pending[peerId] = action;
  }

  static void runIfPending(String peerId) {
    final action = _pending.remove(peerId);
    if (action == null) {
      return;
    }
    final sessionId = gFFI.sessionId;
    switch (action) {
      case restart:
        bind.sessionRestartRemoteDevice(sessionId: sessionId);
        break;
      case shutdown:
        bind.sessionShutdownRemoteDevice(sessionId: sessionId);
        break;
    }
  }
}
