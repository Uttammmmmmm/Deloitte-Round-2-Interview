import 'package:demoapi/core/network/auth_interceptor.dart';
import 'package:demoapi/core/storage/token_storage.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../helpers/fake_adapter.dart';

class MockTokenStorage extends Mock implements TokenStorage {}

void main() {
  late MockTokenStorage storage;
  late String access;
  String? refreshToken;
  late int refreshCalls;
  late bool refreshWorks;

  Dio buildDio({int? alwaysStatus}) {
    final adapter = FakeAdapter((o) {
      if (o.path == '/auth/refresh') {
        refreshCalls++;
        return refreshWorks
            ? json({'access_token': 'new'}, 200)
            : json({'error': 'refresh expired'}, 401);
      }
      if (alwaysStatus != null) {
        return json({'status': alwaysStatus}, alwaysStatus);
      }
      // a "server" that only accepts the NEW token
      return o.headers['Authorization'] == 'Bearer new'
          ? json({'ok': true}, 200)
          : json({'error': 'expired'}, 401);
    });
    final plain = Dio(BaseOptions(baseUrl: 'http://api.test'))
      ..httpClientAdapter = adapter;
    return Dio(BaseOptions(baseUrl: 'http://api.test'))
      ..httpClientAdapter = adapter
      ..interceptors.add(AuthInterceptor(storage: storage, plainDio: plain));
  }

  setUp(() {
    storage = MockTokenStorage();
    access = 'old';
    refreshToken = 'refresh';
    refreshCalls = 0;
    refreshWorks = true;
    when(() => storage.readAccess()).thenAnswer((_) async => access);
    when(() => storage.readRefresh()).thenAnswer((_) async => refreshToken);
    when(
      () => storage.save(
        access: any(named: 'access'),
        refresh: any(named: 'refresh'),
      ),
    ).thenAnswer((i) async => access = i.namedArguments[#access] as String);
    when(() => storage.clear()).thenAnswer((_) async {});
  });

  test('attaches "Authorization: Bearer <token>" to every request', () async {
    final dio = buildDio(alwaysStatus: 200);

    await dio.get<dynamic>('/users');

    final adapter = dio.httpClientAdapter as FakeAdapter;
    expect(adapter.requests.single.headers['Authorization'], 'Bearer old');
  });

  test('no token stored -> no Authorization header', () async {
    when(() => storage.readAccess()).thenAnswer((_) async => null);
    final dio = buildDio(alwaysStatus: 200);

    await dio.get<dynamic>('/users');

    final adapter = dio.httpClientAdapter as FakeAdapter;
    expect(
      adapter.requests.single.headers.containsKey('Authorization'),
      isFalse,
    );
  });

  test(
    '401 -> refresh -> retries the original request with the new token',
    () async {
      final dio = buildDio();

      final response = await dio.get<dynamic>('/users');

      expect(response.data, {'ok': true});
      expect(refreshCalls, 1);
      verify(() => storage.save(access: 'new', refresh: null)).called(1);
    },
  );

  test('parallel 401s share ONE refresh call', () async {
    final dio = buildDio();

    final results = await Future.wait([
      dio.get<dynamic>('/a'),
      dio.get<dynamic>('/b'),
      dio.get<dynamic>('/c'),
    ]);

    expect(results.map((r) => r.statusCode), everyElement(200));
    expect(refreshCalls, 1);
  });

  test('refresh fails -> storage cleared, original 401 is surfaced', () async {
    refreshWorks = false;
    final dio = buildDio();

    await expectLater(
      dio.get<dynamic>('/users'),
      throwsA(
        isA<DioException>().having(
          (e) => e.response?.statusCode,
          'status',
          401,
        ),
      ),
    );

    expect(refreshCalls, 1);
    verify(() => storage.clear()).called(1);
  });

  test('no refresh token -> does not call the refresh endpoint', () async {
    refreshToken = null;
    final dio = buildDio();

    await expectLater(dio.get<dynamic>('/users'), throwsA(isA<DioException>()));

    expect(refreshCalls, 0);
  });

  test('non-401 errors pass through untouched (no refresh)', () async {
    final dio = buildDio(alwaysStatus: 500);

    await expectLater(
      dio.get<dynamic>('/users'),
      throwsA(
        isA<DioException>().having(
          (e) => e.response?.statusCode,
          'status',
          500,
        ),
      ),
    );

    expect(refreshCalls, 0);
  });

  test(
    'retry with the NEW token still 401 -> error surfaced, no refresh loop',
    () async {
      final adapter = FakeAdapter((o) {
        if (o.path == '/auth/refresh') {
          refreshCalls++;
          return json({'access_token': 'new'}, 200);
        }
        return json({
          'error': 'still unauthorized',
        }, 401); // even for the new token
      });
      final plain = Dio(BaseOptions(baseUrl: 'http://api.test'))
        ..httpClientAdapter = adapter;
      final dio = Dio(BaseOptions(baseUrl: 'http://api.test'))
        ..httpClientAdapter = adapter
        ..interceptors.add(AuthInterceptor(storage: storage, plainDio: plain));

      await expectLater(
        dio.get<dynamic>('/users'),
        throwsA(
          isA<DioException>().having(
            (e) => e.response?.statusCode,
            'status',
            401,
          ),
        ),
      );

      expect(refreshCalls, 1, reason: 'one refresh, not a loop');
    },
  );
}
