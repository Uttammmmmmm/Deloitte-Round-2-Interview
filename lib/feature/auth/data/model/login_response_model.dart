import '../../domain/entity/auth_session.dart';

class LoginResponseModel {
  const LoginResponseModel({required this.token});

  final String token;

  factory LoginResponseModel.fromJson(Map<String, dynamic> json) =>
      LoginResponseModel(token: json['token'] as String);

  AuthSession toEntity() => AuthSession(token: token);
}
