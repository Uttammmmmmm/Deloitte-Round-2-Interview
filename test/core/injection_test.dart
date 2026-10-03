import 'package:demoapi/core/di/injection.dart';
import 'package:demoapi/core/network/auth_interceptor.dart';
import 'package:demoapi/core/storage/token_storage.dart';
import 'package:demoapi/feature/auth/presentation/cubit/login_cubit.dart';
import 'package:demoapi/feature/user/presentation/cubit/user_cubit.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() async {
    await sl.reset();
    initDependencies();
  });
  tearDown(() => sl.reset());

  test('the whole graph resolves (catches wiring mistakes at test time)', () {
    expect(sl<UserCubit>(), isA<UserCubit>());
    expect(sl<LoginCubit>(), isA<LoginCubit>());
  });

  test('Cubits are factories: every request gets a NEW instance', () {
    expect(identical(sl<UserCubit>(), sl<UserCubit>()), isFalse);
  });

  test(
    'Dio is a singleton with baseUrl, timeouts and the auth interceptor',
    () {
      final dio = sl<Dio>();

      expect(identical(dio, sl<Dio>()), isTrue);
      expect(dio.options.baseUrl, 'https://reqres.in/api');
      expect(dio.options.connectTimeout, isNotNull);
      expect(dio.interceptors.whereType<AuthInterceptor>(), hasLength(1));
    },
  );

  test('createDio does not need call-order tricks', () {
    final dio = createDio(const TokenStorage(FlutterSecureStorage()));

    expect(dio.interceptors.whereType<AuthInterceptor>(), hasLength(1));
  });
}
