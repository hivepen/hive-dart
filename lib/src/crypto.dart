/// secp256k1 keys and signatures for Hive.
///
/// Faithful port of the signing behaviour of dhive (`@hiveio/dhive`
/// `src/crypto.ts`, which wraps the `secp256k1` npm package backed by
/// libsecp256k1):
///
/// * private keys are 32-byte secrets, WIF-encoded as `0x80 || secret`
///   with a double-SHA256 checksum, base58.
/// * public keys are compressed secp256k1 points (33 bytes), encoded as
///   `STM` + base58(`key || ripemd160(key)[0:4]`).
/// * signing is ECDSA with a deterministic nonce per RFC 6979
///   (HMAC-SHA256), where the nonce function receives the additional
///   input `sha256(message || attempts)` — exactly what dhive passes as
///   `options.data` to `secp256k1.sign`. The signer retries with
///   `attempts = 1, 2, ...` until the signature is canonical (dhive
///   `isCanonicalSignature`): neither `r` nor `s` may have its high bit
///   set, and neither may carry an unnecessary leading zero byte.
/// * `s` is normalised to the low half of the curve order (libsecp256k1
///   behaviour), flipping the recovery bit when it does.
/// * a signature serialises as 65 bytes — first byte `recovery + 31`,
///   then `r || s` — hex-encoded for the JSON-RPC wire format.
library;

import 'dart:typed_data';

import 'package:pointycastle/export.dart';

import 'constants.dart';
import 'utils.dart';

final _domain = ECDomainParameters('secp256k1');
final _n = _domain.n;
final _halfN = _n >> 1;
final _p = BigInt.parse(
  'fffffffffffffffffffffffffffffffffffffffffffffffffffffffefffffc2f',
  radix: 16,
);

/// Thrown when a key, signature or digest is malformed.
class HiveCryptoException implements Exception {
/// Create with an error message.
  HiveCryptoException(this.message);
/// Human-readable error detail.
  final String message;
  @override
  String toString() => 'HiveCryptoException: $message';
}

/// HMAC-SHA256, used by the RFC 6979 nonce generator.
Uint8List _hmacSha256(Uint8List key, Uint8List data) {
  final hmac = HMac.withDigest(SHA256Digest());
  hmac.init(KeyParameter(key));
  return hmac.process(data);
}

/// `bits2int` of RFC 6979: interpret [bytes] as a big-endian integer,
/// truncated to the bit length of the curve order.
BigInt _bits2int(Uint8List bytes) {
  var value = bytesToBigInt(bytes);
  final excessBits = bytes.length * 8 - _n.bitLength;
  if (excessBits > 0) value >>= excessBits;
  return value;
}

/// `bits2octets` of RFC 6979: reduce the hash to the curve order range
/// and encode as 32 big-endian bytes.
Uint8List _bits2octets(Uint8List hash) {
  var z = _bits2int(hash);
  if (z >= _n) z -= _n;
  return bigIntToBytes(z, 32);
}

/// RFC 6979 deterministic nonce generation (HMAC-SHA256) with the
/// additional input that libsecp256k1 mixes in (RFC 6979 §3.6).
///
/// [privateKey] is the 32-byte secret, [hash] the 32-byte message
/// digest, [additionalData] the extra input (`sha256(message ||
/// attempts)` in dhive's signing loop).
BigInt _rfc6979Nonce(
  Uint8List privateKey,
  Uint8List hash,
  Uint8List additionalData,
) {
  final x = bigIntToBytes(bytesToBigInt(privateKey), 32);
  final h1 = _bits2octets(hash);
  var v = Uint8List(32)..fillRange(0, 32, 0x01);
  var k = Uint8List(32);
  k = _hmacSha256(k, concatBytes([v, [0x00], x, h1, additionalData]));
  v = _hmacSha256(k, v);
  k = _hmacSha256(k, concatBytes([v, [0x01], x, h1, additionalData]));
  v = _hmacSha256(k, v);
  while (true) {
    v = _hmacSha256(k, v);
    final candidate = _bits2int(v);
    if (candidate >= BigInt.one && candidate < _n) return candidate;
    k = _hmacSha256(k, concatBytes([v, [0x00]]));
    v = _hmacSha256(k, v);
  }
}

