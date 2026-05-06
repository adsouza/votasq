import 'dart:js_interop';

@JS('document')
external _Document get _document;

extension type _Document._(JSObject _) implements JSObject {
  external String get visibilityState;
  external void addEventListener(String type, JSFunction listener);
  external void removeEventListener(String type, JSFunction listener);
}

/// Listens for the browser's `visibilitychange` event and invokes `onVisible`
/// when the tab returns to the foreground. This fills the gap left by
/// `AppLifecycleListener.onResume`, which is unreliable on web.
class VisibilityListener {
  VisibilityListener({required void Function() onVisible})
    : _onVisible = onVisible {
    _jsListener = _handleVisibilityChange.toJS;
    _document.addEventListener('visibilitychange', _jsListener);
  }

  final void Function() _onVisible;
  late final JSFunction _jsListener;

  void _handleVisibilityChange() {
    if (_document.visibilityState == 'visible') _onVisible();
  }

  void dispose() {
    _document.removeEventListener('visibilitychange', _jsListener);
  }
}
