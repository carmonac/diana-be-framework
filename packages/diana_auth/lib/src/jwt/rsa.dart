/// Minimal, verification-only RSA (RSASSA-PKCS1-v1_5 with SHA-256) in pure
/// Dart. Verification needs no private-key operations and no
/// timing-sensitive secrets: it is `signature^e mod n` (native
/// [BigInt.modPow]) followed by an exact comparison against the expected
/// EMSA-PKCS1-v1_5 encoding — the encode-then-compare construction, which
/// never parses attacker-controlled padding.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// An RSA public key (modulus + public exponent), optionally tagged with
/// the JWK `kid` it came from.
class RsaPublicKey {
  final BigInt modulus;
  final BigInt exponent;

  /// JWK key id, when the key came from a JWK/JWKS document.
  final String? keyId;

  RsaPublicKey(this.modulus, this.exponent, {this.keyId}) {
    if (modulus <= BigInt.zero || exponent <= BigInt.zero) {
      throw const FormatException('RSA key components must be positive');
    }
  }

  /// Parses an RSA JWK (RFC 7518 §6.3): `kty` must be `RSA`, `n`/`e` are
  /// base64url-encoded big-endian integers. Throws [FormatException] on
  /// anything else — key material errors are configuration errors, not
  /// credential failures.
  factory RsaPublicKey.fromJwk(Map<String, Object?> jwk) {
    if (jwk['kty'] != 'RSA') {
      throw FormatException('JWK kty must be RSA, was "${jwk['kty']}"');
    }
    final n = jwk['n'];
    final e = jwk['e'];
    if (n is! String || e is! String) {
      throw const FormatException('RSA JWK must carry base64url "n" and "e"');
    }
    return RsaPublicKey(
      _base64UrlToBigInt(n),
      _base64UrlToBigInt(e),
      keyId: jwk['kid'] is String ? jwk['kid'] as String : null,
    );
  }

  /// Parses a PEM public key: `BEGIN PUBLIC KEY` (X.509
  /// SubjectPublicKeyInfo) or `BEGIN RSA PUBLIC KEY` (PKCS#1).
  factory RsaPublicKey.fromPem(String pem, {String? keyId}) {
    final armor = RegExp(
            r'-----BEGIN (RSA PUBLIC KEY|PUBLIC KEY)-----([A-Za-z0-9+/=\s]+)'
            r'-----END \1-----')
        .firstMatch(pem);
    if (armor == null) {
      throw const FormatException(
          'Expected a PEM "PUBLIC KEY" or "RSA PUBLIC KEY" block');
    }
    final der = base64.decode(armor.group(2)!.replaceAll(RegExp(r'\s'), ''));
    final rsaSequence = armor.group(1) == 'PUBLIC KEY'
        ? _rsaKeyFromSubjectPublicKeyInfo(der)
        : der;
    final ints = _parseDerIntegerSequence(rsaSequence);
    if (ints.length != 2) {
      throw const FormatException('Malformed RSA public key');
    }
    return RsaPublicKey(ints[0], ints[1], keyId: keyId);
  }

  /// Modulus size in octets (the RSA signature length).
  int get octetLength => (modulus.bitLength + 7) ~/ 8;
}

/// Verifies an RSASSA-PKCS1-v1_5 SHA-256 [signature] over [message].
/// Returns `false` on any mismatch; never throws for bad signatures.
bool rsaVerifyPkcs1Sha256(
    RsaPublicKey key, List<int> message, List<int> signature) {
  final k = key.octetLength;
  if (signature.length != k) return false;
  final s = _bytesToBigInt(signature);
  if (s >= key.modulus) return false;
  final em = _bigIntToBytes(s.modPow(key.exponent, key.modulus), k);
  final expected = emsaPkcs1V15Sha256(message, k);
  if (expected == null) return false;
  // Exact compare of the full encoded message — no padding parsing.
  var diff = 0;
  for (var i = 0; i < k; i++) {
    diff |= em[i] ^ expected[i];
  }
  return diff == 0;
}

/// EMSA-PKCS1-v1_5 encoding of SHA-256([message]) into [length] octets
/// (RFC 8017 §9.2): `0x00 0x01 FF…FF 0x00 DigestInfo ‖ hash`. Returns
/// `null` when [length] is too small. Exposed for the verifier's
/// encode-then-compare and for test-only signing.
Uint8List? emsaPkcs1V15Sha256(List<int> message, int length) {
  final hash = sha256.convert(message).bytes;
  final t = [..._sha256DigestInfoPrefix, ...hash];
  if (length < t.length + 11) return null;
  final em = Uint8List(length);
  em[0] = 0x00;
  em[1] = 0x01;
  for (var i = 2; i < length - t.length - 1; i++) {
    em[i] = 0xFF;
  }
  em[length - t.length - 1] = 0x00;
  em.setRange(length - t.length, length, t);
  return em;
}

