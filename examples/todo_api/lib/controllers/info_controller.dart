import 'package:diana/diana.dart';

import '../config/app_info_props.dart';

part 'info_controller.diana.dart';

@RestController('/info')
@CrossOrigin(origins: ['https://dashboard.example'])
class InfoController {
  final AppInfoProps info;

  InfoController(this.info);

  @Get()
  Map<String, dynamic> get() => {'name': info.name, 'version': info.version};
}
