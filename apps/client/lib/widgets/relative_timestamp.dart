import 'package:flutter/material.dart';
import 'package:timeago/timeago.dart' as timeago;

/// A subtle, localized relative-time label ("9 hours ago") with a tooltip
/// exposing the exact date and time.
///
/// The phrasing is produced by [timeago] using the active locale's
/// `languageCode`; the messages for every supported locale are registered
/// once in `bootstrap()` via `registerTimeagoLocales()`. The text is
/// recomputed on each build (there's no per-second timer), which is fine for
/// the lists this appears in — they rebuild when their data stream re-emits.
///
/// Note: [timeago] buckets durations as minutes → hours → days → months →
/// years, with no "weeks" step, so e.g. 16 days renders as "16 days ago".
///
/// An optional [label] is prefixed to the phrase to disambiguate when several
/// timestamps sit together — e.g. label "Edited" yields "Edited 1 hour ago".
/// Keep it a single localized word/phrase; it joins the relative phrase in one
/// [Text] so text direction and wrapping stay correct.
class RelativeTimestamp extends StatelessWidget {
  const RelativeTimestamp({required this.timestamp, this.label, super.key});

  final DateTime timestamp;

  /// Optional localized prefix, e.g. `l10n.problemEditedLabel`.
  final String? label;

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context).languageCode;
    final materialL10n = MaterialLocalizations.of(context);
    final absolute =
        '${materialL10n.formatFullDate(timestamp)} '
        '${materialL10n.formatTimeOfDay(TimeOfDay.fromDateTime(timestamp))}';
    final theme = Theme.of(context);

    final relative = timeago.format(timestamp, locale: locale);
    final text = label == null ? relative : '$label $relative';

    return Tooltip(
      message: absolute,
      child: Text(
        text,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
