import 'package:dio/dio.dart';

import '../storage/token_storage.dart';

/// 1. onRequest: attach the `Authorization: Bearer` header.
/// 2. onError 401: refresh once, retry the original request with the new token.
class AuthInterceptor extends Interceptor {
  AuthInterceptor({required this.storage, required this.plainDio});

  final TokenStorage storage;

  /// Dio WITHOUT this interceptor (same baseUrl) - used for refresh + retry,
  /// so a failing refresh can never trigger another refresh (infinite loop).
  final Dio plainDio;

  Future<String?>? _refreshing; // all parallel 401s share ONE refresh call

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final token = await storage.readAccess();
    if (token != null) options.headers['Authorization'] = 'Bearer $token';
    handler.next(options);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    if (err.response?.statusCode != 401) return handler.next(err);

    final newToken = await (_refreshing ??= _refresh().whenComplete(
      () => _refreshing = null,
    ));
    if (newToken == null) return handler.next(err); // refresh failed -> logout

    try {
      final retry = err.requestOptions
        ..headers['Authorization'] = 'Bearer $newToken';
      handler.resolve(await plainDio.fetch<dynamic>(retry));
    } on DioException catch (e) {
      handler.next(e);
    }
  }

  Future<String?> _refresh() async {
    final refreshToken = await storage.readRefresh();
    if (refreshToken == null) return null;
    try {
      final response = await plainDio.post<Map<String, dynamic>>(
        '/auth/refresh', // your backend's refresh endpoint
        data: {'refresh_token': refreshToken},
      );
      final access = response.data!['access_token'] as String;
      await storage.save(
        access: access,
        refresh: response.data!['refresh_token'] as String?,
      );
      return access;
    } catch (_) {
      await storage.clear(); // refresh token dead -> user must login again
      return null;
    }
  }
}
