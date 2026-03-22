// Translation repository with platform-specific implementations.
//
// WARNING: The native implementation imports google_mlkit_translation, whose
// method channel registration interferes with Flutter's text input on desktop
// platforms (e.g. macOS). To avoid this, only import this file from the
// service/repository layer — never from view or widget files.
export 'translation_repository_native.dart'
    if (dart.library.js_interop) 'translation_repository_web.dart';
