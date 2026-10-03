import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:get_it/get_it.dart';

import '../../feature/auth/auth_injection.dart';
import '../../feature/user/data/data_source/user_remote_data_source.dart';
import '../../feature/user/data/data_source/user_remote_data_source_impl.dart';
import '../../feature/user/data/repository/user_repository_impl.dart';
import '../../feature/user/domain/repository/user_repository.dart';
import '../../feature/user/domain/usecase/get_users.dart';
import '../../feature/user/presentation/cubit/user_cubit.dart';
import '../constants/api_constants.dart';
import '../network/auth_interceptor.dart';
import '../network/dio_client.dart';
import '../network/safe_log_interceptor.dart';
import '../storage/token_storage.dart';

final sl = GetIt.instance;

/// Composition root. Registrations are lazy, so their order never matters.
void initDependencies() {
  sl
    // core
    ..registerLazySingleton(() => const TokenStorage(FlutterSecureStorage()))
    ..registerLazySingleton<Dio>(() => createDio(sl()))
    ..registerLazySingleton(() => DioClient(sl()))
    // user feature (bottom -> top)
    ..registerLazySingleton<UserRemoteDataSource>(
      () => UserRemoteDataSourceImpl(sl()),
    )
    ..registerLazySingleton<UserRepository>(() => UserRepositoryImpl(sl()))
    ..registerLazySingleton(() => GetUsers(sl()))
    ..registerFactory(() => UserCubit(sl())); // factory: new Cubit per screen

  registerAuthFeature(sl);
}

/// The ONE place Dio is built: base options, auth interceptor, debug logging.
@visibleForTesting
Dio createDio(TokenStorage tokenStorage) {
  final dio = Dio(_baseOptions());
  dio.interceptors.add(
    AuthInterceptor(
      storage: tokenStorage,
      plainDio: Dio(_baseOptions()), // no interceptors: used to refresh + retry
    ),
  );
  if (kDebugMode) {
    dio.interceptors.add(SafeLogInterceptor()); // never in release
  }
  return dio;
}

BaseOptions _baseOptions() => BaseOptions(
  baseUrl: ApiConstants.baseUrl,
  connectTimeout: ApiConstants.timeout,
  receiveTimeout: ApiConstants.timeout,
  headers: {'Accept': 'application/json'},
);
