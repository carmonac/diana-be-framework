/// Built-in XML body codec.
///
/// Enable it by registering an injectable subclass:
///
/// ```dart
/// @Component()
/// class AppXmlCodec extends XmlCodec {}
/// ```
///
/// ## The XML ↔ Map convention
///
/// Decode (`application/xml` body → `Map<String, dynamic>`):
/// - the root element's name is ignored;
/// - child elements become map keys; nested elements become nested maps;
/// - repeated same-name siblings become a `List`;
/// - an element whose children are all `<item>` becomes a `List`;
/// - leaf text becomes a scalar with inference: `int` → `double` →
///   `true`/`false` → `String`;
/// - an empty element decodes to `null`;
/// - attributes are **ignored** (documented limitation).
///
/// Encode (`Map`/`List`/scalar → XML): root element `<response>`; map
/// entries become child elements; a list under key `k` emits repeated
/// `<k>` elements; a top-level `List` emits `<item>` children; `null`
/// emits an empty element.
///
/// Known asymmetry: a single-element list decodes as a scalar (XML cannot
/// distinguish them).
library;

import 'package:xml/xml.dart';

import 'codec.dart';

class XmlCodec implements BodyCodec {
  const XmlCodec();

  @override
  List<String> get mimeTypes => const ['application/xml', 'text/xml'];

  @override
  Object? decode(String body) {
    final XmlDocument document;
    try {
      document = XmlDocument.parse(body);
    } on XmlException catch (e) {
      throw FormatException('Invalid XML: ${e.message}');
    }
    return _decodeElement(document.rootElement);
  }

  @override
  String encode(Object? value) {
    final builder = XmlBuilder();
    builder.element('response', nest: () => _encodeValue(builder, value));
    return builder.buildDocument().toXmlString();
  }

  Object? _decodeElement(XmlElement element) {
    final children = element.childElements.toList();
    if (children.isEmpty) {
      final text = element.innerText;
      return text.isEmpty ? null : _inferScalar(text);
    }
    if (children.every((c) => c.localName == 'item')) {
      return [for (final child in children) _decodeElement(child)];
    }
    final map = <String, dynamic>{};
    for (final child in children) {
      final decoded = _decodeElement(child);
      final key = child.localName;
      final existing = map[key];
      if (existing == null && !map.containsKey(key)) {
        map[key] = decoded;
      } else if (existing is List) {
        existing.add(decoded);
      } else {
        map[key] = <dynamic>[existing, decoded];
      }
    }
    return map;
  }

  Object _inferScalar(String text) =>
      int.tryParse(text) ??
      double.tryParse(text) ??
      switch (text) {
        'true' => true,
        'false' => false,
        _ => text,
      };

  void _encodeValue(XmlBuilder builder, Object? value) {
    if (value == null) return;
    if (value is Map) {
      for (final entry in value.entries) {
        final key = '${entry.key}';
        final item = entry.value;
        if (item is List) {
          for (final element in item) {
            builder.element(key,
                nest: () => _encodeValue(builder, element));
          }
        } else {
          builder.element(key, nest: () => _encodeValue(builder, item));
        }
      }
    } else if (value is List) {
      for (final element in value) {
        builder.element('item', nest: () => _encodeValue(builder, element));
      }
    } else {
      builder.text('$value');
    }
  }
}
