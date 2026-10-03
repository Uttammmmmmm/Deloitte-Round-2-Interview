import '../entity/paged_users.dart';
import '../repository/user_repository.dart';

class GetUsers {
  const GetUsers(this._repository);

  final UserRepository _repository;

  Future<PagedUsers> call({required int page}) =>
      _repository.getUsers(page: page);
}
