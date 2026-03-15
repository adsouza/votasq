import 'package:shared/shared.dart';

enum ProblemsStatus { initial, loading, success, failure }

class ProblemsState {
  const ProblemsState({
    this.status = ProblemsStatus.initial,
    this.problems = const [],
    this.nextPageToken,
  });

  final ProblemsStatus status;
  final List<Problem> problems;
  final String? nextPageToken;

  bool get hasMore => nextPageToken != null;

  ProblemsState copyWith({
    ProblemsStatus? status,
    List<Problem>? problems,
    String? Function()? nextPageToken,
  }) {
    return ProblemsState(
      status: status ?? this.status,
      problems: problems ?? this.problems,
      nextPageToken: nextPageToken != null
          ? nextPageToken()
          : this.nextPageToken,
    );
  }
}
