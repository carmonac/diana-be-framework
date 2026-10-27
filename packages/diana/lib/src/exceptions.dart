/// Diana's HTTP exception hierarchy.
///
/// Throwing an [HttpException] anywhere in a handler, service or middleware
/// produces a JSON error response with the corresponding status code.
/// Exceptions not in this hierarchy result in a 500 (unless a
/// `@ControllerAdvice` handler maps them).
class HttpException implements Exception {
  final int statusCode;
  final String message;

  /// Machine-readable error identifier included in the response body.
  final String reason;

  const HttpException(this.statusCode, this.message, {this.reason = 'error'});

  @override
  String toString() => 'HttpException($statusCode, $reason): $message';
}

class BadRequestException extends HttpException {
  const BadRequestException(String message)
      : super(400, message, reason: 'bad_request');
}

class UnauthorizedException extends HttpException {
  const UnauthorizedException([String message = 'Unauthorized'])
      : super(401, message, reason: 'unauthorized');
}

class ForbiddenException extends HttpException {
  const ForbiddenException([String message = 'Forbidden'])
      : super(403, message, reason: 'forbidden');
}

class NotFoundException extends HttpException {
  const NotFoundException([String message = 'Not found'])
      : super(404, message, reason: 'not_found');
}

class ConflictException extends HttpException {
  const ConflictException(String message)
      : super(409, message, reason: 'conflict');
}

class UnsupportedMediaTypeException extends HttpException {
  const UnsupportedMediaTypeException(String message)
      : super(415, message, reason: 'unsupported_media_type');
}

class PayloadTooLargeException extends HttpException {
  const PayloadTooLargeException(String message)
      : super(413, message, reason: 'payload_too_large');
}

class NotAcceptableException extends HttpException {
  const NotAcceptableException(String message)
      : super(406, message, reason: 'not_acceptable');
}

class UnprocessableEntityException extends HttpException {
  const UnprocessableEntityException(String message)
      : super(422, message, reason: 'unprocessable_entity');
}

class InternalServerErrorException extends HttpException {
  const InternalServerErrorException([String message = 'Internal server error'])
      : super(500, message, reason: 'internal_server_error');
}

/// One field-level validation failure.
class FieldError {
  final String field;
  final String message;

  const FieldError(this.field, this.message);

  @override
  String toString() => '$field: $message';
}

/// Thrown when DTO validation fails; mapped to a structured 400 response:
/// `{"error": "validation_failed", "fields": {"title": ["..."], ...}}`.
class ValidationException implements Exception {
  final List<FieldError> errors;

  const ValidationException(this.errors);

  /// Errors grouped by field name.
  Map<String, List<String>> get fieldMap {
    final map = <String, List<String>>{};
    for (final error in errors) {
      (map[error.field] ??= []).add(error.message);
    }
    return map;
  }

  @override
  String toString() => 'ValidationException(${errors.join('; ')})';
}
