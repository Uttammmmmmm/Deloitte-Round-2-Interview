import 'package:equatable/equatable.dart';

class AuthSession extends Equatable {
  const AuthSession({required this.token});

  final String token;

  @override
  List<Object?> get props => [token];
}
