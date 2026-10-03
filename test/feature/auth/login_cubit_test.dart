import 'package:bloc_test/bloc_test.dart';
import 'package:demoapi/core/errors/failures.dart';
import 'package:demoapi/feature/auth/domain/entity/auth_session.dart';
import 'package:demoapi/feature/auth/domain/usecase/login.dart';
import 'package:demoapi/feature/auth/presentation/cubit/login_cubit.dart';
import 'package:demoapi/feature/auth/presentation/cubit/login_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockLogin extends Mock implements Login {}

void main() {
  late MockLogin login;
  setUp(() => login = MockLogin());

  blocTest<LoginCubit, LoginState>(
    'emits [Loading, Success] when credentials are valid',
    build: () {
      when(() => login(email: 'a@a.com', password: 'secret1'))
          .thenAnswer((_) async => const AuthSession(token: 't'));
      return LoginCubit(login);
    },
    act: (c) => c.login(email: 'a@a.com', password: 'secret1'),
    expect: () => const [LoginLoading(), LoginSuccess()],
  );

  blocTest<LoginCubit, LoginState>(
    'emits [Loading, Error] when the server rejects the login',
    build: () {
      when(
        () => login(
          email: any(named: 'email'),
          password: any(named: 'password'),
        ),
      ).thenThrow(const ServerFailure('Missing password', statusCode: 400));
      return LoginCubit(login);
    },
    act: (c) => c.login(email: 'a@a.com', password: ''),
    expect: () => const [LoginLoading(), LoginError('Missing password')],
  );
}
