/// Small byte helpers: hex, base58, digests (via pointycastle).
library;

import 'dart:typed_data';

import 'package:pointycastle/digests/md5.dart';
import 'package:pointycastle/digests/ripemd160.dart';
import 'package:pointycastle/digests/sha256.dart';
import 'package:pointycastle/digests/sha512.dart';

const _hexDigits = '0123456789abcdef';

/// Lower-case hex encoding of [bytes].
String hexEncode(Uint8List bytes) {
  final out = StringBuffer();
  for (final b in bytes) {
    out.write(_hexDigits[b >> 4]);
    out.write(_hexDigits[b & 0x0f]);
  }
  return out.toString();
}

/// Decode a (lower- or upper-case) hex string. Throws [FormatException]
/// on odd length or non-hex characters.
Uint8List hexDecode(String hex) {
  if (hex.length.isOdd) {
    throw FormatException('Odd-length hex string', hex);
  }
  final out = Uint8List(hex.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    final hi = _hexDigits.indexOf(hex[2 * i].toLowerCase());
    final lo = _hexDigits.indexOf(hex[2 * i + 1].toLowerCase());
    if (hi < 0 || lo < 0) throw FormatException('Invalid hex', hex);
    out[i] = (hi << 4) | lo;
  }
  return out;
}

/// SHA-256 digest.
Uint8List sha256(Uint8List input) => SHA256Digest().process(input);

/// Double SHA-256 (used for WIF checksums).
Uint8List doubleSha256(Uint8List input) => sha256(sha256(input));

/// SHA-512 digest (used for memo shared secrets in dhive; kept for parity).
Uint8List sha512(Uint8List input) => SHA512Digest().process(input);

/// RIPEMD-160 digest (used for public-key checksums).
Uint8List ripemd160(Uint8List input) => RIPEMD160Digest().process(input);

/// MD5 digest (used by the CryptoJS-compatible key derivation in HAS).
Uint8List md5(Uint8List input) => MD5Digest().process(input);

/// Bitcoin base58 alphabet.
const _base58Alphabet =
    '123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz';

/// Base58-encode [bytes] (Bitcoin alphabet, leading zero bytes → '1').
String base58Encode(Uint8List bytes) {
  var leadingZeros = 0;
  while (leadingZeros < bytes.length && bytes[leadingZeros] == 0) {
    leadingZeros++;
  }
  var value = BigInt.zero;
  for (final b in bytes) {
    value = (value << 8) | BigInt.from(b);
  }
  final chars = <String>[];
  while (value > BigInt.zero) {
    final remainder = (value % BigInt.from(58)).toInt();
    chars.add(_base58Alphabet[remainder]);
    value ~/= BigInt.from(58);
  }
  return ('1' * leadingZeros) + chars.reversed.join();
}

/// Base58-decode [encoded] (Bitcoin alphabet).
/// Throws [FormatException] on characters outside the alphabet.
Uint8List base58Decode(String encoded) {
  var leadingOnes = 0;
  while (leadingOnes < encoded.length && encoded[leadingOnes] == '1') {
    leadingOnes++;
  }
  var value = BigInt.zero;
  for (var i = 0; i < encoded.length; i++) {
    final digit = _base58Alphabet.indexOf(encoded[i]);
    if (digit < 0) {
      throw FormatException('Invalid base58 character', encoded, i);
    }
    value = value * BigInt.from(58) + BigInt.from(digit);
  }
  final bytes = <int>[];
  while (value > BigInt.zero) {
    bytes.add((value & BigInt.from(0xff)).toInt());
    value >>= 8;
  }
  final body = bytes.reversed.toList();
  return Uint8List.fromList(
    List<int>.filled(leadingOnes, 0) + body,
  );
}

/// Concatenate byte lists.
Uint8List concatBytes(List<List<int>> parts) {
  final total = parts.fold<int>(0, (sum, p) => sum + p.length);
  final out = Uint8List(total);
  var offset = 0;
  for (final part in parts) {
    out.setRange(offset, offset + part.length, part);
    offset += part.length;
  }
  return out;
}

/// Big-endian unsigned encoding of [value] in exactly [length] bytes.
Uint8List bigIntToBytes(BigInt value, int length) {
  final out = Uint8List(length);
  var v = value;
  for (var i = length - 1; i >= 0; i--) {
    out[i] = (v & BigInt.from(0xff)).toInt();
    v >>= 8;
  }
  if (v != BigInt.zero) {
    throw ArgumentError('Value does not fit in $length bytes');
  }
  return out;
}

/// Decode big-endian unsigned bytes to [BigInt].
BigInt bytesToBigInt(Uint8List bytes) {
  var value = BigInt.zero;
  for (final b in bytes) {
    value = (value << 8) | BigInt.from(b);
  }
  return value;
}

/// Lexicographic byte comparison, for canonical-signature checks.
int compareBytes(Uint8List a, Uint8List b) {
  final len = a.length < b.length ? a.length : b.length;
  for (var i = 0; i < len; i++) {
    if (a[i] != b[i]) return a[i] - b[i];
  }
  return a.length - b.length;
}
