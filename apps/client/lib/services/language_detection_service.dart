// Language detection service with platform-specific implementations.
//
// WARNING: The native implementation imports google_mlkit_language_id, whose
// method channel registration interferes with Flutter's text input on desktop
// platforms (e.g. macOS). To avoid this, only import this file from the
// service/repository layer — never from view or widget files. Views should
// access detection indirectly via FirestoreRepository, which holds a
// LanguageDetectionService instance internally.
export 'language_detection_service_native.dart'
    if (dart.library.js_interop) 'language_detection_service_web.dart';
