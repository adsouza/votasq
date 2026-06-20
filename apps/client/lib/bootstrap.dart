import 'dart:async';
import 'dart:developer';
import 'dart:io' show Platform;

import 'package:bloc/bloc.dart';
import 'package:client/firebase_options.dart';
import 'package:client/l10n/timeago_locales.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb, kReleaseMode;
import 'package:flutter/widgets.dart';
import 'package:flutter_web_plugins/url_strategy.dart';

class AppBlocObserver extends BlocObserver {
  const AppBlocObserver();

  @override
  void onChange(BlocBase<dynamic> bloc, Change<dynamic> change) {
    super.onChange(bloc, change);
    log('onChange(${bloc.runtimeType}, $change)');
  }

  @override
  void onError(BlocBase<dynamic> bloc, Object error, StackTrace stackTrace) {
    log('onError(${bloc.runtimeType}, $error, $stackTrace)');
    super.onError(bloc, error, stackTrace);
  }
}

Future<void> bootstrap(
  FutureOr<Widget> Function() builder, {
  bool useEmulators = false,
}) async {
  WidgetsFlutterBinding.ensureInitialized();
  // print() (not log()) so this is reliably visible in `flutter run`'s
  // terminal. The single most useful diagnostic at startup: which
  // backend did this build connect to? Tells us in one line whether
  // dart-defines / build flavor wiring did what we expect.
  // ignore: avoid_print
  print('Bootstrap: useEmulators=$useEmulators');
  usePathUrlStrategy();

  // Load relative-time ("9 hours ago") messages for every supported locale
  // before any UI builds. timeago stores these in global state, so once is
  // enough and it must precede the first NotificationCard render.
  registerTimeagoLocales();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Activate App Check in every non-(web+emulator) configuration.
  //
  // The naive guard `if (!useEmulators)` is wrong on Apple platforms:
  // when the firebase_app_check plugin is loaded (which is always, it's
  // in pubspec.yaml), the iOS/macOS Firestore SDK automatically attempts
  // to fetch an App Check token for every request. Without an explicit
  // provider, the SDK falls back to DeviceCheck, which can't issue a
  // token in debug builds — the exchange to `firebaseappcheck.googleapis.com`
  // fails ("Too many attempts"), the Firestore SDK then refuses to
  // proceed, and every query surfaces as `[cloud_firestore/unavailable]`.
  // Activating with the debug provider gives the SDK something to use;
  // the emulator ignores tokens, so it doesn't matter that the debug
  // token isn't registered in Firebase Console for emulator runs.
  //
  // Web emulator runs skip activation because reCAPTCHA's site-key
  // verification against localhost is fiddly and the web Firestore SDK
  // doesn't have the same auto-fallback problem.
  //
  // For non-release mobile providers, the debug token is emitted to the
  // log on first use and must be registered in Firebase Console →
  // App Check → Apps (for prod runs; emulator runs ignore the result).
  if (!useEmulators || !kIsWeb) {
    await FirebaseAppCheck.instance.activate(
      providerWeb: ReCaptchaV3Provider(
        '6LehEfcsAAAAAKNdlzalCBUJXYvJngj1lFTKYpC6',
      ),
      providerAndroid: kReleaseMode
          ? const AndroidPlayIntegrityProvider()
          : const AndroidDebugProvider(),
      providerApple: kReleaseMode
          ? const AppleAppAttestProvider()
          : const AppleDebugProvider(),
    );
  }

  if (useEmulators) {
    await _connectToEmulators();
  } else if (kIsWeb) {
    // Persistence is on by default for native platforms. On web it must be
    // opted in and can fail (incognito, multi-tab). Skip when pointed at the
    // emulator — useFirestoreEmulator is incompatible with persistence.
    try {
      FirebaseFirestore.instance.settings = const Settings(
        persistenceEnabled: true,
      );
    } on Exception catch (e) {
      log('Web Firestore persistence unavailable: $e');
    }
  }

  FlutterError.onError = (details) {
    log(details.exceptionAsString(), stackTrace: details.stack);
  };

  Bloc.observer = const AppBlocObserver();

  runApp(await builder());
}

/// Routes Firebase Auth + Firestore at the local emulator suite.
///
/// Hosts default to `localhost`; on Android the loopback to the host machine
/// is `10.0.2.2`. Ports match the values in `firebase.json` (auth: 9099,
/// firestore: 8081).
///
/// Persistence is disabled on emulator runs so the on-disk cache (which is
/// keyed by Firestore instance, not by backend) doesn't carry emulator data
/// over into subsequent prod/staging sessions on the same machine. Without
/// this, an empty emulator collection could shadow the real collection for
/// the SDK's first cache-served reads.
Future<void> _connectToEmulators() async {
  final host = _emulatorHost();
  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: false,
  );
  await FirebaseAuth.instance.useAuthEmulator(host, 9099);
  FirebaseFirestore.instance.useFirestoreEmulator(host, 8081);
  FirebaseFunctions.instance.useFunctionsEmulator(host, 5001);
  // print() (not log()) so this is reliably visible in `flutter run`'s
  // terminal — dart:developer.log() routes through the VM service and
  // may not surface depending on Flutter / IDE configuration. This is
  // a one-line bootstrap log; the noise is worth the diagnosability.
  // ignore: avoid_print
  print(
    'Bootstrap: connected to Firebase emulators at $host '
    '(auth:9099, firestore:8081, functions:5001)',
  );
}

String _emulatorHost() {
  if (kIsWeb) return 'localhost';
  if (Platform.isAndroid) return '10.0.2.2';
  // macOS / iOS / desktop: use 127.0.0.1 literally rather than 'localhost'.
  // macOS resolves 'localhost' to both ::1 (IPv6) and 127.0.0.1 (IPv4),
  // and the Firebase Local Emulator Suite binds only to 127.0.0.1. The
  // Firestore client uses gRPC, which on Apple platforms doesn't reliably
  // happy-eyeballs from IPv6 to IPv4 — so a connection to ::1:8081 fails
  // with "Connection refused" and surfaces as [cloud_firestore/unavailable].
  // (Auth works because its REST/URLSession path does proper fallback.)
  return '127.0.0.1';
}
