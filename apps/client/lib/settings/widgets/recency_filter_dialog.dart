import 'dart:async';

import 'package:client/l10n/l10n.dart';
import 'package:client/settings/cubit/recency_filter_cubit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Convenience helper — shows [RecencyFilterDialog] as a modal.
Future<void> showRecencyFilterDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => const RecencyFilterDialog(),
  );
}

/// A dialog with a seven-step discrete slider for limiting the listing to
/// problems updated within the last N days. The leftmost stop ("any time")
/// turns the filter off. Changes apply live via [RecencyFilterCubit] so the
/// label updates as the user drags.
class RecencyFilterDialog extends StatelessWidget {
  const RecencyFilterDialog({super.key});

  /// Localized label for a given day threshold — `0` reads as "any time",
  /// everything else as a pluralized "within N days".
  static String labelFor(AppLocalizations l10n, int days) => days == 0
      ? l10n.recencyFilterAnyTime
      : l10n.recencyFilterWithinDays(days);

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final materialL10n = MaterialLocalizations.of(context);
    const days = RecencyFilterCubit.allowedDays;
    return AlertDialog(
      title: Text(l10n.recencyFilterDialogTitle),
      content: BlocBuilder<RecencyFilterCubit, int>(
        builder: (context, current) {
          final index = _closestIndex(current, days);
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                labelFor(l10n, days[index]),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Slider(
                max: (days.length - 1).toDouble(),
                divisions: days.length - 1,
                value: index.toDouble(),
                label: labelFor(l10n, days[index]),
                onChanged: (value) {
                  final i = value.round();
                  unawaited(
                    context.read<RecencyFilterCubit>().setMaxAgeDays(days[i]),
                  );
                },
              ),
            ],
          );
        },
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(materialL10n.okButtonLabel),
        ),
      ],
    );
  }

  /// Find the index in [days] whose value is closest to [target]. Guards the
  /// case where the cubit holds a value outside the discrete steps (e.g. set
  /// programmatically) — the slider snaps to the nearest step rather than
  /// crashing on `indexOf` returning -1.
  static int _closestIndex(int target, List<int> days) {
    var best = 0;
    var bestDelta = (target - days[0]).abs();
    for (var i = 1; i < days.length; i++) {
      final delta = (target - days[i]).abs();
      if (delta < bestDelta) {
        best = i;
        bestDelta = delta;
      }
    }
    return best;
  }
}
