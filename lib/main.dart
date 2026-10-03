import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'core/di/injection.dart';
import 'core/errors/app_bloc_observer.dart';
import 'feature/auth/presentation/cubit/login_cubit.dart';
import 'feature/auth/presentation/pages/login_page.dart';
import 'feature/user/presentation/cubit/user_cubit.dart';
import 'feature/user/presentation/pages/user_page.dart';

void main() {
  initDependencies();
  Bloc.observer = AppBlocObserver();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    routes: {
      '/': (_) => BlocProvider(
        create: (_) => sl<UserCubit>()..fetchUsers(),
        child: const UserPage(),
      ),
      '/login': (_) => BlocProvider(
        create: (_) => sl<LoginCubit>(),
        child: const LoginPage(),
      ),
    },
  );
}
