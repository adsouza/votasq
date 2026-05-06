/// No-op on native — AppLifecycleListener.onResume already triggers vote
/// grants when the OS resumes the app from the background. The web variant
/// of this class wires up the DOM `visibilitychange` event instead.
class VisibilityListener {
  // The parameter must exist for API parity with the web variant.
  // ignore: avoid_unused_constructor_parameters
  VisibilityListener({required void Function() onVisible});

  void dispose() {}
}
