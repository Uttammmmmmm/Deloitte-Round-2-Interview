import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/errors/report_failure.dart';
import '../../domain/usecase/get_users.dart';
import 'user_state.dart';

class UserCubit extends Cubit<UserState> with FailureReporting<UserState> {
  UserCubit(this._getUsers) : super(const UserInitial());

  final GetUsers _getUsers;

  /// Bumped by every fresh load. A response that belongs to an older
  /// generation (user hit Retry, or refreshed meanwhile) is dropped.
  int _generation = 0;

  /// First page (also used by the Retry button).
  Future<void> fetchUsers() async {
    final generation = ++_generation;
    emit(const UserLoading());
    try {
      final result = await _getUsers(page: 1);
      if (isClosed || generation != _generation) return;
      emit(
        UserLoaded(
          users: result.users,
          currentPage: result.page,
          totalPages: result.totalPages,
        ),
      );
    } on CancelledFailure {
      return; // superseded on purpose: no error UI
    } on Failure catch (failure) {
      reportFailure(failure);
      if (isClosed || generation != _generation) return;
      emit(UserError(failure.message));
    }
  }

  /// Next page, appended to the current list. Safe to call many times.
  Future<void> loadMore() async {
    final current = state;
    if (current is! UserLoaded ||
        current.isLoadingMore ||
        current.hasReachedMax) {
      return;
    }

    final generation = _generation;
    emit(current.copyWith(isLoadingMore: true, loadMoreFailed: false));
    try {
      final result = await _getUsers(page: current.currentPage + 1);
      if (isClosed || generation != _generation) return; // list was reloaded
      emit(
        current.copyWith(
          users: [...current.users, ...result.users],
          currentPage: result.page,
          totalPages: result.totalPages,
          isLoadingMore: false,
        ),
      );
    } on CancelledFailure {
      return;
    } on Failure catch (failure) {
      reportFailure(failure);
      if (isClosed || generation != _generation) return;
      emit(current.copyWith(isLoadingMore: false, loadMoreFailed: true));
    }
  }
}
