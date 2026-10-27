/// A fixed 2048-bit RSA test keypair (generated once with openssl) plus a
/// TEST-ONLY RS256 signer: signing is just `em^d mod n`, so the tests can
/// mint real RS256 tokens without shipping any signing code in the lib.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:diana_auth/diana_auth.dart';

const fixtureN =
    'qydYCZkinvP83P-IY2XzmKft47OalHZUZM1pKBQDwlJp-nskbuZWbLw2Jc4VmRCxNx7uDRp'
    'bwcg5lvt3dqwqTnYqWKDCutmWRVeXC_mAlHiOHlcuQ3dNaNxcjGyM46GI8USdmoxMhQKtHI'
    'jGL1glhWDt4F67edTNPVe_qodIMgNnc--RZWDaUCwDGi7WcTKjoQ9QJ2_oJAmXbi4Fw_pUB'
    '0lYyMSdjL4OYhKfGWZThQEPjJGh9pOVn2M5QR_9TpRPCF-UDxIp4fNUHtS1PGGHQ7Q4Z-l_'
    'U13c9JWC0dslbStbvL61pdiWI2GH_e-sm6soXLK5-72I3JyfBOyjS1DOWQ';
const fixtureE = 'AQAB';

final BigInt _d = BigInt.parse(
  '1cb97aae09b464c7001e3b08b1ddef77245fe98240244083c37331fdd6f6168bec5b6c85'
  '5dd36c97cd32ad3f9c225749d6bd6b2869cf1283bf1e96cfa2ec1c2194f56070829e075c'
  '9000b649fd32d6383169e829cc8ade44060fc6458593c28d90287ae6f03afb6bca8fea68'
  '909393a081f70a5bfbcce3a91a6d7aae6d0bf1d0982d232f7505958984dab156b73380a7'
  'bec041987c1e895b0a70e3dde01717ae80e31499a2ed35bda733cccb04f75aa29821f80a'
  '0c38a9d4d2fca86a5ee6aae35e0d3ffb1adef23ed0aa1d21bd846b0d80352711c6b7032b'
  '182a5dd44503b2eee24afae6af0306e5b81abfe0e686103b3c849dd8826639e409ce5b88'
  'f11d4a2d',
  radix: 16,
);

const fixtureSpkiPem = '''
-----BEGIN PUBLIC KEY-----
MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAqydYCZkinvP83P+IY2Xz
mKft47OalHZUZM1pKBQDwlJp+nskbuZWbLw2Jc4VmRCxNx7uDRpbwcg5lvt3dqwq
TnYqWKDCutmWRVeXC/mAlHiOHlcuQ3dNaNxcjGyM46GI8USdmoxMhQKtHIjGL1gl
hWDt4F67edTNPVe/qodIMgNnc++RZWDaUCwDGi7WcTKjoQ9QJ2/oJAmXbi4Fw/pU
B0lYyMSdjL4OYhKfGWZThQEPjJGh9pOVn2M5QR/9TpRPCF+UDxIp4fNUHtS1PGGH
Q7Q4Z+l/U13c9JWC0dslbStbvL61pdiWI2GH/e+sm6soXLK5+72I3JyfBOyjS1DO
WQIDAQAB
-----END PUBLIC KEY-----
''';

const fixturePkcs1Pem = '''
-----BEGIN RSA PUBLIC KEY-----
MIIBCgKCAQEAqydYCZkinvP83P+IY2XzmKft47OalHZUZM1pKBQDwlJp+nskbuZW
bLw2Jc4VmRCxNx7uDRpbwcg5lvt3dqwqTnYqWKDCutmWRVeXC/mAlHiOHlcuQ3dN
aNxcjGyM46GI8USdmoxMhQKtHIjGL1glhWDt4F67edTNPVe/qodIMgNnc++RZWDa
UCwDGi7WcTKjoQ9QJ2/oJAmXbi4Fw/pUB0lYyMSdjL4OYhKfGWZThQEPjJGh9pOV
n2M5QR/9TpRPCF+UDxIp4fNUHtS1PGGHQ7Q4Z+l/U13c9JWC0dslbStbvL61pdiW
I2GH/e+sm6soXLK5+72I3JyfBOyjS1DOWQIDAQAB
-----END RSA PUBLIC KEY-----
''';

/// JWK map for the fixture public key.
Map<String, Object?> fixtureJwk({String? kid}) => {
      'kty': 'RSA',
      'n': fixtureN,
      'e': fixtureE,
      if (kid != null) 'kid': kid,
    };

RsaPublicKey fixtureKey({String? kid}) =>
    RsaPublicKey.fromJwk(fixtureJwk(kid: kid));

String _seg(Object json) =>
    base64Url.encode(utf8.encode(jsonEncode(json))).replaceAll('=', '');

/// TEST-ONLY: mints an RS256 token with the fixture private exponent.
String signRs256(
  Map<String, Object?> claims, {
  String? kid,
  Map<String, Object?>? header,
}) {
  final h =
      header ?? {'alg': 'RS256', 'typ': 'JWT', if (kid != null) 'kid': kid};
  final signingInput = '${_seg(h)}.${_seg(claims)}';
  final key = fixtureKey();
  final k = key.octetLength;
  final em = emsaPkcs1V15Sha256(utf8.encode(signingInput), k)!;
  var m = BigInt.zero;
  for (final byte in em) {
    m = (m << 8) | BigInt.from(byte);
  }
  var s = m.modPow(_d, key.modulus);
  final sig = Uint8List(k);
  final mask = BigInt.from(0xff);
  for (var i = k - 1; i >= 0; i--) {
    sig[i] = (s & mask).toInt();
    s >>= 8;
  }
  return '$signingInput.${base64Url.encode(sig).replaceAll('=', '')}';
}

/// Standard claims helper: valid for an hour by default.
Map<String, Object?> claims({
  String sub = 'ada',
  Duration ttl = const Duration(hours: 1),
  Map<String, Object?> extra = const {},
}) {
  final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  return {'sub': sub, 'iat': now, 'exp': now + ttl.inSeconds, ...extra};
}
