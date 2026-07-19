// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import

part of 'chat_gateway.dart';

ChatIn $ChatInFromJson(Map<String, dynamic> json) =>
    ChatIn(json['text'] as String);

Map<String, dynamic> $ChatInToJson(ChatIn value) => <String, dynamic>{
  'text': value.text,
};

ChatOut $ChatOutFromJson(Map<String, dynamic> json) =>
    ChatOut(from: json['from'] as String, text: json['text'] as String);

Map<String, dynamic> $ChatOutToJson(ChatOut value) => <String, dynamic>{
  'from': value.from,
  'text': value.text,
};
