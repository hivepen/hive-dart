// Crypto tests — vectors from dhive `test/crypto.ts`
// (openhive-network/dhive) and from a live dhive 1.3.2 run
// (see README: "Test vectors").
import 'dart:typed_data';

import 'package:hiveblockchain_dart/hiveblockchain_dart.dart';
import 'package:test/test.dart';

void main() {
  group('base58 / hex utils', () {
    test('base58 round-trip incl. leading zeros', () {
      const samples = [
        '5K2yDAd9KAZ3ZitBsAPyRka9PLFemUrbcL6UziZiPaw2c6jCeLH',
        'STM8QykigLRi9ZUcNy1iXGY3KjRuCiLM8Ga49LHti1F8hgawKFc3K',
        'hello',
      ];
      for (final s in samples) {
        final bytes = Uint8List.fromList(s.codeUnits);
        expect(base58Decode(base58Encode(bytes)), bytes);
      }
      expect(base58Encode(Uint8List.fromList([0, 0, 1])), '112');
      expect(base58Decode('112'), Uint8List.fromList([0, 0, 1]));
    });

    test('hex round-trip', () {
      expect(
        hexDecode('00ff10ab'),
        Uint8List.fromList([0x00, 0xff, 0x10, 0xab]),
      );
      expect(hexEncode(Uint8List.fromList([0, 255, 16, 171])), '00ff10ab');
    });
  });

  group('private keys', () {
    // dhive test/crypto.ts: mainPair / testnetPair.
    test('WIF round-trip (mainnet pair)', () {
      const wif = '5K2yDAd9KAZ3ZitBsAPyRka9PLFemUrbcL6UziZiPaw2c6jCeLH';
      final key = HivePrivateKey.fromWif(wif);
      expect(key.toWif(), wif);
    });

    test('WIF round-trip (testnet pair)', () {
      const wif = '5JQy7moK9SvNNDxn8rKNfQYFME5VDYC2j9Mv2tb7uXV5jz3fQR8';
      final key = HivePrivateKey.fromWif(wif);
      expect(key.toWif(), wif);
    });

    test('rejects bad checksum', () {
      expect(
        () => HivePrivateKey.fromWif(
          '5K2yDAd9KAZ3ZitBsAPyRka9PLFemUrbcL6UziZiPaw2c6jCeLL',
        ),
        throwsA(isA<HiveCryptoException>()),
      );
    });

    test('fromLogin vector (dhive)', () {
      final key = HivePrivateKey.fromLogin('foo', 'barman');
      expect(
        key.createPublic().toString(),
        'STM87F7tN56tAUL2C6J9Gzi9HzgNpZdi6M2cLQo7TjDU5v178QsYA',
      );
    });

    test('fromSeed public key (dhive vote-tx test)', () {
      final key = HivePrivateKey.fromSeed('hello');
      expect(
        key.createPublic().toString(),
        'STM7s4VJuYFfHq8HCPpgC649Lu7CjA1V9oXgPfv8f3fszKMk3Kny9',
      );
    });
  });

  group('public keys', () {
    test('mainnet pair public key', () {
      const wif = '5K2yDAd9KAZ3ZitBsAPyRka9PLFemUrbcL6UziZiPaw2c6jCeLH';
      expect(
        HivePrivateKey.fromWif(wif).createPublic().toString(),
        'STM8QykigLRi9ZUcNy1iXGY3KjRuCiLM8Ga49LHti1F8hgawKFc3K',
      );
    });

    test('testnet pair public key keeps STX prefix', () {
      const wif = '5JQy7moK9SvNNDxn8rKNfQYFME5VDYC2j9Mv2tb7uXV5jz3fQR8';
      expect(
        HivePrivateKey.fromWif(wif).createPublic(prefix: 'STX').toString(),
        'STX8FiV6v7yqYWTZz8WuFDckWr62L9X34hCy6koe8vd2cDJHimtgM',
      );
    });

    test('decode compressed bytes vector (dhive mainPairPub)', () {
      final bytes = hexDecode(
        '03d0519ddad62bd2a833bee5dc04011c08f77f66338c38d99c685dee1f454cd1b8',
      );
      expect(
        HivePublicKey.fromCompressedBytes(bytes).toString(),
        'STM8QykigLRi9ZUcNy1iXGY3KjRuCiLM8Ga49LHti1F8hgawKFc3K',
      );
    });

    test('rejects bad public-key checksum', () {
      expect(
        () => HivePublicKey.fromString(
          'STM8QykigLRi9ZUcNy1iXGY3KjRuCiLM8Ga49LHti1F8hgawKFc3X',
        ),
        throwsA(isA<HiveCryptoException>()),
      );
    });
  });

  group('signatures', () {
    test('signature hex round-trip (dhive testSig)', () {
      const sigHex =
          '202c52188b0ecbc26c766fe6d3ec68dac58644f43f43fc7d97da122f76fa028f98'
          '691dd48b44394bdd8cecbbe66e94795dcf53291a1ef7c16b49658621273ea68e';
      final sig = HiveSignature.fromHex(sigHex);
      expect(sig.toHex(), sigHex);
      expect(sig.recovery, 1);
    });

    test('sign and verify round-trip, deterministic', () {
      final key = HivePrivateKey.fromSeed('hello');
      final digest = sha256(Uint8List.fromList('some message'.codeUnits));
      final sig1 = key.sign(digest);
      final sig2 = key.sign(digest);
      expect(sig1, sig2, reason: 'RFC 6979 signing must be deterministic');
      expect(key.createPublic().verify(digest, sig1), isTrue);
      final tampered = Uint8List.fromList(digest)..[0] ^= 0x01;
      expect(key.createPublic().verify(tampered, sig1), isFalse);
    });

    test('recover public key from signature', () {
      final key = HivePrivateKey.fromSeed('hello');
      final digest = sha256(Uint8List.fromList('recover me'.codeUnits));
      final sig = key.sign(digest);
      expect(
        HivePublicKey.recover(digest, sig).toString(),
        key.createPublic().toString(),
      );
    });

    test('dhive vote-tx signature, byte-for-byte', () {
      // Serialized transaction hex produced by dhive 1.3.2 for the
      // vote tx in dhive test/crypto.ts ("should sign and verify
      // transaction"). Signing these exact bytes must reproduce
      // dhive's signature exactly.
      const serializedHex =
          'd204f776e54207486a59010003666f6f036261720362617a1027010a'
          '6c6f6e672d70616e7473';
      const expectedSig =
          '2074b570ddbc83cea5a077fdbae211b9054590340776c17de86f237a2c'
          '136ef46c72a723057243514be6e01110703c87637a985bd10e7b7406cbd'
          '83fe652d71f5f';
      final key = HivePrivateKey.fromSeed('hello');
      final sig = HiveTransaction.signSerialized(
        hexDecode(serializedHex),
        key,
      );
      expect(sig.toHex(), expectedSig);
      // And the recovered key is the one dhive's test asserts.
      final digest = sha256(
        Uint8List.fromList([
          ...hexDecode(hiveMainnetChainIdHex),
          ...hexDecode(serializedHex),
        ]),
      );
      expect(
        HivePublicKey.recover(digest, sig).toString(),
        'STM7s4VJuYFfHq8HCPpgC649Lu7CjA1V9oXgPfv8f3fszKMk3Kny9',
      );
    });
  });
}
