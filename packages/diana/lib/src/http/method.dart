/// HTTP methods supported by Diana routes.
enum HttpMethod {
  get,
  head,
  post,
  put,
  delete,
  patch,
  options;

  /// Parses an upper- or lower-case method name.
  static HttpMethod parse(String name) => HttpMethod.values.firstWhere(
        (m) => m.name == name.toLowerCase(),
        orElse: () =>
            throw ArgumentError.value(name, 'name', 'Unknown HTTP method'),
      );
}
