import 'dart:async';

import 'package:client/app/router.dart';
import 'package:client/auth/auth.dart';
import 'package:client/auto_translate/auto_translate.dart';
import 'package:client/geoscope/geoscope.dart';
import 'package:client/l10n/l10n.dart';
import 'package:client/services/feedback_repository.dart';
import 'package:client/services/firestore_repository.dart';
import 'package:client/services/language_detection_service.dart';
import 'package:client/services/translation_repository.dart';
import 'package:feedback/feedback.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

class App extends StatefulWidget {
  const App({
    this.firestoreRepository,
    this.feedbackRepository,
    this.authRepository,
    this.languageDetectionService,
    this.translationRepository,
    this.router,
    super.key,
  });

  final FirestoreRepository? firestoreRepository;
  final FeedbackRepository? feedbackRepository;
  final AuthRepository? authRepository;
  final LanguageDetectionService? languageDetectionService;
  final TranslationRepository? translationRepository;
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
    final langService =
        widget.languageDetectionService ?? LanguageDetectionService();
    final translationRepo =
        widget.translationRepository ??
        TranslationRepository(
          serverBaseUrl: const String.fromEnvironment(
            'SERVER_BASE_URL',
            defaultValue: 'https://votasq.quikchange.net',
          ),
        );
    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider(
          create: (_) =>
              widget.firestoreRepository ??
              FirestoreRepository(
                languageDetectionService: langService,
                translationRepository: translationRepo,
              ),
        ),
        RepositoryProvider(
          create: (_) => widget.feedbackRepository ?? FeedbackRepository(),
        ),
        RepositoryProvider.value(value: langService),
        RepositoryProvider.value(value: translationRepo),
        RepositoryProvider.value(value: authRepo),
      ],
      child: MultiBlocProvider(
        providers: [
          BlocProvider(
            create: (context) => AuthCubit(
              authRepo,
              context.read<FirestoreRepository>(),
            ),
          ),
          BlocProvider(create: (_) => AutoTranslateCubit()),
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
        child: _LastActiveTracker(
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
      ),
    );
  }
}

class _LastActiveTracker extends StatefulWidget {
  const _LastActiveTracker({required this.child});

  final Widget child;

  @override
  State<_LastActiveTracker> createState() => _LastActiveTrackerState();
}

class _LastActiveTrackerState extends State<_LastActiveTracker> {
  late final AppLifecycleListener _lifecycleListener;

  @override
  void initState() {
    super.initState();
    _lifecycleListener = AppLifecycleListener(
      onResume: _onResume,
      onInactive: _bumpUserLastActiveTS,
      onPause: _bumpUserLastActiveTS,
    );
  }

  bool _hasShownSignInToast = false;

  @override
  void dispose() {
    _lifecycleListener.dispose();
    super.dispose();
  }

  void _showSignInToast() {
    if (_hasShownSignInToast) return;
    _hasShownSignInToast = true;

    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;

    messenger.showSnackBar(
      SnackBar(
        content: Text(context.l10n.signInHintToast),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _onResume() {
    final userId = context.read<AuthCubit>().state.userId;
    if (userId == null) {
      _showSignInToast();
      return;
    }
    unawaited(context.read<FirestoreRepository>().grantVotesAndTouch(userId));
  }

  void _bumpUserLastActiveTS() {
    final userId = context.read<AuthCubit>().state.userId;
    if (userId == null) {
      _showSignInToast();
      return;
    }
    unawaited(context.read<FirestoreRepository>().touchLastActiveAt(userId));
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
