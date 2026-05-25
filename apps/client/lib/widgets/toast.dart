import 'package:flutter/material.dart';
import 'package:toastification/toastification.dart';

// Translucent light-green / light-orange surfaces with deep-indigo text.
// Translucency survives toastification's MaterialColor conversion because the
// primary channel keeps the original alpha; only the generated swatch shades
// are opaque, and the toast container paints from the primary.
final Color _successBackground = Colors.green.shade100.withValues(alpha: 0.85);
final Color _errorBackground = Colors.orange.shade100.withValues(alpha: 0.85);
const _foregroundColor = Color(0xFF1A237E); // Material indigo.shade900.

/// Shows a centered success toast with [message] (light-green surface).
/// Use for confirmations of completed actions (save succeeded, link copied,
/// feedback sent, etc.). For failures, use [showErrorToast] instead so the
/// background hue signals the outcome.
ToastificationItem showSuccessToast(
  String message, {
  Duration duration = const Duration(seconds: 4),
}) => _showToast(message, _successBackground, duration);

/// Shows a centered error toast with [message] (light-orange surface).
/// Use for failures the user should notice (save error, language mismatch,
/// link/unlink failure, etc.). For successes, use [showSuccessToast].
ToastificationItem showErrorToast(
  String message, {
  Duration duration = const Duration(seconds: 4),
}) => _showToast(message, _errorBackground, duration);

/// Internal: builds the toast with the given [backgroundColor]. Returns a
/// handle that callers can pass to `toastification.dismiss(...)` to remove
/// the toast before its [duration] elapses — useful when the toast's
/// instruction stops being relevant (e.g. the originating page is no longer
/// visible).
///
/// Requires [ToastificationWrapper] to be in the widget tree above any
/// [MaterialApp] that calls this; the wrapper provides the overlay and lets
/// us fire toasts without a [BuildContext].
ToastificationItem _showToast(
  String message,
  Color backgroundColor,
  Duration duration,
) {
  return toastification.show(
    // Explicit maxLines overrides toastification's built-in 2-line cap, which
    // would otherwise ellipsize longer messages.
    title: Text(
      message,
      maxLines: 5,
      style: const TextStyle(
        color: _foregroundColor,
        fontWeight: FontWeight.w500,
      ),
    ),
    alignment: Alignment.center,
    autoCloseDuration: duration,
    style: ToastificationStyle.flat,
    backgroundColor: backgroundColor,
    foregroundColor: _foregroundColor,
    animationBuilder: _slideFromTop,
  );
}

/// Slides the toast down by one widget-height into its centered resting
/// position (and back up on dismiss). The default builder slides up from
/// below for center-aligned toasts; this flips that to come from above.
Widget _slideFromTop(
  BuildContext context,
  Animation<double> animation,
  Alignment alignment,
  Widget child,
) {
  return FadeTransition(
    opacity: animation,
    child: SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(0, -1),
        end: Offset.zero,
      ).animate(animation),
      child: child,
    ),
  );
}
