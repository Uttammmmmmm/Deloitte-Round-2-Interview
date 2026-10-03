import '../model/users_response_model.dart';

abstract interface class UserRemoteDataSource {
  Future<UsersResponseModel> getUsers({required int page});
}
