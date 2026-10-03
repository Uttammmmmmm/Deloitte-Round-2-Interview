import 'package:demoapi/core/errors/exceptions.dart';
import 'package:demoapi/core/network/dio_client.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockDio extends Mock implements Dio {}

void main() {
  late MockDio dio;
  late DioClient client;

  setUp(() {
    dio = MockDio();
    client = DioClient(dio);
  });

  final options = RequestOptions(path: '/x');
  Response<dynamic> ok(Object? data) =>
      Response(requestOptions: options, data: data);

  DioException badResponse(int code, [Object? body]) => DioException(
    requestOptions: options,
    type: DioExceptionType.badResponse,
    response: Response(requestOptions: options, statusCode: code, data: body),
  );

  void stubGet(Object Function() answer) {
    when(
      () => dio.get<dynamic>(
        '/x',
        queryParameters: any(named: 'queryParameters'),
        cancelToken: any(named: 'cancelToken'),
      ),
    ).thenAnswer((_) async {
      final a = answer();
      if (a is Exception) throw a;
      return ok(a);
    });
  }

  group('success', () {
    test('GET returns response.data', () async {
      stubGet(() => {'ok': true});
      expect(await client.get('/x'), {'ok': true});
    });

    test('POST / PUT / PATCH / DELETE use the right Dio method', () async {
      when(
        () => dio.post<dynamic>(
          '/x',
          data: any(named: 'data'),
          cancelToken: any(named: 'cancelToken'),
        ),
      ).thenAnswer((_) async => ok('post'));
      when(
        () => dio.put<dynamic>(
          '/x',
          data: any(named: 'data'),
          cancelToken: any(named: 'cancelToken'),
        ),
      ).thenAnswer((_) async => ok('put'));
      when(
        () => dio.patch<dynamic>(
          '/x',
          data: any(named: 'data'),
          cancelToken: any(named: 'cancelToken'),
        ),
      ).thenAnswer((_) async => ok('patch'));
      when(
        () => dio.delete<dynamic>('/x', cancelToken: any(named: 'cancelToken')),
      ).thenAnswer((_) async => ok(''));

      expect(await client.post('/x', data: {'a': 1}), 'post');
      expect(await client.put('/x', data: {'a': 1}), 'put');
      expect(await client.patch('/x', data: {'a': 1}), 'patch');
      expect(await client.delete('/x'), '');
      verify(() => dio.post<dynamic>('/x', data: {'a': 1})).called(1);
    });

    test('forwards the CancelToken to Dio', () async {
      final token = CancelToken();
      when(
        () => dio.get<dynamic>(
          '/x',
          queryParameters: any(named: 'queryParameters'),
          cancelToken: token,
        ),
      ).thenAnswer((_) async => ok(1));

      await client.get('/x', cancelToken: token);

      verify(
        () => dio.get<dynamic>('/x', queryParameters: null, cancelToken: token),
      ).called(1);
    });
  });

  group('errors', () {
    test('400 {"error": ...} -> ServerException with that message', () {
      stubGet(() => badResponse(400, {'error': 'Missing password'}));

      expect(
        client.get('/x'),
        throwsA(
          isA<ServerException>()
              .having((e) => e.message, 'message', 'Missing password')
              .having((e) => e.statusCode, 'statusCode', 400),
        ),
      );
    });

    test('{"message": ...} is understood too', () {
      stubGet(() => badResponse(422, {'message': 'Email is invalid'}));

      expect(
        client.get('/x'),
        throwsA(
          isA<ServerException>().having(
            (e) => e.message,
            'message',
            'Email is invalid',
          ),
        ),
      );
    });

    test('no body: falls back to a default message per status', () {
      stubGet(() => badResponse(404));

      expect(
        client.get('/x'),
        throwsA(
          isA<ServerException>().having((e) => e.message, 'm', 'Not found.'),
        ),
      );
    });

    test('5xx -> "Server error" message', () {
      stubGet(() => badResponse(503));

      expect(
        client.get('/x'),
        throwsA(
          isA<ServerException>().having(
            (e) => e.message,
            'm',
            contains('Server error'),
          ),
        ),
      );
    });

    test('timeout -> NetworkException', () {
      stubGet(
        () => DioException(
          requestOptions: options,
          type: DioExceptionType.receiveTimeout,
        ),
      );
      expect(client.get('/x'), throwsA(isA<NetworkException>()));
    });

    test('connection error -> NetworkException "No internet"', () {
      stubGet(
        () => DioException(
          requestOptions: options,
          type: DioExceptionType.connectionError,
        ),
      );
      expect(
        client.get('/x'),
        throwsA(
          isA<NetworkException>().having(
            (e) => e.message,
            'm',
            'No internet connection.',
          ),
        ),
      );
    });

    test('cancelled request -> CancelledException (not a network error)', () {
      stubGet(
        () => DioException(
          requestOptions: options,
          type: DioExceptionType.cancel,
        ),
      );
      expect(client.get('/x'), throwsA(isA<CancelledException>()));
    });

    test('invalid JSON body -> ParsingException (not a network error)', () {
      stubGet(
        () => DioException(
          requestOptions: options,
          type: DioExceptionType.unknown,
          error: const FormatException('Unexpected character'),
        ),
      );
      expect(client.get('/x'), throwsA(isA<ParsingException>()));
    });
  });
}
