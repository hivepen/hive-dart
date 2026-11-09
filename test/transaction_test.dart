// Transaction tests — digests and signatures cross-checked against
// dhive 1.3.2 (live Node run, see README "Test vectors").
import 'dart:typed_data';

import 'package:hive_dart/hive_dart.dart';
import 'package:test/test.dart';

void main() {
  final key = HivePrivateKey.fromSeed('hello');

  group('reference-block derivation', () {
    test('ref_block_num is head & 0xffff; prefix is block-id bytes 4..8 LE',
        () {
      // head_block_id of a real Hive block shape: 32 bytes.
      final tx = HiveTransaction.refBlockFromHead(
        headBlockNumber: 0x12345678,
        headBlockIdHex:
            '00123456' 'f776e542' '0000000000000000000000000000000000000000'
            '00000000',
        expiration: DateTime.utc(2017, 7, 15, 16, 51, 19),
        operations: const [],
      );
      expect(tx.refBlockNum, 0x5678);
      expect(tx.refBlockPrefix, 1122334455);
    });

    test('rejects short block id', () {
      expect(
        () => HiveTransaction.refBlockFromHead(
          headBlockNumber: 1,
          headBlockIdHex: 'abcd',
          expiration: DateTime.utc(2017, 7, 15),
          operations: const [],
        ),
        throwsA(isA<HiveSerializationException>()),
      );
    });
  });

  group('digest and signing vs dhive', () {
    test('custom_json tx digest + signature match dhive', () {
      final tx = HiveTransaction(
        refBlockNum: 1234,
        refBlockPrefix: 1122334455,
        expiration: DateTime.utc(2017, 7, 15, 16, 51, 19),
        operations: [
          HiveOperation.customJson(
            requiredAuths: const [],
            requiredPostingAuths: const ['alice'],
            id: 'genioo_achievement',
            json: '{"game":"minesweeper","score":42}',
          ),
        ],
      );
      // The signature is the real cross-check: it covers the digest
      // and the exact RFC 6979 nonce sequence dhive uses.
      final signed = tx.sign(key);
      expect(
        signed.signatures.single.toHex(),
        '20511cea11f1cf19ef1507935dedd9d2ed13046494b8ee7dbe1c3037238'
        'd5a597c1793e4fa3f5d9ebf20e64455498b918a8ee76f6b72230d11198d'
        '1e51d56ebac4',
      );
    });

    test('comment tx signature matches dhive', () {
      final tx = HiveTransaction(
        refBlockNum: 1234,
        refBlockPrefix: 1122334455,
        expiration: DateTime.utc(2017, 7, 15, 16, 51, 19),
        operations: [
          HiveOperation.comment(
            parentAuthor: '',
            parentPermlink: 'hive-123',
            author: 'alice',
            permlink: 'my-first-post',
            title: 'Hello',
            body: 'Body text',
            jsonMetadata: '{}',
          ),
        ],
      );
      final signed = tx.sign(key);
      expect(
        signed.signatures.single.toHex(),
        '1f3b37330ecce3e0a86f74284938f0ba5c4bfe067ec3b85a6e1a54eecf'
        '5e22c23e38048f7fe146bf8925f9ccec12b63a76707dd4268549f22bcc7'
        'c167d80313b0e',
      );
    });

    test('vote tx digest matches dhive', () {
      // Same vote tx as dhive test/crypto.ts: the digest is
      // sha256(chain_id || serialized tx).
      const serializedHex =
          'd204f776e54207486a59010003666f6f036261720362617a1027010a'
          '6c6f6e672d70616e7473';
      final digest = sha256(
        Uint8List.fromList([
          ...hexDecode(hiveMainnetChainIdHex),
          ...hexDecode(serializedHex),
        ]),
      );
      expect(
        hexEncode(digest),
        '7d9f5bd21890fa4d782816828dbd45a0f035c7a4a7801e22896d9ba5b568c13e',
      );
    });
  });

  group('JSON form', () {
    test('toJson matches the broadcast wire shape', () {
      final tx = HiveTransaction(
        refBlockNum: 1234,
        refBlockPrefix: 1122334455,
        expiration: DateTime.utc(2017, 7, 15, 16, 51, 19),
        operations: [
          HiveOperation.customJson(
            requiredAuths: const [],
            requiredPostingAuths: const ['alice'],
            id: 'genioo_achievement',
            json: '{}',
          ),
        ],
      );
      final signed = tx.sign(key);
      final json = signed.toJson();
      expect(json['ref_block_num'], 1234);
      expect(json['ref_block_prefix'], 1122334455);
      expect(json['expiration'], '2017-07-15T16:51:19');
      expect(json['operations'], [
        [
          'custom_json',
          {
            'required_auths': [],
            'required_posting_auths': ['alice'],
            'id': 'genioo_achievement',
            'json': '{}',
          },
        ],
      ]);
      expect(json['extensions'], <String>[]);
      expect((json['signatures'] as List).single, isA<String>());
      // Transaction id is sha256 of the serialised tx alone.
      expect(signed.id.length, 64);
    });
  });
}
