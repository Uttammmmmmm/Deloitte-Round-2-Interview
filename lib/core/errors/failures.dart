import 'package:equatable/equatable.dart';

import 'exceptions.dart';

/// What the domain / Cubit understands. [message] is always user-safe.
sealed class Failure extends Equatable implements Exception {
  const Failure(this.message, {this.cause, this.stackTrace});

  final String message;

  /// Technical reason. NEVER shown to users; forwarded to `Bloc.observer.onError`
  /// (see `reportFailure`) so unexpected problems reach your logger/crash tool.
  final Object? cause;
  final StackTrace? stackTrace;

  @override
  List<Object?> get props => [message];
}

class ServerFailure extends Failure {
  const ServerFailure(super.message, {this.statusCode});

  final int? statusCode;

  @override
  List<Object?> get props => [message, statusCode];
}

class UnauthorizedFailure extends Failure {
  const UnauthorizedFailure(super.message);
}

/// 422 / client-side validation: show the message next to the form.
class ValidationFailure extends Failure {
  const ValidationFailure(super.message);
}

class NetworkFailure extends Failure {
  const NetworkFailure(super.message);
}

/// The request was cancelled on purpose: callers ignore it, no error UI.
class CancelledFailure extends Failure {
  const CancelledFailure() : super('Request cancelled.');
}

class ParsingFailure extends Failure {
  const ParsingFailure({super.cause, super.stackTrace})
    : super('Unexpected data received from server.');
}

class UnknownFailure extends Failure {
  const UnknownFailure({super.cause, super.stackTrace})
    : super('Something went wrong. Please try again.');
}

/// Repositories wrap every data-source call in this: Exception -> Failure, once.
/// Technical causes are kept on the Failure, never swallowed.
Future<T> guard<T>(Future<T> Function() action) async {
  try {
    return await action();
  } on ServerException catch (e) {
    throw switch (e.statusCode) {
      401 || 403 => UnauthorizedFailure(e.message),
      422 => ValidationFailure(e.message),
      _ => ServerFailure(e.message, statusCode: e.statusCode),
    };
  } on NetworkException catch (e) {
    throw NetworkFailure(e.message);
  } on CancelledException {
    throw const CancelledFailure();
  } on ParsingException catch (e, s) {
    throw ParsingFailure(cause: e, stackTrace: s); // body is not valid JSON
  } on TypeError catch (e, s) {
    throw ParsingFailure(cause: e, stackTrace: s); // wrong shape: null / type
  } on FormatException catch (e, s) {
    throw ParsingFailure(cause: e, stackTrace: s);
  } catch (e, s) {
    throw UnknownFailure(cause: e, stackTrace: s);
  }
}
