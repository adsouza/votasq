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
import 'package:client/services/notification_registration_service.dart';
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
    this.notificationRegistration,
    this.router,
    super.key,
  });

  final FirestoreRepository? firestoreRepository;
  final FeedbackRepository? feedbackRepository;
  final AuthRepository? authRepository;
  final LanguageDetectionService? languageDetectionService;
  final TranslationRepository? translationRepository;
  final NotificationRegistrationService? notificationRegistration;
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
        RepositoryProvider<NotificationRegistrationService>(
          create: (context) =>
              widget.notificationRegistration ??
              NotificationRegistrationService(
                repo: context.read<FirestoreRepository>(),
                // VAPID public key for web push (only needed on Chrome /
                // Firefox etc.; ignored on native). Generate in Firebase
                // Console → Cloud Messaging → Web Push certificates, then
                // pass at run time:
                //   tool/run-client.sh dev -d chrome \
                //     --dart-define=VAPID_KEY=BJ...
                // Empty string means "not configured" — `getToken` on web
                // will fail and registration is skipped, which is fine
                // outside web flavors.
                webVapidKey: const String.fromEnvironment('VAPID_KEY').isEmpty
                    ? null
                    : const String.fromEnvironment('VAPID_KEY'),
              ),
        ),
      ],
      child: MultiBlocProvider(
        providers: [
          BlocProvider(
            create: (context) => UserCubit(
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

/// Drives [NotificationsCubit], [NotificationsCountCubit], and
/// [NotificationRegistrationService] off [UserCubit] state. On sign-in,
/// the live subscription starts, the badge count refreshes, and FCM
/// permission + token registration kicks off. On sign-out, the cubits
/// reset and the device's FCM token doc is deleted. Captures the previous
/// uid so the unregister can target it even after the UserCubit has moved
/// past it.
///
/// Also re-runs the unread-count aggregation whenever the live
/// notifications subscription emits — without this, an incoming push (or
/// any out-of-band notification doc write) would land in the list but the
/// badge would stay at its stale value until the user navigated to the
/// page or backgrounded/foregrounded the app.
class _NotificationAuthSync extends StatefulWidget {
  const _NotificationAuthSync({required this.child});

  final Widget child;

  @override
  State<_NotificationAuthSync> createState() => _NotificationAuthSyncState();
}

class _NotificationAuthSyncState extends State<_NotificationAuthSync> {
  String? _previousUid;

  @override
  Widget build(BuildContext context) {
    return MultiBlocListener(
      listeners: [
        BlocListener<UserCubit, UserState>(
          listenWhen: (previous, current) =>
              previous.status != current.status ||
              previous.userId != current.userId,
          listener: (context, state) {
            final notifsCubit = context.read<NotificationsCubit>();
            final countCubit = context.read<NotificationsCountCubit>();
            final registration = context
                .read<NotificationRegistrationService>();
            final uid = state.userId;
            if (state.status == AuthStatus.authenticated && uid != null) {
              notifsCubit.subscribe(uid);
              unawaited(countCubit.watch(uid));
              unawaited(registration.register(uid));
              _previousUid = uid;
            } else {
              unawaited(notifsCubit.clear());
              countCubit.reset();
              final priorUid = _previousUid;
              if (priorUid != null) {
                unawaited(registration.unregister(priorUid));
                _previousUid = null;
              }
            }
          },
        ),
        BlocListener<NotificationsCubit, NotificationsState>(
          // Whenever the live list changes, the unread count could have
          // changed too (new doc arrived, or readAt flipped). Re-query the
          // aggregation so the bell badge stays in sync without polling.
          listenWhen: (previous, current) =>
              previous.notifications != current.notifications,
          listener: (context, _) {
            unawaited(context.read<NotificationsCountCubit>().refresh());
          },
        ),
      ],
      child: widget.child,
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
    final userId = context.read<UserCubit>().state.userId;
    if (userId == null) return;
    unawaited(context.read<FirestoreRepository>().grantVotesAndTouch(userId));
    unawaited(context.read<NotificationsCountCubit>().refresh());
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
