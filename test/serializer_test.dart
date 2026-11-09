// Serialization tests — expected hex produced by dhive 1.3.2
// (live Node run, see README "Test vectors").
import 'dart:typed_data';

import 'package:hiveblockchain_dart/hiveblockchain_dart.dart';
import 'package:test/test.dart';

void main() {
  group('TxWriter primitives', () {
    test('varint', () {
      Uint8List write(int v) {
        final w = TxWriter()..writeVarint(v);
        return w.toBytes();
      }

      expect(write(0), [0]);
      expect(write(1), [1]);
      expect(write(127), [127]);
      expect(write(128), [0x80, 0x01]);
      expect(write(300), [0xac, 0x02]);
      expect(write(10000), [0x90, 0x4e]);
    });

    test('integers are little-endian', () {
      final w = TxWriter()
        ..writeUint16(1234)
        ..writeUint32(1122334455);
      expect(hexEncode(w.toBytes()), 'd204f776e542');
    });

    test('string is varint length + utf8', () {
      final w = TxWriter()..writeString('foo');
      expect(hexEncode(w.toBytes()), '03666f6f');
      final empty = TxWriter()..writeString('');
      expect(hexEncode(empty.toBytes()), '00');
    });

    test('array is varint count + items', () {
      final w = TxWriter();
      w.writeArray<String>(['a', 'bb'], w.writeString);
      expect(hexEncode(w.toBytes()), '020161026262');
    });

    test('int64 is little-endian two\'s complement', () {
      final positive = TxWriter()..writeInt64(BigInt.from(1000000000));
      expect(hexEncode(positive.toBytes()), '00ca9a3b00000000');
      final minusOne = TxWriter()..writeInt64(BigInt.from(-1));
      expect(hexEncode(minusOne.toBytes()), 'ffffffffffffffff');
    });

    test('bool is one byte', () {
      final yes = TxWriter()..writeBool(true);
      expect(hexEncode(yes.toBytes()), '01');
      final no = TxWriter()..writeBool(false);
      expect(hexEncode(no.toBytes()), '00');
    });

    test('asset is int64 amount + precision + 7-byte symbol', () {
      // Wire symbols are the legacy Steem names (dhive
      // `AssetSerializer` calls `steem_symbols()`): HBD -> SBD,
      // HIVE -> STEEM.
      final hbd = TxWriter()..writeAsset('1000000.000 HBD');
      expect(hexEncode(hbd.toBytes()), '00ca9a3b000000000353424400000000');
      final hive = TxWriter()..writeAsset('1.500 HIVE');
      expect(hexEncode(hive.toBytes()), 'dc0500000000000003535445454d0000');
      final whole = TxWriter()..writeAsset('42 HIVE');
      expect(hexEncode(whole.toBytes()), '2a0000000000000000535445454d0000');
    });

    test('asset rejects malformed values', () {
      expect(() => (TxWriter()..writeAsset('nope')), throwsA(isA<HiveSerializationException>()));
      expect(
        () => (TxWriter()..writeAsset('1.00 TOOLONGSYM')),
        throwsA(isA<HiveSerializationException>()),
      );
      expect(
        () => (TxWriter()..writeAsset('abc HBD')),
        throwsA(isA<HiveSerializationException>()),
      );
    });
  });

  group('operation serialization vs dhive', () {
    test('custom_json op bytes', () {
      final op = HiveOperation.customJson(
        requiredAuths: const [],
        requiredPostingAuths: const ['alice'],
        id: 'genioo_achievement',
        json: '{"game":"minesweeper","score":42}',
      );
      final w = TxWriter()..writeVarint(1); // one operation, like a tx
      op.serialize(w);
      // Full tx bytes from dhive: d204 f776e542 07486a59 | 01 12 ... | 00
      // Here we check only the op portion (after the 8 header bytes
      // and the op-count varint).
      final full = HiveTransaction(
        refBlockNum: 1234,
        refBlockPrefix: 1122334455,
        expiration: DateTime.utc(2017, 7, 15, 16, 51, 19),
        operations: [op],
      ).serialize();
      expect(
        hexEncode(full),
        'd204f776e54207486a590112000105616c6963651267656e696f6f5f'
        '616368696576656d656e74217b2267616d65223a226d696e657377656570'
        '6572222c2273636f7265223a34327d00',
      );
    });

    test('comment op bytes', () {
      final op = HiveOperation.comment(
        parentAuthor: '',
        parentPermlink: 'hive-123',
        author: 'alice',
        permlink: 'my-first-post',
        title: 'Hello',
        body: 'Body text',
        jsonMetadata: '{}',
      );
      final full = HiveTransaction(
        refBlockNum: 1234,
        refBlockPrefix: 1122334455,
        expiration: DateTime.utc(2017, 7, 15, 16, 51, 19),
        operations: [op],
      ).serialize();
      expect(
        hexEncode(full),
        'd204f776e54207486a5901010008686976652d31323305616c6963650d'
        '6d792d66697273742d706f73740548656c6c6f09426f6479207465787402'
        '7b7d00',
      );
    });

    test('comment_options op bytes (dhive 1.3.2, live Node run)', () {
      final op = HiveOperation.commentOptions(
        author: 'alice',
        permlink: 'gloti-yumi-1234567890123',
        beneficiaries: const [HiveBeneficiary('hivepen', 1000)],
      );
      final full = HiveTransaction(
        refBlockNum: 1234,
        refBlockPrefix: 1122334455,
        expiration: DateTime.utc(2017, 7, 15, 16, 51, 19),
        operations: [op],
      ).serialize();
      expect(
        hexEncode(full),
        'd204f776e54207486a59011305616c69636518676c6f74692d79756d692d'
        '3132333435363738393031323300ca9a3b000000000353424400000000'
        '10270101010001076869766570656ee80300',
      );
    });

    test('comment_options JSON form matches dhive', () {
      final op = HiveOperation.commentOptions(
        author: 'alice',
        permlink: 'gloti-yumi-1234567890123',
        beneficiaries: const [HiveBeneficiary('hivepen', 1000)],
      );
      expect(op.toJson(), [
        'comment_options',
        {
          'author': 'alice',
          'permlink': 'gloti-yumi-1234567890123',
          'max_accepted_payout': '1000000.000 HBD',
          'percent_hbd': 10000,
          'allow_votes': true,
          'allow_curation_rewards': true,
          'extensions': [
            [
              0,
              {
                'beneficiaries': [
                  {'account': 'hivepen', 'weight': 1000},
                ],
              },
            ],
          ],
        },
      ]);
    });

    test('comment_options without beneficiaries has empty extensions '
        '(dhive 1.3.2, live Node run)', () {
      final op = HiveOperation.commentOptions(
        author: 'alice',
        permlink: 'gloti-yumi-1234567890123',
      );
      expect(op.data['extensions'], isEmpty);
      final full = HiveTransaction(
        refBlockNum: 1234,
        refBlockPrefix: 1122334455,
        expiration: DateTime.utc(2017, 7, 15, 16, 51, 19),
        operations: [op],
      ).serialize();
      expect(
        hexEncode(full),
        'd204f776e54207486a59011305616c69636518676c6f74692d79756d692d'
        '3132333435363738393031323300ca9a3b000000000353424400000000'
        '102701010000',
      );
    });

    test('vote tx bytes (dhive test/crypto.ts vector)', () {
      // The vote op itself is not part of the v1 API; build its bytes
      // with the public TxWriter to verify the shared primitives
      // against dhive's vector, then sign the exact bytes.
      final w = TxWriter()
        ..writeUint16(1234)
        ..writeUint32(1122334455)
        ..writeUint32(1500137479) // 2017-07-15T16:51:19Z
        ..writeVarint(1) // one operation
        ..writeVarint(0) // vote
        ..writeString('foo')
        ..writeString('bar')
        ..writeString('baz')
        ..writeUint16(10000)
        ..writeVarint(1) // one extension
        ..writeString('long-pants');
      expect(
        hexEncode(w.toBytes()),
        'd204f776e54207486a59010003666f6f036261720362617a1027010a'
        '6c6f6e672d70616e7473',
      );
    });
  });
}
