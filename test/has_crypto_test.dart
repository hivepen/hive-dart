// HAS crypto tests — the decrypt vector was produced by the real
// `crypto-js` library (Node), see README "Test vectors".
import 'dart:typed_data';

import 'package:hive_dart/hive_dart.dart';
import 'package:test/test.dart';

void main() {
  group('CryptoJS-compatible AES', () {
    test('decrypts a CryptoJS-produced ciphertext', () {
      // Produced with:
      //   CryptoJS.AES.encrypt(
      //     '{"app":{"name":"gloti"},"challenge":"abc"}',
      //     'test-auth-key-123').toString()
      const ciphertext =
          'U2FsdGVkX19TaQBqsw2an4yNPY9DjvoddJ2z/UIizIId20zue+kJWVERjTqI4sYr19iLWLJH/BiW50ZHCyvOcQ==';
      expect(
        cryptoJsAesDecrypt(ciphertext, 'test-auth-key-123'),
        '{"app":{"name":"gloti"},"challenge":"abc"}',
      );
    });

    test('decrypt fails with the wrong passphrase', () {
      const ciphertext =
          'U2FsdGVkX19TaQBqsw2an4yNPY9DjvoddJ2z/UIizIId20zue+kJWVERjTqI4sYr19iLWLJH/BiW50ZHCyvOcQ==';
      expect(
        () => cryptoJsAesDecrypt(ciphertext, 'wrong-passphrase'),
        throwsA(isA<HiveAuthCryptoException>()),
      );
    });

    test('encrypt/decrypt round-trip, deterministic with fixed salt', () {
      const plaintext = '{"cmd":"auth_req","account":"alice"}';
      const passphrase = 'some-auth-key';
      final salt = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]);
      final a = cryptoJsAesEncrypt(plaintext, passphrase, salt: salt);
      final b = cryptoJsAesEncrypt(plaintext, passphrase, salt: salt);
      expect(a, b, reason: 'fixed salt must give identical ciphertext');
      expect(a.startsWith('U2FsdGVkX1'), isTrue,
          reason: 'CryptoJS output starts with base64("Salted__")');
      expect(cryptoJsAesDecrypt(a, passphrase), plaintext);
    });

    test('random-salt encryption still round-trips', () {
      const plaintext = 'hello HAS';
      final encrypted = cryptoJsAesEncrypt(plaintext, 'key-1');
      expect(cryptoJsAesDecrypt(encrypted, 'key-1'), plaintext);
    });
  });
}
