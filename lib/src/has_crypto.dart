/// CryptoJS-compatible AES encryption, for HiveAuth (HAS).
///
/// The HAS protocol (docs.hiveauth.com) encrypts its `auth_req_data` /
/// `sign_req_data` payloads the way `hive-auth-wrapper` does it:
/// `CryptoJS.AES.encrypt(plaintext, authKey).toString()` — i.e. AES-256
/// in CBC mode with PKCS#7 padding, where key and IV are derived from
/// the passphrase with OpenSSL's `EVP_BytesToKey` (MD5, one iteration,
/// 8-byte random salt), and the output is
/// `base64("Salted__" || salt || ciphertext)`.
///
/// The HAS server never sees plaintext: only the app and the wallet
/// (PKSA) share the `auth_key`, so they are the only parties that can
/// encrypt/decrypt these payloads.
///
/// Implementation notes:
/// * `EVP_BytesToKey`: `D1 = MD5(pass || salt)`,
///   `D_i = MD5(D_{i-1} || pass || salt)`; key = first 32 bytes,
///   IV = next 16 bytes.
/// * [encrypt] uses a random 8-byte salt (from `Random.secure`); pass
///   an explicit [salt] for deterministic tests.
/// * [decrypt] accepts the `Salted__`-prefixed base64 form and also a
///   bare base64 ciphertext produced with an empty salt (defensive).
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

import 'utils.dart';

/// Thrown when a HAS payload cannot be decrypted.
class HiveAuthCryptoException implements Exception {
/// Create with an error message.
  HiveAuthCryptoException(this.message);
/// Human-readable error detail.
  final String message;
  @override
  String toString() => 'HiveAuthCryptoException: $message';
}

/// Derive a 32-byte AES key and a 16-byte IV from [passphrase] and
/// [salt] with OpenSSL `EVP_BytesToKey` (MD5, 1 iteration).
({Uint8List key, Uint8List iv}) evpBytesToKey(
  Uint8List passphrase,
  Uint8List salt,
) {
  final derived = BytesBuilder();
  var prev = Uint8List(0);
  while (derived.length < 48) {
    final block = md5(concatBytes([prev, passphrase, salt]));
    derived.add(block);
    prev = block;
  }
  final bytes = derived.toBytes();
  return (key: bytes.sublist(0, 32), iv: bytes.sublist(32, 48));
}

Uint8List _aesCbc(Uint8List key, Uint8List iv, Uint8List data, bool encrypt) {
  final cipher = PaddedBlockCipherImpl(
    PKCS7Padding(),
    CBCBlockCipher(AESEngine()),
  );
  cipher.init(
    encrypt,
    PaddedBlockCipherParameters(
      ParametersWithIV<KeyParameter>(KeyParameter(key), iv),
      null,
    ),
  );
  return cipher.process(data);
}

/// Encrypt [plaintext] with [passphrase], CryptoJS-compatible.
/// Returns `base64("Salted__" || salt || ciphertext)`.
String cryptoJsAesEncrypt(
  String plaintext,
  String passphrase, {
  Uint8List? salt,
}) {
  final passBytes = Uint8List.fromList(utf8.encode(passphrase));
  final usedSalt = salt ?? _randomSalt();
  final (:key, :iv) = evpBytesToKey(passBytes, usedSalt);
  final ciphertext = _aesCbc(
    key,
    iv,
    Uint8List.fromList(utf8.encode(plaintext)),
    true,
  );
  return base64Encode(concatBytes([
    utf8.encode('Salted__'),
    usedSalt,
    ciphertext,
  ]));
}

/// Decrypt a CryptoJS-produced base64 string with [passphrase].
String cryptoJsAesDecrypt(String base64Ciphertext, String passphrase) {
  final raw = base64Decode(base64Ciphertext);
  final passBytes = Uint8List.fromList(utf8.encode(passphrase));
  late Uint8List salt;
  late Uint8List ciphertext;
  if (raw.length > 16 &&
      utf8.decode(raw.sublist(0, 8), allowMalformed: true) == 'Salted__') {
    salt = raw.sublist(8, 16);
    ciphertext = raw.sublist(16);
  } else {
    // Bare ciphertext without salt (non-standard, defensive only).
    salt = Uint8List(0);
    ciphertext = raw;
  }
  final (:key, :iv) = evpBytesToKey(passBytes, salt);
  try {
    final plain = _aesCbc(key, iv, ciphertext, false);
    return utf8.decode(plain);
  } catch (e) {
    // A wrong passphrase surfaces as a PKCS7 padding ArgumentError
    // (an Error, not an Exception) from pointycastle; normalise it.
    throw HiveAuthCryptoException('Decryption failed: $e');
  }
}

Uint8List _randomSalt() {
  final random = Random.secure();
  return Uint8List.fromList(
    List<int>.generate(8, (_) => random.nextInt(256)),
  );
}
