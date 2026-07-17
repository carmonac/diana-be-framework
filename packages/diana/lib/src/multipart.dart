/// Form-data support: `multipart/form-data` (file uploads) and
/// `application/x-www-form-urlencoded` bodies, bound with `@Body() FormData`.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:mime/mime.dart';

import 'exceptions.dart';
import 'http/request.dart';

/// One uploaded file from a multipart form.
class UploadedFile {
  /// The form field name.
  final String name;

  /// The client-provided file name, if any.
  final String? filename;

  /// The part's content type, if declared.
  final String? contentType;

  /// File content, buffered in memory (bounded by
  /// `server.multipart.maxSize`).
  final Uint8List bytes;

  const UploadedFile({
    required this.name,
    this.filename,
    this.contentType,
    required this.bytes,
  });

  int get size => bytes.length;
}

/// Decoded form body: text fields plus uploaded files.
class FormData {
  final Map<String, String> fields;
  final List<UploadedFile> files;

  const FormData({this.fields = const {}, this.files = const []});

  /// The first uploaded file under form field [name], or `null`.
  UploadedFile? file(String name) {
    for (final file in files) {
      if (file.name == name) return file;
    }
    return null;
  }
}

/// Decodes a `multipart/form-data` or `application/x-www-form-urlencoded`
/// body. Any other content type is a 415; a multipart body larger than
/// `request.limits.multipartMaxBytes` is a 413 (the raw stream — including
/// part headers and boundaries — is capped by [DianaRequest.readBodyAsBytes];
/// the per-part sum below is a second, decoded-content check). Urlencoded
/// bodies are capped at `request.limits.maxBodyBytes` by the string read.
Future<FormData> decodeFormBody(DianaRequest request) async {
  final contentType = request.header('content-type') ?? '';
  final mime = contentType.split(';').first.trim().toLowerCase();

  if (mime == 'application/x-www-form-urlencoded') {
    final body = await request.readBodyAsString();
    return FormData(fields: Uri.splitQueryString(body));
  }
  if (mime != 'multipart/form-data') {
    throw UnsupportedMediaTypeException(
      "Expected 'multipart/form-data' or "
      "'application/x-www-form-urlencoded', got '$mime'.",
    );
  }

  final boundary = _boundaryOf(contentType);
  if (boundary == null) {
    throw const BadRequestException(
        'Malformed multipart body: missing boundary.');
  }

  final maxBytes = request.limits.multipartMaxBytes;
  var total = 0;
  final fields = <String, String>{};
  final files = <UploadedFile>[];

  final parts = request
      .readBodyAsBytes()
      .cast<List<int>>()
      .transform(MimeMultipartTransformer(boundary));
  await for (final part in parts) {
    final disposition = part.headers['content-disposition'] ?? '';
    final name = _dispositionParam(disposition, 'name');
    if (name == null) continue;
    final filename = _dispositionParam(disposition, 'filename');

    final builder = BytesBuilder(copy: false);
    await for (final chunk in part) {
      total += chunk.length;
      if (total > maxBytes) {
        throw PayloadTooLargeException(
          'Multipart body exceeds the configured limit of $maxBytes bytes.',
        );
      }
      builder.add(chunk);
    }
    final bytes = builder.takeBytes();

    if (filename == null && part.headers['content-type'] == null) {
      try {
        fields[name] = utf8.decode(bytes);
      } on FormatException {
        throw BadRequestException(
            "Multipart field '$name' is not valid UTF-8.");
      }
    } else {
      files.add(UploadedFile(
        name: name,
        filename: filename,
        contentType: part.headers['content-type'],
        bytes: bytes,
      ));
    }
  }
  return FormData(fields: fields, files: files);
}

String? _boundaryOf(String contentType) {
  for (final param in contentType.split(';').skip(1)) {
    final trimmed = param.trim();
    if (trimmed.startsWith('boundary=')) {
      var value = trimmed.substring('boundary='.length);
      if (value.startsWith('"') && value.endsWith('"') && value.length > 1) {
        value = value.substring(1, value.length - 1);
      }
      return value;
    }
  }
  return null;
}

String? _dispositionParam(String disposition, String name) {
  final match =
      RegExp('$name="([^"]*)"').firstMatch(disposition) ??
          RegExp('$name=([^;\\s]+)').firstMatch(disposition);
  return match?.group(1);
}
