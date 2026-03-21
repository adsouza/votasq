import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared/shared.dart';

enum ProblemsStatus { initial, loading, success, failure }

class ProblemsState {
  const ProblemsState({
    this.status = ProblemsStatus.initial,
    this.problems = const [],
    this.lastDocument,
    this.hasMore = true,
    this.geoscope = '/',
  });

  final ProblemsStatus status;
  final List<Problem> problems;
  final DocumentSnapshot? lastDocument;
  final bool hasMore;
  final String geoscope;

  ProblemsState copyWith({
    ProblemsStatus? status,
    List<Problem>? problems,
    DocumentSnapshot? Function()? lastDocument,
    bool? hasMore,
    String? geoscope,
  }) {
    return ProblemsState(
      status: status ?? this.status,
      problems: problems ?? this.problems,
      lastDocument: lastDocument != null ? lastDocument() : this.lastDocument,
      hasMore: hasMore ?? this.hasMore,
      geoscope: geoscope ?? this.geoscope,
    );
  }
}
