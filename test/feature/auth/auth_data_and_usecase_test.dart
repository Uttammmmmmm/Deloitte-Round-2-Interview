import 'package:demoapi/core/network/dio_client.dart';
import 'package:demoapi/feature/auth/data/data_source/auth_remote_data_source.dart';
import 'package:demoapi/feature/auth/data/model/login_request_model.dart';
import 'package:demoapi/feature/auth/domain/entity/auth_session.dart';
import 'package:demoapi/feature/auth/domain/repository/auth_repository.dart';
import 'package:demoapi/feature/auth/domain/usecase/login.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockDioClient extends Mock implements DioClient {}

class MockAuthRepository extends Mock implements AuthRepository {}

void main() {
  test(
    'data source: POST /login with the request JSON, parses {"token"}',
    () async {
      final client = MockDioClient();
      when(() => client.post('/login', data: any(named: 'data')))
          .thenAnswer((_) async => {'token': 'QpwL5tke4Pnpja7X4'});

      final response = await AuthRemoteDataSourceImpl(client).login(
        const LoginRequestModel(
          email: 'eve.holt@reqres.in',
          password: 'cityslicka',
        ),
      );

      expect(response.token, 'QpwL5tke4Pnpja7X4');
      expect(
        response.toEntity(),
        const AuthSession(token: 'QpwL5tke4Pnpja7X4'),
      );
      verify(
        () => client.post(
          '/login',
          data: {'email': 'eve.holt@reqres.in', 'password': 'cityslicka'},
        ),
      ).called(1);
    },
  );

  test('Login use case delegates to the repository', () async {
    final repository = MockAuthRepository();
    when(() => repository.login(email: 'a@a.com', password: 'secret1'))
        .thenAnswer((_) async => const AuthSession(token: 't'));

    final session = await Login(repository)(
      email: 'a@a.com',
      password: 'secret1',
    );

    expect(session.token, 't');
  });
}
