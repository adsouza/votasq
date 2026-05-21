import 'package:client/notifications/notifications.dart';
import 'package:client/problems/problems.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

GoRouter buildRouter() {
  // Without this, `context.push('/problems/X')` updates the Navigator stack
  // but leaves the browser URL at the pre-push location, so the visible URL
  // never reflects which problem the user is viewing. Our pushed locations
  // are all declared `GoRoute`s, so the "not always deeplink-able" caveat in
  // the go_router docs does not apply here.
  GoRouter.optionURLReflectsImperativeAPIs = true;
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
          GoRoute(
            path: 'notifications',
            builder: (context, state) => const NotificationsPage(),
          ),
        ],
      ),
    ],
  );
}