/// dhive `isCanonicalSignature`: the 64-byte compact signature must not
/// have the high bit set on `r` or `s`, and must not carry an unnecessary
/// leading zero byte on either half.
bool _isCanonicalSignature(Uint8List compact) {
  bool halfOk(int offset) {
    if (compact[offset] & 0x80 != 0) return false;
    if (compact[offset] == 0 && (compact[offset + 1] & 0x80) == 0) {
      return false;
    }
    return true;
  }

  return halfOk(0) && halfOk(32);
}

/// A Hive ECDSA (secp256k1) signature: 64-byte compact `r || s` plus a
/// recovery id in `0..3`.
class HiveSignature {
/// Create from a 64-byte compact signature and recovery id.
  HiveSignature(this.compact, this.recovery) {
    if (compact.length != 64) {
      throw HiveCryptoException(
        'Invalid signature length: ${compact.length}, expected 64',
      );
    }
    if (recovery < 0 || recovery > 3) {
      throw HiveCryptoException('Invalid recovery id: $recovery');
    }
  }

  /// Parse the 65-byte wire form (first byte `recovery + 31`, then
  /// `r || s`), as produced by [toBuffer].
  factory HiveSignature.fromBuffer(Uint8List buffer) {
    if (buffer.length != 65) {
      throw HiveCryptoException(
        'Invalid signature buffer length: ${buffer.length}, expected 65',
      );
    }
    final recovery = buffer[0] - 31;
    if (recovery < 0 || recovery > 3) {
      throw HiveCryptoException('Invalid recovery byte: ${buffer[0]}');
    }
    return HiveSignature(buffer.sublist(1), recovery);
  }

  /// Parse a hex-encoded 65-byte signature (the JSON-RPC wire form).
  factory HiveSignature.fromHex(String hex) {
    return HiveSignature.fromBuffer(hexDecode(hex));
  }

  /// The 64-byte compact signature (`r || s`, big-endian).
  final Uint8List compact;

  /// Recovery id (`0..3`).
  final int recovery;

/// The `r` component as a big integer.
  BigInt get r => bytesToBigInt(compact.sublist(0, 32));
/// The `s` component as a big integer.
  BigInt get s => bytesToBigInt(compact.sublist(32, 64));

  /// The 65-byte wire form: `[recovery + 31, r (32), s (32)]`.
  Uint8List toBuffer() {
    final out = Uint8List(65);
    out[0] = recovery + 31;
    out.setRange(1, 65, compact);
    return out;
  }

  /// Hex encoding of [toBuffer] — the form Hive nodes expect in the
  /// `signatures` array of a broadcast transaction.
  String toHex() => hexEncode(toBuffer());

  @override
  String toString() => toHex();

  @override
  bool operator ==(Object other) =>
      other is HiveSignature &&
      recovery == other.recovery &&
      compareBytes(compact, other.compact) == 0;

  @override
  int get hashCode => Object.hash(recovery, hexEncode(compact));
}

/// A Hive ECDSA (secp256k1) public key — a compressed 33-byte point.
class HivePublicKey {
/// Create from a 33-byte compressed point.
  HivePublicKey(this.compressed, {this.prefix = hiveAddressPrefix}) {
    if (compressed.length != 33 ||
        (compressed[0] != 0x02 && compressed[0] != 0x03)) {
      throw HiveCryptoException('Invalid compressed public key');
    }
  }

