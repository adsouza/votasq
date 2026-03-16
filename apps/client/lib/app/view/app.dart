import 'package:client/l10n/l10n.dart';
import 'package:client/problems/problems.dart';
import 'package:client/services/firestore_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class App extends StatelessWidget {
  const App({this.firestoreRepository, super.key});

  final FirestoreRepository? firestoreRepository;

  @override
  Widget build(BuildContext context) {
    return RepositoryProvider(
      create: (_) => firestoreRepository ?? FirestoreRepository(),
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
    );
  }
}
