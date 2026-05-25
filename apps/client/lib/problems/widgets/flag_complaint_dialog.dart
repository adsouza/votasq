import 'package:client/l10n/l10n.dart';
import 'package:flutter/material.dart';

/// Confirm dialog asking the user to flag a problem as abusive. Returns
/// `true` if the user confirmed, `false` (or `null` on dismissal) otherwise.
///
/// Shared between the listing and the detail page so the wording stays in
/// lockstep — both surfaces describe the same action with the same copy.
Future<bool?> showFlagComplaintConfirmDialog(BuildContext context) {
  final l10n = context.l10n;
  return showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l10n.flagComplaintDialogTitle),
      content: Text(l10n.flagComplaintDialogBody),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.flagComplaintDialogCancel),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l10n.flagComplaintDialogConfirm),
        ),
      ],
    ),
  );
}
