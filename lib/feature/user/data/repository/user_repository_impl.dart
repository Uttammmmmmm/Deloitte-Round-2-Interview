import '../../../../core/errors/failures.dart';
import '../../domain/entity/paged_users.dart';
import '../../domain/repository/user_repository.dart';
import '../data_source/user_remote_data_source.dart';

class UserRepositoryImpl implements UserRepository {
  const UserRepositoryImpl(this._remote);

  final UserRemoteDataSource _remote;

  @override
  Future<PagedUsers> getUsers({required int page}) =>
      guard(() async => (await _remote.getUsers(page: page)).toEntity());
}
