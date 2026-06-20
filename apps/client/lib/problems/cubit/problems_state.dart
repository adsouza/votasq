import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared/shared.dart';

enum ProblemsStatus { initial, loading, success, failure }

/// A one-shot request from the cubit asking the view to bring a particular
/// problem into view. [seq] is a monotonic counter so that two requests for
/// the same [problemId] still register as a state change (the view triggers
/// on `seq`, not on identity). The view decides whether scrolling is actually
/// needed — see the "gentle" follow logic in `ProblemsView`.
class ProblemScrollRequest {
  const ProblemScrollRequest({required this.problemId, required this.seq});

  final String problemId;
  final int seq;
}

class ProblemsState {
  const ProblemsState({
    this.status = ProblemsStatus.initial,
    this.problems = const [],
    this.lastDocument,
    this.hasMore = true,
    this.geoscope = '/',
    this.scrollRequest,
  });

  final ProblemsStatus status;
  final List<Problem> problems;
  final DocumentSnapshot? lastDocument;
  final bool hasMore;
  final String geoscope;
  final ProblemScrollRequest? scrollRequest;

  ProblemsState copyWith({
    ProblemsStatus? status,
    List<Problem>? problems,
    DocumentSnapshot? Function()? lastDocument,
    bool? hasMore,
    String? geoscope,
    ProblemScrollRequest? scrollRequest,
  }) {
    return ProblemsState(
      status: status ?? this.status,
      problems: problems ?? this.problems,
      lastDocument: lastDocument != null ? lastDocument() : this.lastDocument,
      hasMore: hasMore ?? this.hasMore,
      geoscope: geoscope ?? this.geoscope,
      scrollRequest: scrollRequest ?? this.scrollRequest,
    );
  }
}