/// DER `DigestInfo` header for SHA-256 (RFC 8017 §9.2 note 1).
const _sha256DigestInfoPrefix = [
  0x30, 0x31, 0x30, 0x0d, 0x06, 0x09, 0x60, 0x86, 0x48, 0x01, //
  0x65, 0x03, 0x04, 0x02, 0x01, 0x05, 0x00, 0x04, 0x20,
];

// ---- DER (parse-only, minimal) ----

const _rsaEncryptionOid = [
  0x06, 0x09, 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x01,
];

/// Extracts the PKCS#1 `RSAPublicKey` DER from an X.509
/// SubjectPublicKeyInfo: `SEQUENCE { AlgorithmIdentifier, BIT STRING }`.
Uint8List _rsaKeyFromSubjectPublicKeyInfo(List<int> der) {
  final outer = _DerReader(der).readSequence();
  final algorithm = outer.readSequence();
  final oid = algorithm.readRaw();
  if (!_listEquals(oid, _rsaEncryptionOid)) {
    throw const FormatException('PEM key is not an RSA key');
  }
  final bits = outer.readTagged(0x03); // BIT STRING
  if (bits.isEmpty || bits[0] != 0x00) {
    throw const FormatException('Malformed RSA public key');
  }
  return Uint8List.sublistView(bits, 1);
}

/// Parses `SEQUENCE { INTEGER, INTEGER, ... }` (PKCS#1 RSAPublicKey).
List<BigInt> _parseDerIntegerSequence(List<int> der) {
  final seq = _DerReader(der).readSequence();
  final ints = <BigInt>[];
  while (!seq.isDone) {
    ints.add(_bytesToBigInt(seq.readTagged(0x02)));
  }
  return ints;
}

class _DerReader {
  final Uint8List _bytes;
  int _pos = 0;

  _DerReader(List<int> bytes) : _bytes = Uint8List.fromList(bytes);

  bool get isDone => _pos >= _bytes.length;

  _DerReader readSequence() => _DerReader(readTagged(0x30));

  /// Reads one TLV with the expected [tag] and returns its value bytes.
  Uint8List readTagged(int tag) {
    if (_pos >= _bytes.length || _bytes[_pos] != tag) {
      throw const FormatException('Malformed DER structure');
    }
    _pos++;
    var length = _readByte();
    if (length & 0x80 != 0) {
      final count = length & 0x7f;
      if (count == 0 || count > 4) {
        throw const FormatException('Malformed DER structure');
      }
      length = 0;
      for (var i = 0; i < count; i++) {
        length = (length << 8) | _readByte();
      }
    }
    if (_pos + length > _bytes.length) {
      throw const FormatException('Malformed DER structure');
    }
    final value = Uint8List.sublistView(_bytes, _pos, _pos + length);
    _pos += length;
    return value;
  }

  /// Reads one TLV of any tag and returns it whole (tag + length + value).
  Uint8List readRaw() {
    final start = _pos;
    if (isDone) throw const FormatException('Malformed DER structure');
    readTagged(_bytes[_pos]);
    return Uint8List.sublistView(_bytes, start, _pos);
  }

  int _readByte() {
    if (_pos >= _bytes.length) {
      throw const FormatException('Malformed DER structure');
    }
    return _bytes[_pos++];
  }
}

// ---- big-endian BigInt codecs ----

BigInt _base64UrlToBigInt(String value) {
  try {
    return _bytesToBigInt(base64Url.decode(base64Url.normalize(value)));
  } on FormatException {
    throw const FormatException('Malformed base64url integer in JWK');
  }
}

BigInt _bytesToBigInt(List<int> bytes) {
  var result = BigInt.zero;
  for (final byte in bytes) {
    result = (result << 8) | BigInt.from(byte);
  }
  return result;
}

Uint8List _bigIntToBytes(BigInt value, int length) {
  final bytes = Uint8List(length);
  var v = value;
  final mask = BigInt.from(0xff);
  for (var i = length - 1; i >= 0; i--) {
    bytes[i] = (v & mask).toInt();
    v >>= 8;
  }
  return bytes;
}

bool _listEquals(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
