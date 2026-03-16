import 'dart:async';

import 'package:client/l10n/l10n.dart';
import 'package:client/problems/cubit/problems_cubit.dart';
import 'package:client/problems/cubit/problems_state.dart';
import 'package:client/services/firestore_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class ProblemsPage extends StatelessWidget {
  const ProblemsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) {
        final repo = context.read<FirestoreRepository>();
        return ProblemsCubit(repo)..subscribe();
      },
      child: const ProblemsView(),
    );
  }
}

class ProblemsView extends StatefulWidget {
  const ProblemsView({super.key});

  @override
  State<ProblemsView> createState() => _ProblemsViewState();
}

class _ProblemsViewState extends State<ProblemsView> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_isNearBottom) {
      unawaited(context.read<ProblemsCubit>().loadMore());
    }
  }

  bool get _isNearBottom {
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.offset;
    return currentScroll >= maxScroll * 0.9;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.problemsAppBarTitle)),
      body: BlocBuilder<ProblemsCubit, ProblemsState>(
        builder: (context, state) {
          return switch (state.status) {
            ProblemsStatus.initial || ProblemsStatus.loading
                when state.problems.isEmpty =>
              const Center(child: CircularProgressIndicator()),
            ProblemsStatus.failure when state.problems.isEmpty => Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Failed to load problems'),
                  const SizedBox(height: 8),
                  ElevatedButton(
                    onPressed: () => context.read<ProblemsCubit>().subscribe(),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
            _ => ListView.builder(
              controller: _scrollController,
              itemCount: state.problems.length + (state.hasMore ? 1 : 0),
              itemBuilder: (context, index) {
                if (index >= state.problems.length) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: CircularProgressIndicator(),
                    ),
                  );
                }
                final problem = state.problems[index];
                return ListTile(
                  title: Text(
                    '${problem.description} (${problem.votes})',
                  ),
                );
              },
            ),
          };
        },
      ),
    );
  }
}