  /// Decode a `STM...` (or other 3-letter prefix) encoded public key,
  /// verifying the ripemd160 checksum (dhive `decodePublic`).
  factory HivePublicKey.fromString(String encoded) {
    if (encoded.length < 4) {
      throw HiveCryptoException('Public key too short: $encoded');
    }
    final prefix = encoded.substring(0, 3);
    final decoded = base58Decode(encoded.substring(3));
    if (decoded.length != 37) {
      throw HiveCryptoException(
        'Invalid public key length: ${decoded.length}, expected 37',
      );
    }
    final key = decoded.sublist(0, 33);
    final checksum = decoded.sublist(33);
    final expected = ripemd160(key).sublist(0, 4);
    if (compareBytes(checksum, expected) != 0) {
      throw HiveCryptoException('Public key checksum mismatch');
    }
    return HivePublicKey(key, prefix: prefix);
  }

  /// Build from a 33-byte compressed point (dhive `PublicKey.fromBuffer`
  /// — validates that the point is on the curve).
  factory HivePublicKey.fromCompressedBytes(Uint8List bytes,
      {String prefix = hiveAddressPrefix}) {
    final point = _domain.curve.decodePoint(bytes);
    if (point == null || point.isInfinity) {
      throw HiveCryptoException('Invalid public key point');
    }
    return HivePublicKey(bytes, prefix: prefix);
  }

  /// The 33-byte compressed point.
  final Uint8List compressed;

  /// The 3-letter address prefix, e.g. `STM`.
  final String prefix;

  ECPoint get _point => _domain.curve.decodePoint(compressed)!;

  /// Verify [signature] over the 32-byte [digest].
  bool verify(Uint8List digest, HiveSignature signature) {
    if (digest.length != 32) {
      throw HiveCryptoException('Digest must be 32 bytes');
    }
    final z = _bits2int(digest);
    final r = signature.r;
    final s = signature.s;
    if (r < BigInt.one || r >= _n || s < BigInt.one || s >= _n) {
      return false;
    }
    final w = s.modInverse(_n);
    final u1 = (z * w) % _n;
    final u2 = (r * w) % _n;
    final point = (_domain.G * u1)! + (_point * u2)!;
    if (point == null || point.isInfinity) return false;
    return point.x!.toBigInteger()! % _n == r;
  }

  /// Recover the public key that produced [signature] over [digest].
  static HivePublicKey recover(
    Uint8List digest,
    HiveSignature signature, {
    String prefix = hiveAddressPrefix,
  }) {
    if (digest.length != 32) {
      throw HiveCryptoException('Digest must be 32 bytes');
    }
    final r = signature.r;
    final s = signature.s;
    final recid = signature.recovery;
    // x = r + (recid >> 1) * n  (the R point's x coordinate)
    final x = r + BigInt.from(recid >> 1) * _n;
    if (x >= _p) {
      throw HiveCryptoException('Invalid recovery parameters');
    }
    final bigR = _domain.curve.decompressPoint(recid & 1, x);
    final rInv = r.modInverse(_n);
    final u1 = (-_bits2int(digest) * rInv) % _n;
    final u2 = (s * rInv) % _n;
    final point = (_domain.G * u1)! + (bigR * u2)!;
    if (point == null || point.isInfinity) {
      throw HiveCryptoException('Could not recover public key');
    }
    return HivePublicKey(point.getEncoded(true), prefix: prefix);
  }

  /// `STM` + base58(`key || ripemd160(key)[0:4]`) (dhive `encodePublic`).
  @override
  String toString() {
    final checksum = ripemd160(compressed).sublist(0, 4);
    return prefix + base58Encode(concatBytes([compressed, checksum]));
  }

  @override
  bool operator ==(Object other) =>
      other is HivePublicKey &&
      prefix == other.prefix &&
      compareBytes(compressed, other.compressed) == 0;

  @override
  int get hashCode => Object.hash(prefix, hexEncode(compressed));
}

/// A Hive ECDSA (secp256k1) private key — a 32-byte secret.
///
/// The secret is held in memory only. Never log it, never write it to
/// disk, and never send it anywhere: signing happens locally, and only
/// signatures leave the device. [toString] deliberately does NOT return
/// the WIF; use [toWif] explicitly when the caller really needs it.
class HivePrivateKey {
/// Create from a 32-byte secret.
  HivePrivateKey(this.secret) {
    if (secret.length != 32) {
      throw HiveCryptoException(
        'Invalid private key length: ${secret.length}, expected 32',
      );
    }
    final d = bytesToBigInt(secret);
    if (d <= BigInt.zero || d >= _n) {
      throw HiveCryptoException('Private key out of range');
    }
  }

