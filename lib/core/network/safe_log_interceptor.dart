import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// Logs ONLY method, url, status. Never headers (Authorization), never bodies
/// (passwords, tokens, PII). Register it only in debug builds.
class SafeLogInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    debugPrint('-> ${options.method} ${options.uri}');
    handler.next(options);
  }

  @override
  void onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) {
    debugPrint('<- ${response.statusCode} ${response.requestOptions.uri}');
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    debugPrint(
      'x  ${err.response?.statusCode} ${err.requestOptions.uri} ${err.type.name}',
    );
    handler.next(err);
  }
}
