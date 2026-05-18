import 'package:flutter/material.dart';
import 'package:toastification/toastification.dart';

// Translucent light orange surface with deep-indigo text. Translucency
// survives toastification's MaterialColor conversion because the primary
// channel keeps the original alpha; only the generated swatch shades are
// opaque, and the toast container paints from the primary.
final Color _backgroundColor = Colors.orange.shade100.withValues(alpha: 0.85);
const _foregroundColor = Color(0xFF1A237E); // Material indigo.shade900.

/// Shows a centered toast notification with [message]. Returns a handle that
/// callers can pass to `toastification.dismiss(...)` to remove the toast
/// before its [duration] elapses — useful when the toast's instruction stops
/// being relevant (e.g. the originating page is no longer visible).
///
/// Requires [ToastificationWrapper] to be in the widget tree above any
/// [MaterialApp] that calls this; the wrapper provides the overlay and lets us
/// fire toasts without a [BuildContext].
ToastificationItem showToast(
  String message, {
  Duration duration = const Duration(seconds: 4),
}) {
  return toastification.show(
    // Explicit maxLines overrides toastification's built-in 2-line cap, which
    // would otherwise ellipsize longer messages like the sign-in hint.
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
    backgroundColor: _backgroundColor,
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
