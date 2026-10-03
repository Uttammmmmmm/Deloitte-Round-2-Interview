import 'package:demoapi/core/errors/exceptions.dart';
import 'package:demoapi/core/errors/failures.dart';
import 'package:demoapi/feature/user/data/data_source/user_remote_data_source.dart';
import 'package:demoapi/feature/user/data/model/user_model.dart';
import 'package:demoapi/feature/user/data/model/users_response_model.dart';
import 'package:demoapi/feature/user/data/repository/user_repository_impl.dart';
import 'package:mocktail/mocktail.dart';
import 'package:flutter_test/flutter_test.dart';

class MockRemote extends Mock implements UserRemoteDataSource {}

void main() {
  late MockRemote remote;
  late UserRepositoryImpl repository;

  setUp(() {
    remote = MockRemote();
    repository = UserRepositoryImpl(remote);
  });

  test('maps model -> entity on success', () async {
    when(() => remote.getUsers(page: 1)).thenAnswer(
      (_) async => const UsersResponseModel(
        page: 1,
        perPage: 6,
        total: 12,
        totalPages: 2,
        data: [
          UserModel(
            id: 1,
            email: 'a@a.com',
            firstName: 'A',
            lastName: 'One',
            avatar: '',
          ),
        ],
      ),
    );

    final result = await repository.getUsers(page: 1);

    expect(result.users.single.fullName, 'A One');
    expect(result.hasNext, isTrue);
  });

  test('ServerException(404) -> ServerFailure', () {
    when(() => remote.getUsers(page: 1))
        .thenThrow(const ServerException('Not found.', statusCode: 404));

    expect(repository.getUsers(page: 1), throwsA(isA<ServerFailure>()));
  });

  test('ServerException(401) -> UnauthorizedFailure', () {
    when(
      () => remote.getUsers(page: 1),
    ).thenThrow(const ServerException('Please login again.', statusCode: 401));

    expect(repository.getUsers(page: 1), throwsA(isA<UnauthorizedFailure>()));
  });

  test('ServerException(422) -> ValidationFailure', () {
    when(() => remote.getUsers(page: 1))
        .thenThrow(const ServerException('Email is invalid.', statusCode: 422));

    expect(repository.getUsers(page: 1), throwsA(isA<ValidationFailure>()));
  });

  test('NetworkException -> NetworkFailure', () {
    when(() => remote.getUsers(page: 1))
        .thenThrow(const NetworkException('No internet connection.'));

    expect(repository.getUsers(page: 1), throwsA(isA<NetworkFailure>()));
  });

  test('bad JSON shape (TypeError) -> ParsingFailure', () {
    when(() => remote.getUsers(page: 1))
        .thenAnswer((_) async => UsersResponseModel.fromJson({'page': 'oops'}));

    expect(repository.getUsers(page: 1), throwsA(isA<ParsingFailure>()));
  });

  test('CancelledException -> CancelledFailure', () {
    when(() => remote.getUsers(page: 1))
        .thenThrow(const CancelledException('Request cancelled.'));

    expect(repository.getUsers(page: 1), throwsA(isA<CancelledFailure>()));
  });

  test('ParsingFailure keeps the technical cause for logging', () async {
    when(() => remote.getUsers(page: 1))
        .thenAnswer((_) async => UsersResponseModel.fromJson({'page': 'oops'}));

    await expectLater(
      repository.getUsers(page: 1),
      throwsA(
        isA<ParsingFailure>()
            .having((f) => f.cause, 'cause', isA<TypeError>())
            .having((f) => f.stackTrace, 'stackTrace', isNotNull)
            .having(
              (f) => f.message,
              'user-safe message',
              isNot(contains('type')),
            ),
      ),
    );
  });

  test('unknown errors become UnknownFailure and keep cause + stack', () async {
    when(() => remote.getUsers(page: 1)).thenThrow(StateError('boom'));

    await expectLater(
      repository.getUsers(page: 1),
      throwsA(
        isA<UnknownFailure>()
            .having((f) => f.cause, 'cause', isA<StateError>())
            .having((f) => f.stackTrace, 'stackTrace', isNotNull),
      ),
    );
  });
}
