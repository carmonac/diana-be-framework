import 'package:diana/diana.dart';
import 'package:test/test.dart';

void main() {
  const codec = XmlCodec();

  test('decodes nested elements, lists and scalar inference', () {
    final decoded = codec.decode('''
<request>
  <title>hello</title>
  <priority>3</priority>
  <score>1.5</score>
  <done>true</done>
  <empty/>
  <tags><tag>a</tag><tag>b</tag></tags>
  <address><street>Main</street></address>
  <items><item>1</item><item>2</item></items>
</request>
''') as Map<String, dynamic>;
    expect(decoded['title'], 'hello');
    expect(decoded['priority'], 3);
    expect(decoded['score'], 1.5);
    expect(decoded['done'], isTrue);
    expect(decoded['empty'], isNull);
    expect(decoded['tags'], {'tag': ['a', 'b']});
    expect(decoded['address'], {'street': 'Main'});
    expect(decoded['items'], [1, 2]);
  });

  test('encodes maps, lists and nulls deterministically', () {
    final xml = codec.encode({
      'title': 'x',
      'count': 2,
      'tags': ['a', 'b'],
      'nested': {'k': 'v'},
      'missing': null,
    });
    expect(
      xml,
      '<response><title>x</title><count>2</count>'
      '<tags>a</tags><tags>b</tags>'
      '<nested><k>v</k></nested><missing/></response>',
    );
  });

  test('round-trips a DTO-shaped map', () {
    final original = {
      'title': 'buy milk',
      'priority': 5,
    };
    final decoded = codec.decode(codec.encode(original));
    expect(decoded, original);
  });

  test('top-level lists use <item> elements', () {
    expect(codec.encode([1, 2]), '<response><item>1</item><item>2</item></response>');
    expect(codec.decode('<r><item>1</item><item>2</item></r>'), [1, 2]);
  });

  test('malformed XML throws FormatException', () {
    expect(() => codec.decode('<a><b></a>'), throwsFormatException);
  });
}
