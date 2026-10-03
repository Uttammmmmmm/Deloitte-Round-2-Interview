import 'package:demoapi/core/errors/exceptions.dart';
import 'package:demoapi/core/errors/failures.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('guard(): every exception maps to exactly one failure', () {
    Future<void> failWith(Object error) => guard<void>(() async => throw error);

    test('401 and 403 -> UnauthorizedFailure', () async {
      await expectLater(
        failWith(const ServerException('x', statusCode: 401)),
        throwsA(isA<UnauthorizedFailure>()),
      );
      await expectLater(
        failWith(const ServerException('x', statusCode: 403)),
        throwsA(isA<UnauthorizedFailure>()),
      );
    });

    test(
      '422 -> ValidationFailure; 500 -> ServerFailure with status',
      () async {
        await expectLater(
          failWith(const ServerException('bad', statusCode: 422)),
          throwsA(isA<ValidationFailure>()),
        );
        await expectLater(
          failWith(const ServerException('boom', statusCode: 500)),
          throwsA(
            isA<ServerFailure>().having((f) => f.statusCode, 'status', 500),
          ),
        );
      },
    );

    test('FormatException -> ParsingFailure', () async {
      await expectLater(
        failWith(const FormatException('bad json')),
        throwsA(isA<ParsingFailure>()),
      );
    });

    test('returns the value when nothing throws', () async {
      expect(await guard(() async => 42), 42);
    });
  });

  test('failures have value equality (message / status)', () {
    expect(
      const ServerFailure('x', statusCode: 500),
      const ServerFailure('x', statusCode: 500),
    );
    expect(
      const ServerFailure('x', statusCode: 500),
      isNot(const ServerFailure('x', statusCode: 404)),
    );
    expect(const NetworkFailure('a'), const NetworkFailure('a'));
  });

  test('user-facing messages never contain technical details', () {
    final unknown = UnknownFailure(
      cause: StateError('secret internals'),
      stackTrace: StackTrace.current,
    );

    expect(unknown.message, isNot(contains('secret internals')));
    expect(unknown.cause, isA<StateError>());
  });
}
