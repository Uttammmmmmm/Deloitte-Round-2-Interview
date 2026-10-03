import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/errors/report_failure.dart';
import '../../domain/usecase/login.dart';
import 'login_state.dart';

class LoginCubit extends Cubit<LoginState> with FailureReporting<LoginState> {
  LoginCubit(this._login) : super(const LoginInitial());

  final Login _login;

  Future<void> login({required String email, required String password}) async {
    if (state is LoginLoading) return; // ignore double taps
    emit(const LoginLoading());
    try {
      await _login(email: email, password: password);
      if (!isClosed) emit(const LoginSuccess());
    } on Failure catch (failure) {
      reportFailure(failure);
      if (!isClosed) emit(LoginError(failure.message));
    }
  }
}
