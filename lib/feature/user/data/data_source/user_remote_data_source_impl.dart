import '../../../../core/constants/api_constants.dart';
import '../../../../core/network/dio_client.dart';
import '../model/users_response_model.dart';
import 'user_remote_data_source.dart';

class UserRemoteDataSourceImpl implements UserRemoteDataSource {
  const UserRemoteDataSourceImpl(this._client);

  final DioClient _client;

  @override
  Future<UsersResponseModel> getUsers({required int page}) async {
    final json = await _client.get(ApiConstants.users, query: {'page': page});
    return UsersResponseModel.fromJson(json as Map<String, dynamic>);
  }
}
