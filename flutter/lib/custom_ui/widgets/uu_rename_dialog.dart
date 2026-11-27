import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/models/platform_model.dart';

import 'uu_feedback.dart';

/// Renames a device: the alias is saved locally for recent entries and pushed
/// to the account address book when the device belongs to it.
/// Returns the new alias, or null when cancelled.
Future<String?> showUuRenameDevice(
  BuildContext context, {
  required String id,
  required String currentAlias,
}) async {
  final controller = TextEditingController(text: currentAlias);
  final alias = await showUuDialog<String>(
    context,
    title: translate('Rename device'),
    content: UuTextField(
      controller: controller,
      hint: translate('Device name'),
      autofocus: true,
    ),
    actions: [
      uuDialogTextButton(translate('Cancel'), () => Navigator.of(context).pop()),
      uuDialogFilledButton(
        translate('Save'),
        () => Navigator.of(context).pop(controller.text.trim()),
      ),
    ],
  );
  controller.dispose();
  if (alias == null || alias == currentAlias) {
    return null;
  }
  if (gFFI.abModel.currentAbPeers.any((peer) => peer.id == id)) {
    await gFFI.abModel.changeAlias(id: id, alias: alias);
  }
  await bind.mainSetPeerAlias(id: id, alias: alias);
  bind.mainLoadRecentPeers();
  uuToast(alias.isEmpty ? translate('Default name restored') : translate('Renamed to {$alias}'));
  return alias;
}
