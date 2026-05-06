// Platform-specific listener that fires when the app becomes visible again.
//
// On native, AppLifecycleListener.onResume already handles foreground returns,
// so the native implementation is a no-op. On web, browsers don't fire that
// lifecycle event when a tab regains focus, so we wire up the DOM
// `visibilitychange` event instead.
export 'visibility_listener_native.dart'
    if (dart.library.js_interop) 'visibility_listener_web.dart';
