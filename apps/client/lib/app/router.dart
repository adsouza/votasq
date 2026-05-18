import 'package:client/problems/problems.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

GoRouter buildRouter() {
  return GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const ProblemsPage(),
        routes: [
          GoRoute(
            path: 'new',
            builder: (context, state) => const NewProblemPage(),
          ),
          GoRoute(
            path: 'problems/:id',
            builder: (context, state) {
              final id = state.pathParameters['id']!;
              // ValueKey(id) forces a fresh State (re-running initState/_load)
              // when navigating between two problem detail pages, e.g. after
              // forking. Without it, Flutter reuses the same Element and the
              // page keeps showing stale data.
              return ProblemDetailPage(key: ValueKey(id), problemId: id);
            },
          ),
        ],
      ),
    ],
  );
}
