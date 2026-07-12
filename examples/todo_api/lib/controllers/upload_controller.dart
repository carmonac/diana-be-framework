import 'package:diana/diana.dart';

part 'upload_controller.diana.dart';

/// File uploads via `@Body() FormData` (multipart/form-data or
/// x-www-form-urlencoded), plus a raw-text echo via `@Body() String`.
@RestController('/uploads')
class UploadController {
  @Post()
  @ResponseStatus(201)
  Map<String, dynamic> upload(@Body() FormData body) => {
        'fields': body.fields,
        'files': [
          for (final file in body.files)
            {
              'name': file.name,
              'filename': file.filename,
              'contentType': file.contentType,
              'size': file.size,
            },
        ],
      };

  @Post('/echo')
  String echo(@Body() String body) => body.toUpperCase();
}
