import 'package:equatable/equatable.dart';

import '../../domain/entity/user.dart';

sealed class UserState extends Equatable {
  const UserState();

  @override
  List<Object?> get props => [];
}

class UserInitial extends UserState {
  const UserInitial();
}

/// First page is loading (full-screen spinner).
class UserLoading extends UserState {
  const UserLoading();
}

class UserLoaded extends UserState {
  const UserLoaded({
    required this.users,
    required this.currentPage,
    required this.totalPages,
    this.isLoadingMore = false,
    this.loadMoreFailed = false,
  });

  final List<User> users;
  final int currentPage;
  final int totalPages;
  final bool isLoadingMore; // next page is loading (footer spinner)
  final bool loadMoreFailed; // next page failed (footer retry button)

  bool get hasReachedMax => currentPage >= totalPages;

  UserLoaded copyWith({
    List<User>? users,
    int? currentPage,
    int? totalPages,
    bool? isLoadingMore,
    bool? loadMoreFailed,
  }) => UserLoaded(
    users: users ?? this.users,
    currentPage: currentPage ?? this.currentPage,
    totalPages: totalPages ?? this.totalPages,
    isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    loadMoreFailed: loadMoreFailed ?? this.loadMoreFailed,
  );

  @override
  List<Object?> get props => [
    users,
    currentPage,
    totalPages,
    isLoadingMore,
    loadMoreFailed,
  ];
}

class UserError extends UserState {
  const UserError(this.message);

  final String message;

  @override
  List<Object?> get props => [message];
}
