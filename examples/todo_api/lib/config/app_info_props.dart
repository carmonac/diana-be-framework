import 'package:diana/diana.dart';

part 'app_info_props.diana.dart';

/// Bound from the `app.info` section of `application.yaml` (overridable via
/// `APP_INFO_NAME` / `APP_INFO_VERSION` environment variables).
@ConfigurationProperties('app.info')
class AppInfoProps {
  final String name;
  final String version;

  const AppInfoProps({required this.name, required this.version});
}
