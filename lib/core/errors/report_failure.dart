import 'package:flutter_bloc/flutter_bloc.dart';

import 'failures.dart';

mixin FailureReporting<S> on BlocBase<S> {
  /// Forwards the hidden technical cause of a [Failure] (parsing/unknown) to
  /// `Bloc.observer.onError`: one place to plug Crashlytics/Sentry.
  /// Expected failures (offline, 401, 422...) have no cause and are not reported.
  void reportFailure(Failure failure) {
    final cause = failure.cause;
    if (cause != null) addError(cause, failure.stackTrace);
  }
}
