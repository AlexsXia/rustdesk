import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart' show translate;
import 'package:flutter_hbb/models/user_model.dart';

import 'uu_feedback.dart';

/// Pulls the account address book and reports the result.
Future<void> uuRefreshDevices() async {
  await UserModel.updateOtherModels();
  uuToast(translate('Devices refreshed'));
}

/// Asks before signing out of the account.
Future<bool> uuConfirmLogout(BuildContext context) {
  return showUuConfirm(
    context,
    title: translate('Sign out'),
    message: translate("After signing out, this account's devices are removed from the list. This device can still be controlled remotely."),
    confirmText: translate('Exit'),
    danger: true,
  );
}
