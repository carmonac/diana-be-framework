// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import

part of 'upload_controller.dart';

Future<DianaResponse> $diana$UploadController$upload(
  UploadController c,
  DianaRequest req,
) async {
  final $a0 = await decodeFormBody(req);
  final result = c.upload($a0);
  return DianaResponse.json(result, statusCode: 201);
}

Future<DianaResponse> $diana$UploadController$echo(
  UploadController c,
  DianaRequest req,
) async {
  final $a0 = await req.readBodyAsString();
  final result = c.echo($a0);
  return DianaResponse.text(result);
}
