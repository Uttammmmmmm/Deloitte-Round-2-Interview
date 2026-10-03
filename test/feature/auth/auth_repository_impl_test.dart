import 'package:demoapi/core/errors/exceptions.dart';
import 'package:demoapi/core/errors/failures.dart';
import 'package:demoapi/core/storage/token_storage.dart';
import 'package:demoapi/feature/auth/data/data_source/auth_remote_data_source.dart';
import 'package:demoapi/feature/auth/data/model/login_request_model.dart';
import 'package:demoapi/feature/auth/data/model/login_response_model.dart';
import 'package:demoapi/feature/auth/data/repository/auth_repository_impl.dart';
import 'package:demoapi/feature/auth/domain/entity/auth_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockRemote extends Mock implements AuthRemoteDataSource {}

class MockTokenStorage extends Mock implements TokenStorage {}

void main() {
  late MockRemote remote;
  late MockTokenStorage storage;
  late AuthRepositoryImpl repository;

  setUpAll(
    () =>
        registerFallbackValue(const LoginRequestModel(email: '', password: '')),
  );

  setUp(() {
    remote = MockRemote();
    storage = MockTokenStorage();
    repository = AuthRepositoryImpl(remote, storage);
    when(
      () => storage.save(
        access: any(named: 'access'),
        refresh: any(named: 'refresh'),
      ),
    ).thenAnswer((_) async {});
  });

  test(
    'success: sends the request model, stores the token, returns entity',
    () async {
      when(() => remote.login(any()))
          .thenAnswer((_) async => const LoginResponseModel(token: 'abc'));

      final session = await repository.login(
        email: 'a@a.com',
        password: 'secret1',
      );

      expect(session, const AuthSession(token: 'abc'));
      final sent =
          verify(() => remote.login(captureAny())).captured.single
              as LoginRequestModel;
      expect(sent.toJson(), {'email': 'a@a.com', 'password': 'secret1'});
      verify(() => storage.save(access: 'abc', refresh: null)).called(1);
    },
  );

  test('400 -> ServerFailure and NO token is stored', () async {
    when(() => remote.login(any()))
        .thenThrow(const ServerException('Missing password', statusCode: 400));

    await expectLater(
      repository.login(email: 'a@a.com', password: ''),
      throwsA(
        isA<ServerFailure>().having(
          (f) => f.message,
          'message',
          'Missing password',
        ),
      ),
    );
    verifyNever(
      () => storage.save(
        access: any(named: 'access'),
        refresh: any(named: 'refresh'),
      ),
    );
  });

  test('offline -> NetworkFailure', () {
    when(() => remote.login(any()))
        .thenThrow(const NetworkException('No internet connection.'));

    expect(
      repository.login(email: 'a@a.com', password: 'x'),
      throwsA(isA<NetworkFailure>()),
    );
  });
}
