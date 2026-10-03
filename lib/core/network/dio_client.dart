import 'package:dio/dio.dart';

import '../errors/exceptions.dart';

/// Thin wrapper over Dio: one place for every HTTP verb and for
/// DioException -> AppException mapping.
class DioClient {
  const DioClient(this._dio);

  final Dio _dio;

  Future<dynamic> get(
    String path, {
    Map<String, dynamic>? query,
    CancelToken? cancelToken,
  }) => _send(
    () => _dio.get<dynamic>(
      path,
      queryParameters: query,
      cancelToken: cancelToken,
    ),
  );

  Future<dynamic> post(String path, {Object? data, CancelToken? cancelToken}) =>
      _send(
        () => _dio.post<dynamic>(path, data: data, cancelToken: cancelToken),
      );

  Future<dynamic> put(String path, {Object? data, CancelToken? cancelToken}) =>
      _send(
        () => _dio.put<dynamic>(path, data: data, cancelToken: cancelToken),
      );

  Future<dynamic> patch(
    String path, {
    Object? data,
    CancelToken? cancelToken,
  }) => _send(
    () => _dio.patch<dynamic>(path, data: data, cancelToken: cancelToken),
  );

  Future<dynamic> delete(String path, {CancelToken? cancelToken}) =>
      _send(() => _dio.delete<dynamic>(path, cancelToken: cancelToken));

  Future<dynamic> _send(Future<Response<dynamic>> Function() request) async {
    try {
      return (await request()).data;
    } on DioException catch (e) {
      throw _toException(e);
    }
  }

  AppException _toException(DioException e) => switch (e.type) {
    DioExceptionType.connectionTimeout ||
    DioExceptionType.sendTimeout ||
    DioExceptionType.receiveTimeout => const NetworkException(
      'Request timed out. Please try again.',
    ),
    DioExceptionType.connectionError => const NetworkException(
      'No internet connection.',
    ),
    DioExceptionType.cancel => const CancelledException('Request cancelled.'),
    DioExceptionType.badResponse => ServerException(
      _bodyMessage(e.response) ?? _defaultMessage(e.response?.statusCode),
      statusCode: e.response?.statusCode,
    ),
    // Dio wraps a JSON decoding error as `unknown` + FormatException.
    DioExceptionType.unknown when e.error is FormatException =>
      const ParsingException('Invalid response from server.'),
    _ => const NetworkException('Network error. Please try again.'),
  };

  /// reqres returns {"error": "..."}; many APIs use {"message": "..."}.
  String? _bodyMessage(Response<dynamic>? response) {
    final data = response?.data;
    if (data is! Map) return null;
    final message = data['error'] ?? data['message'];
    return message is String ? message : null;
  }

  String _defaultMessage(int? code) => switch (code) {
    400 => 'Bad request.',
    401 => 'Please login again.',
    403 => 'You do not have access.',
    404 => 'Not found.',
    422 => 'Validation failed.',
    final int c when c >= 500 => 'Server error. Please try later.',
    _ => 'Unexpected server response ($code).',
  };
}
