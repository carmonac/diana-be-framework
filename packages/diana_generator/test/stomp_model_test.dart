import 'package:diana_generator/src/model/summary.dart';
import 'package:test/test.dart';

const _out = TypeRef(name: 'ChatOut', libraryUri: 'package:a/dto.dart');
const _in = TypeRef(name: 'ChatIn', libraryUri: 'package:a/dto.dart');

void main() {
  test('MessageMappingInfo round-trips with every field', () {
    const info = MessageMappingInfo(
      methodName: 'handle',
      destination: '/chat',
      payloadKind: 'json',
      payloadType: _in,
      wantsMessage: true,
      returnKind: 'json',
      returnType: _out,
      sendTo: '/topic/chat',
    );
    final back = MessageMappingInfo.fromJson(info.toJson());
    expect(back.methodName, 'handle');
    expect(back.destination, '/chat');
    expect(back.payloadKind, 'json');
    expect(back.payloadType!.name, 'ChatIn');
    expect(back.wantsMessage, isTrue);
    expect(back.returnKind, 'json');
    expect(back.returnType!.name, 'ChatOut');
    expect(back.sendTo, '/topic/chat');
  });

  test('defaults are omitted and restored', () {
    const info = MessageMappingInfo(
      methodName: 'log',
      destination: '/log',
      payloadKind: 'text',
    );
    final json = info.toJson();
    expect(
        json.keys, unorderedEquals(['method', 'destination', 'payloadKind']));
    final back = MessageMappingInfo.fromJson(json);
    expect(back.returnKind, 'void');
    expect(back.wantsMessage, isFalse);
    expect(back.sendTo, isNull);
  });
}