  /// Decode a WIF string, verifying the `0x80` prefix and the
  /// double-SHA256 checksum (dhive `decodePrivate`).
  factory HivePrivateKey.fromWif(String wif) {
    final decoded = base58Decode(wif);
    if (decoded.length != 37 || decoded[0] != 0x80) {
      throw HiveCryptoException('Invalid WIF encoding');
    }
    final key = decoded.sublist(0, 33);
    final checksum = decoded.sublist(33);
    final expected = doubleSha256(key).sublist(0, 4);
    if (compareBytes(checksum, expected) != 0) {
      throw HiveCryptoException('WIF checksum mismatch');
    }
    return HivePrivateKey(key.sublist(1));
  }

  /// Create a key from a seed string: `sha256(seed)` (dhive `fromSeed`).
  factory HivePrivateKey.fromSeed(String seed) {
    return HivePrivateKey(sha256(Uint8List.fromList(seed.codeUnits)));
  }

  /// Derive a role key from `username + role + password`
  /// (dhive `fromLogin`; role is `owner`, `active`, `posting` or `memo`).
  factory HivePrivateKey.fromLogin(
    String username,
    String password, {
    String role = 'active',
  }) {
    return HivePrivateKey.fromSeed(username + role + password);
  }

  /// The 32-byte secret. Treat as sensitive: never log or persist.
  final Uint8List secret;

  BigInt get _d => bytesToBigInt(secret);

  /// The matching public key (compressed, `STM` prefix by default).
  HivePublicKey createPublic({String prefix = hiveAddressPrefix}) {
    final point = _domain.G * _d;
    return HivePublicKey(point!.getEncoded(true), prefix: prefix);
  }

  /// Sign a 32-byte [digest] with deterministic RFC 6979 nonces,
  /// exactly like dhive's `PrivateKey.sign` (see module doc comment).
  HiveSignature sign(Uint8List digest) {
    if (digest.length != 32) {
      throw HiveCryptoException('Digest must be 32 bytes');
    }
    final z = _bits2int(digest);
    var attempts = 0;
    while (true) {
      attempts++;
      final extra = sha256(concatBytes([digest, [attempts]]));
      final k = _rfc6979Nonce(secret, digest, extra);
      final bigR = _domain.G * k;
      if (bigR == null || bigR.isInfinity) continue;
      final r = bigR.x!.toBigInteger()! % _n;
      if (r == BigInt.zero) continue;
      var recid = (bigR.y!.toBigInteger()! & BigInt.one) == BigInt.one
          ? 1
          : 0;
      if (bigR.x!.toBigInteger()! >= _n) recid |= 2;
      var s = (k.modInverse(_n) * (z + r * _d)) % _n;
      if (s == BigInt.zero) continue;
      // Low-s normalisation (libsecp256k1): flip s and the recovery bit.
      if (s > _halfN) {
        s = _n - s;
        recid ^= 1;
      }
      final compact = concatBytes(
        [bigIntToBytes(r, 32), bigIntToBytes(s, 32)],
      );
      if (!_isCanonicalSignature(compact)) continue;
      return HiveSignature(compact, recid);
    }
  }

  /// WIF encoding (`0x80 || secret` + double-SHA256 checksum, base58).
  /// Call explicitly — this is the only place the secret leaves the
  /// object in encoded form.
  String toWif() {
    final key = concatBytes([
      [0x80],
      secret,
    ]);
    final checksum = doubleSha256(key).sublist(0, 4);
    return base58Encode(concatBytes([key, checksum]));
  }

  /// Deliberately redacted: never print a private key.
  @override
  String toString() => 'HivePrivateKey(<redacted>)';
}
