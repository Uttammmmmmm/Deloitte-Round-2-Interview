import '../entity/paged_users.dart';

abstract interface class UserRepository {
  Future<PagedUsers> getUsers({required int page});
}
