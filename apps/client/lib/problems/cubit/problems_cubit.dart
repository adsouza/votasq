import 'dart:developer';

import 'package:bloc/bloc.dart';
import 'package:client/problems/cubit/problems_state.dart';
import 'package:client/services/api_service.dart';

class ProblemsCubit extends Cubit<ProblemsState> {
  ProblemsCubit(this._api) : super(const ProblemsState());

  final ApiService _api;

  Future<void> loadProblems() async {
    emit(state.copyWith(status: ProblemsStatus.loading));
    try {
      final result = await _api.listProblems();
      emit(
        state.copyWith(
          status: ProblemsStatus.success,
          problems: result.problems,
          nextPageToken: () => result.nextPageToken,
        ),
      );
    } on Exception catch (e, st) {
      log('loadProblems failed: $e', stackTrace: st);
      emit(state.copyWith(status: ProblemsStatus.failure));
    }
  }

  Future<void> loadMore() async {
    if (!state.hasMore) return;
    try {
      final result = await _api.listProblems(
        pageToken: state.nextPageToken,
      );
      emit(
        state.copyWith(
          problems: [...state.problems, ...result.problems],
          nextPageToken: () => result.nextPageToken,
        ),
      );
    } on Exception catch (e, st) {
      log('loadMore failed: $e', stackTrace: st);
      emit(state.copyWith(status: ProblemsStatus.failure));
    }
  }
}
