import '../../../../core/constants/api_constants.dart';
import '../../../../core/network/dio_client.dart';
import '../model/login_request_model.dart';
import '../model/login_response_model.dart';

// Interface + impl in one file = acceptable interview shortcut.
abstract interface class AuthRemoteDataSource {
  Future<LoginResponseModel> login(LoginRequestModel request);
}

class AuthRemoteDataSourceImpl implements AuthRemoteDataSource {
  const AuthRemoteDataSourceImpl(this._client);

  final DioClient _client;

  @override
  Future<LoginResponseModel> login(LoginRequestModel request) async {
    final json = await _client.post(ApiConstants.login, data: request.toJson());
    return LoginResponseModel.fromJson(json as Map<String, dynamic>);
  }
}
