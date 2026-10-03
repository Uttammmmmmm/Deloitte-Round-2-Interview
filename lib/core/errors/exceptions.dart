/// Thrown by the data layer (DioClient / data sources). Never reaches the UI.
sealed class AppException implements Exception {
  const AppException(this.message);

  final String message;
}

/// The server answered with a non-2xx status code.
class ServerException extends AppException {
  const ServerException(super.message, {this.statusCode});

  final int? statusCode;
}

/// No internet, timeout, DNS failure...
class NetworkException extends AppException {
  const NetworkException(super.message);
}

/// 200 OK but the body is not valid JSON.
class ParsingException extends AppException {
  const ParsingException(super.message);
}

/// The caller cancelled the request (CancelToken). Not an error to show.
class CancelledException extends AppException {
  const CancelledException(super.message);
}
