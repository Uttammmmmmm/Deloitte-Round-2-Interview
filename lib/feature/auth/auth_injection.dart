import 'package:get_it/get_it.dart';

import 'data/data_source/auth_remote_data_source.dart';
import 'data/repository/auth_repository_impl.dart';
import 'domain/repository/auth_repository.dart';
import 'domain/usecase/login.dart';
import 'presentation/cubit/login_cubit.dart';

/// Per-feature DI module: registers only this feature's classes. It needs
/// DioClient and TokenStorage from core, which are registered lazily in
/// `initDependencies()`, so call order doesn't matter.
void registerAuthFeature(GetIt sl) {
  sl
    ..registerLazySingleton<AuthRemoteDataSource>(
      () => AuthRemoteDataSourceImpl(sl()),
    )
    ..registerLazySingleton<AuthRepository>(
      () => AuthRepositoryImpl(sl(), sl()),
    )
    ..registerLazySingleton(() => Login(sl()))
    ..registerFactory(() => LoginCubit(sl()));
}
