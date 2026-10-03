import 'package:demoapi/core/network/safe_log_interceptor.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_adapter.dart';

void main() {
  late List<String> logs;
  late DebugPrintCallback originalDebugPrint;

  setUp(() {
    logs = [];
    originalDebugPrint = debugPrint;
    debugPrint = (message, {wrapWidth}) => logs.add(message ?? '');
  });
  tearDown(() => debugPrint = originalDebugPrint);

  Dio dioReturning(int status) => Dio(BaseOptions(baseUrl: 'http://api.test'))
    ..httpClientAdapter = FakeAdapter(
      (_) => json({'password': 'hunter2', 'token': 'SECRET'}, status),
    )
    ..interceptors.add(SafeLogInterceptor());

  test('logs method, url and status only', () async {
    await dioReturning(200).post<dynamic>(
      '/login',
      data: {'password': 'hunter2'},
      options: Options(headers: {'Authorization': 'Bearer SECRET'}),
    );

    final all = logs.join('\n');
    expect(all, contains('-> POST http://api.test/login'));
    expect(all, contains('<- 200 http://api.test/login'));
  });

  test('NEVER logs tokens, passwords or response bodies', () async {
    await dioReturning(200).post<dynamic>(
      '/login',
      data: {'password': 'hunter2'},
      options: Options(headers: {'Authorization': 'Bearer SECRET'}),
    );

    final all = logs.join('\n');
    expect(all, isNot(contains('SECRET')));
    expect(all, isNot(contains('hunter2')));
    expect(all, isNot(contains('Authorization')));
  });

  test('errors log status and type, still without the body', () async {
    await expectLater(
      dioReturning(500).get<dynamic>('/users'),
      throwsA(isA<DioException>()),
    );

    final all = logs.join('\n');
    expect(all, contains('x  500 http://api.test/users badResponse'));
    expect(all, isNot(contains('SECRET')));
  });
}
