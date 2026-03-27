import 'dart:async';

import 'package:client/auth/auth.dart';
import 'package:client/l10n/l10n.dart';
import 'package:client/problems/cubit/problems_cubit.dart';
import 'package:client/problems/widgets/geoscope_widgets.dart';
import 'package:client/problems/widgets/problem_translation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:shared/shared.dart';

/// A read-only list tile for a single problem, showing its description, goal,
/// geoscope chip, vote chip, and trailing action buttons.
class ProblemReadTile extends StatelessWidget {
  const ProblemReadTile({
    required this.problem,
    required this.showEditButton,
    required this.showComplaintButton,
    required this.onEdit,
    required this.onCopyLink,
    required this.onComplaint,
    super.key,
  });

  final Problem problem;
  final bool showEditButton;
  final bool showComplaintButton;
  final VoidCallback onEdit;
  final VoidCallback onCopyLink;
  final VoidCallback onComplaint;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return ListTile(
      contentPadding: const EdgeInsets.only(left: 16, right: 4),
      title: ProblemTranslation(
        problemId: problem.id,
        lang: problem.lang,
        originalDescription: problem.description,
        originalGoal: problem.goal,
        child: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 6,
          children: [
            GestureDetector(
              onDoubleTap: () => context.go('/problems/${problem.id}'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  TranslatedField(
                    problem.description,
                    fieldSelector: (tp) => tp.description,
                  ),
                  if (problem.goal.isNotEmpty)
                    TranslatedField(
                      problem.goal,
                      fieldSelector: (tp) => tp.goal,
                      style: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: 13,
                      ),
                    ),
                ],
              ),
            ),
            if (problem.geoscope != '/')
              Tooltip(
                message:
                    '${l10n.geoscopeLabel}'
                    ' ${geoscopeLabel(context, problem.geoscope)}',
                child: Chip(
                  label: Text(
                    problem.geoscope.split('/').last,
                    style: const TextStyle(fontSize: 12),
                  ),
                  backgroundColor: theme.colorScheme.tertiaryContainer,
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            Builder(
              builder: (context) {
                final authState = context.watch<AuthCubit>().state;
                final userId = authState.userId;
                if (userId != null && (authState.remainingVotes ?? 0) > 0) {
                  return Tooltip(
                    message: l10n.voteButtonTooltip,
                    child: ActionChip(
                      avatar: const Icon(
                        Icons.arrow_circle_up_rounded,
                        size: 16,
                      ),
                      label: Text(
                        '${problem.votes}',
                        style: const TextStyle(fontSize: 12),
                      ),
                      backgroundColor: theme.colorScheme.secondaryContainer,
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      onPressed: () {
                        unawaited(
                          context.read<ProblemsCubit>().vote(
                            problemId: problem.id,
                            userId: userId,
                          ),
                        );
                      },
                    ),
                  );
                }
                return Tooltip(
                  message: l10n.votesChipTooltip,
                  child: Chip(
                    label: Text(
                      '${problem.votes}',
                      style: const TextStyle(fontSize: 12),
                    ),
                    backgroundColor: theme.colorScheme.secondaryContainer,
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                );
              },
            ),
            const ProblemTranslateButton(),
          ],
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Tooltip(
            message: l10n.copyProblemLink,
            child: IconButton(
              icon: const Icon(Icons.link, size: 20),
              onPressed: onCopyLink,
            ),
          ),
          if (showEditButton)
            Tooltip(
              message: l10n.editProblemButton,
              child: TextButton(
                onPressed: onEdit,
                child: const Text('🖊️'),
              ),
            )
          else if (showComplaintButton)
            Tooltip(
              message: l10n.flagProblemButton,
              child: TextButton(
                onPressed: onComplaint,
                child: const Text('🙈'),
              ),
            ),
        ],
      ),
    );
  }
}
