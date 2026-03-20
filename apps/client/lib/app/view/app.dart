import 'package:client/auth/auth.dart';
import 'package:client/l10n/l10n.dart';
import 'package:client/problems/problems.dart';
import 'package:client/services/feedback_repository.dart';
import 'package:client/services/firestore_repository.dart';
import 'package:feedback/feedback.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class App extends StatelessWidget {
  const App({
    this.firestoreRepository,
    this.feedbackRepository,
    this.authRepository,
    super.key,
  });

  final FirestoreRepository? firestoreRepository;
  final FeedbackRepository? feedbackRepository;
  final AuthRepository? authRepository;

  @override
  Widget build(BuildContext context) {
    final authRepo = authRepository ?? AuthRepository();
    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider(
          create: (_) => firestoreRepository ?? FirestoreRepository(),
        ),
        RepositoryProvider(
          create: (_) => feedbackRepository ?? FeedbackRepository(),
        ),
        RepositoryProvider.value(value: authRepo),
      ],
      child: BlocProvider(
        create: (_) => AuthCubit(authRepo),
        child: BetterFeedback(
          child: MaterialApp(
            theme: ThemeData(
              appBarTheme: AppBarTheme(
                backgroundColor: Theme.of(context).colorScheme.inversePrimary,
              ),
              useMaterial3: true,
            ),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const ProblemsPage(),
          ),
        ),
      ),
    );
  }
}
