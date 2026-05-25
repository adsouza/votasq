import 'dart:async';

import 'package:client/l10n/l10n.dart';
import 'package:client/settings/cubit/text_scale_cubit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Convenience helper — shows [TextSizeDialog] as a modal.
Future<void> showTextSizeDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => const TextSizeDialog(),
  );
}

/// A dialog with a 5-step discrete slider for picking the app-wide text
/// scale factor. Changes are applied live via [TextScaleCubit] so the
/// dialog's own text (and everything beneath it) re-scales while the user
/// drags — WYSIWYG preview without a separate preview pane.
class TextSizeDialog extends StatelessWidget {
  const TextSizeDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final materialL10n = MaterialLocalizations.of(context);
    const scales = TextScaleCubit.allowedScales;
    final labels = [
      l10n.textSizeOptionSmall,
      l10n.textSizeOptionDefault,
      l10n.textSizeOptionLarge,
      l10n.textSizeOptionLarger,
      l10n.textSizeOptionLargest,
    ];
    return AlertDialog(
      title: Text(l10n.textSizeDialogTitle),
      content: BlocBuilder<TextScaleCubit, double>(
        builder: (context, scale) {
          final index = _closestIndex(scale, scales);
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                labels[index],
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Slider(
                max: (scales.length - 1).toDouble(),
                divisions: scales.length - 1,
                value: index.toDouble(),
                label: labels[index],
                onChanged: (value) {
                  final i = value.round();
                  unawaited(
                    context.read<TextScaleCubit>().setScale(scales[i]),
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

  /// Find the index in [scales] whose value is closest to [target]. Used
  /// for the case where the cubit holds a value outside the discrete steps
  /// (theoretically possible if set programmatically) — the slider snaps
  /// to the nearest step rather than crashing on `indexOf` returning -1.
  static int _closestIndex(double target, List<double> scales) {
    var best = 0;
    var bestDelta = (target - scales[0]).abs();
    for (var i = 1; i < scales.length; i++) {
      final delta = (target - scales[i]).abs();
      if (delta < bestDelta) {
        best = i;
        bestDelta = delta;
      }
    }
    return best;
  }
}
