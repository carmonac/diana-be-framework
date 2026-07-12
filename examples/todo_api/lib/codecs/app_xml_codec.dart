import 'package:diana/diana.dart';

/// Registers the built-in XML codec: any route annotated with
/// `@Consumes(['application/xml'])` / `@Produces(['application/xml'])` can
/// now speak XML.
@Component()
class AppXmlCodec extends XmlCodec {}
