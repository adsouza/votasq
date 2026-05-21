import 'dart:async';

import 'package:client/app/router.dart';
import 'package:client/auth/auth.dart';
import 'package:client/auto_translate/auto_translate.dart';
import 'package:client/geoscope/geoscope.dart';
import 'package:client/l10n/l10n.dart';
import 'package:client/notifications/notifications.dart';
import 'package:client/services/feedback_repository.dart';
import 'package:client/services/firestore_repository.dart';
import 'package:client/services/language_detection_service.dart';
import 'package:client/services/translation_repository.dart';
import 'package:client/services/visibility_listener.dart';
import 'package:feedback/feedback.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:toastification/toastification.dart';

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
          BlocProvider(
            create: (context) => NotificationsCubit(
              repo: context.read<FirestoreRepository>(),
            ),
          ),
          BlocProvider(
            create: (context) => NotificationsCountCubit(
              repo: context.read<FirestoreRepository>(),
            ),
          ),
        ],
        child: _NotificationAuthSync(
          child: _LastActiveTracker(
            child: BetterFeedback(
              child: ToastificationWrapper(
                child: MaterialApp.router(
                  theme: ThemeData(
                    appBarTheme: AppBarTheme(
                      backgroundColor: Theme.of(
                        context,
                      ).colorScheme.inversePrimary,
                    ),
                    useMaterial3: true,
                  ),
                  localizationsDelegates:
                      AppLocalizations.localizationsDelegates,
                  supportedLocales: AppLocalizations.supportedLocales,
                  routerConfig: _router,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Drives [NotificationsCubit] and [NotificationsCountCubit] off [AuthCubit]
/// state. Subscribes the live notifications stream when a user signs in and
/// clears it on sign-out.
class _NotificationAuthSync extends StatelessWidget {
  const _NotificationAuthSync({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return BlocListener<AuthCubit, AuthState>(
      listenWhen: (previous, current) =>
          previous.status != current.status ||
          previous.userId != current.userId,
      listener: (context, state) {
        final notifsCubit = context.read<NotificationsCubit>();
        final countCubit = context.read<NotificationsCountCubit>();
        final uid = state.userId;
        if (state.status == AuthStatus.authenticated && uid != null) {
          notifsCubit.subscribe(uid);
          unawaited(countCubit.watch(uid));
        } else {
          unawaited(notifsCubit.clear());
          countCubit.reset();
        }
      },
      child: child,
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
  late final VisibilityListener _visibilityListener;

  @override
  void initState() {
    super.initState();
    _lifecycleListener = AppLifecycleListener(
      onResume: _onResume,
    );
    _visibilityListener = VisibilityListener(onVisible: _onResume);
  }

  @override
  void dispose() {
    _visibilityListener.dispose();
    _lifecycleListener.dispose();
    super.dispose();
  }

  void _onResume() {
    final userId = context.read<AuthCubit>().state.userId;
    if (userId == null) return;
    unawaited(context.read<FirestoreRepository>().grantVotesAndTouch(userId));
    unawaited(context.read<NotificationsCountCubit>().refresh());
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
