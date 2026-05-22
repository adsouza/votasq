import 'dart:async';
import 'dart:developer';
import 'dart:io' show Platform;

import 'package:bloc/bloc.dart';
import 'package:client/firebase_options.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
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
  usePathUrlStrategy();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

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
  log(
    'Bootstrap: connected to Firebase emulators at $host '
    '(auth:9099, firestore:8081)',
  );
}

String _emulatorHost() {
  if (kIsWeb) return 'localhost';
  if (Platform.isAndroid) return '10.0.2.2';
  return 'localhost';
}
