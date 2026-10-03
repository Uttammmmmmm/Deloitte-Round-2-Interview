import 'package:equatable/equatable.dart';

import 'user.dart';

class PagedUsers extends Equatable {
  const PagedUsers({
    required this.users,
    required this.page,
    required this.totalPages,
  });

  final List<User> users;
  final int page;
  final int totalPages;

  bool get hasNext => page < totalPages;

  @override
  List<Object?> get props => [users, page, totalPages];
}
