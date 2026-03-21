import 'package:client/problems/problems.dart';
import 'package:go_router/go_router.dart';

GoRouter buildRouter() {
  return GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const ProblemsPage(),
        routes: [
          GoRoute(
            path: 'problems/:id',
            builder: (context, state) {
              final id = state.pathParameters['id']!;
              return ProblemDetailPage(problemId: id);
            },
          ),
        ],
      ),
    ],
  );
}
