import 'dart:async';

import 'package:client/app/router.dart';
import 'package:client/auth/auth.dart';
import 'package:client/geoscope/geoscope.dart';
import 'package:client/l10n/l10n.dart';
import 'package:client/services/feedback_repository.dart';
import 'package:client/services/firestore_repository.dart';
import 'package:feedback/feedback.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

class App extends StatefulWidget {
  const App({
    this.firestoreRepository,
    this.feedbackRepository,
    this.authRepository,
    this.router,
    super.key,
  });

  final FirestoreRepository? firestoreRepository;
  final FeedbackRepository? feedbackRepository;
  final AuthRepository? authRepository;
  final GoRouter? router;

  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> {
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _router = widget.router ?? buildRouter();
  }

  @override
  void dispose() {
    if (widget.router == null) _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authRepo = widget.authRepository ?? AuthRepository();
    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider(
          create: (_) => widget.firestoreRepository ?? FirestoreRepository(),
        ),
        RepositoryProvider(
          create: (_) => widget.feedbackRepository ?? FeedbackRepository(),
        ),
        RepositoryProvider.value(value: authRepo),
      ],
      child: MultiBlocProvider(
        providers: [
          BlocProvider(create: (_) => AuthCubit(authRepo)),
          BlocProvider(
            create: (context) {
              final cubit = GeoscopeCubit(
                context.read<FirestoreRepository>(),
              );
              unawaited(cubit.initialize());
              return cubit;
            },
          ),
        ],
        child: BetterFeedback(
          child: MaterialApp.router(
            theme: ThemeData(
              appBarTheme: AppBarTheme(
                backgroundColor: Theme.of(context).colorScheme.inversePrimary,
              ),
              useMaterial3: true,
            ),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            routerConfig: _router,
          ),
        ),
      ),
    );
  }
}
