import 'dart:async';

import 'package:client/auth/auth.dart';
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
  final _addController = TextEditingController();

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
    _addController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_isNearBottom) {
      unawaited(context.read<ProblemsCubit>().loadMore());
    }
  }

  bool get _hasEnoughWords =>
      _addController.text
          .trim()
          .split(RegExp(r'\s+'))
          .where((w) => w.isNotEmpty)
          .length >=
      3;

  void _submitProblem() {
    if (!_hasEnoughWords) return;
    final text = _addController.text.trim();
    final userId = context.read<AuthCubit>().state.userId!;
    unawaited(
      context.read<ProblemsCubit>().addProblem(
        description: text,
        ownerId: userId,
      ),
    );
    _addController.clear();
  }

  Widget _buildAddProblemRow(BuildContext context) {
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ValueListenableBuilder<TextEditingValue>(
              valueListenable: _addController,
              builder: (context, value, child) {
                return TextField(
                  controller: _addController,
                  maxLength: 80,
                  decoration: InputDecoration(
                    hintText: l10n.addProblemHint,
                  ),
                  onSubmitted: _hasEnoughWords ? (_) => _submitProblem() : null,
                );
              },
            ),
          ),
          const SizedBox(width: 8),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: _addController,
            builder: (context, value, child) {
              return ElevatedButton(
                onPressed: _hasEnoughWords ? _submitProblem : null,
                child: Text(l10n.addProblemButton),
              );
            },
          ),
        ],
      ),
    );
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
      appBar: AppBar(
        title: Text(l10n.problemsAppBarTitle),
        actions: [
          BlocBuilder<AuthCubit, AuthState>(
            builder: (context, authState) {
              if (authState.status == AuthStatus.authenticated) {
                return IconButton(
                  icon: const Icon(Icons.logout),
                  tooltip: l10n.signOutButton,
                  onPressed: () => context.read<AuthCubit>().signOut(),
                );
              }
              return TextButton(
                onPressed: () => context.read<AuthCubit>().signIn(),
                child: Text(l10n.signInButton),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          BlocBuilder<AuthCubit, AuthState>(
            builder: (context, authState) {
              if (authState.status == AuthStatus.authenticated) {
                return _buildAddProblemRow(context);
              }
              return const SizedBox.shrink();
            },
          ),
          Expanded(
            child: BlocBuilder<ProblemsCubit, ProblemsState>(
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
                          onPressed: () =>
                              context.read<ProblemsCubit>().subscribe(),
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
          ),
        ],
      ),
    );
  }
}
