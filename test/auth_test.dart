// Auth tests — HAS message shapes per docs.hiveauth.com and the
// hive-uri spec (hive:// deep links).
import 'dart:convert';

import 'package:hiveblockchain_dart/hiveblockchain_dart.dart';
import 'package:test/test.dart';

void main() {
  group('HiveAuth (HAS)', () {
    test('authRequest builds an encrypted auth_req', () {
      const authKey = 'auth-key-uuid-1';
      final message = HiveAuth.authRequest(
        account: 'alice',
        authKey: authKey,
        app: HiveAuthApp(name: 'Gloti', description: 'Learn English'),
      );
      expect(message['cmd'], 'auth_req');
      expect(message['account'], 'alice');
      final data = jsonDecode(
        cryptoJsAesDecrypt(message['data'] as String, authKey),
      ) as Map<String, dynamic>;
      expect(data['app']['name'], 'Gloti');
    });

    test('signRequest builds an encrypted sign_req', () {
      const authKey = 'auth-key-uuid-2';
      final op = HiveOperation.customJson(
        requiredAuths: const [],
        requiredPostingAuths: const ['alice'],
        id: 'gloti_reward',
        json: '{"story":"yumi","chapter":1}',
      );
      final message = HiveAuth.signRequest(
        account: 'alice',
        authKey: authKey,
        ops: [op],
        keyType: 'posting',
        broadcast: true,
      );
      expect(message['cmd'], 'sign_req');
      final data = jsonDecode(
        cryptoJsAesDecrypt(message['data'] as String, authKey),
      ) as Map<String, dynamic>;
      expect(data['key_type'], 'posting');
      expect(data['broadcast'], isTrue);
      expect(data['ops'], [
        [
          'custom_json',
          {
            'required_auths': [],
            'required_posting_auths': ['alice'],
            'id': 'gloti_reward',
            'json': '{"story":"yumi","chapter":1}',
          },
        ],
      ]);
    });

    test('decryptAck decodes an encrypted ack', () {
      const authKey = 'auth-key-uuid-3';
      final ack = {
        'cmd': 'auth_ack',
        'account': 'alice',
        'token': 'session-token',
        'expire': 1700000000,
      };
      final encrypted = cryptoJsAesEncrypt(jsonEncode(ack), authKey);
      final decoded = HiveAuth.decryptAck(
        {'cmd': 'auth_ack', 'data': encrypted},
        authKey,
      );
      expect(decoded['token'], 'session-token');
      expect(decoded['expire'], 1700000000);
    });

    test('parseWait extracts uuid and expire', () {
      final wait = HiveAuth.parseWait({
        'cmd': 'auth_wait',
        'uuid': 'some-uuid',
        'expire': 1700000060,
      });
      expect(wait.uuid, 'some-uuid');
      expect(wait.expire, 1700000060);
    });

    test('auth payload deep link round-trip', () {
      final payload = HiveAuthPayload(
        account: 'alice',
        uuid: 'uuid-123',
        key: 'auth-key-uuid-4',
      );
      final link = payload.toDeepLink();
      expect(link.startsWith('has://auth_req/'), isTrue);
      final parsed = HiveAuthPayload.fromDeepLink(link);
      expect(parsed.account, 'alice');
      expect(parsed.uuid, 'uuid-123');
      expect(parsed.key, 'auth-key-uuid-4');
      expect(parsed.host, 'wss://has.hiveauth.com');
    });
  });

  group('Hive Keychain (hive-uri)', () {
    test('signOpUri encodes a vote op, decodable (hive-uri doc vector)',
        () {
      // The hive-uri docs encode this exact op as
      // hive://sign/op/WyJ2b3RlIix7InZvdGVyIjoiZm9vIiwiYXV0aG9yIjoiYmFyIiwicGVybWxpbmsiOiJiYXoiLCJ3ZWlnaHQiOjEwMDAwfV0
      // (base64url, no padding).
      const knownUri =
          'hive://sign/op/WyJ2b3RlIix7InZvdGVyIjoiZm9vIiwiYXV0aG9yIjoiYmFyIiwicGVybWxpbmsiOiJiYXoiLCJ3ZWlnaHQiOjEwMDAwfV0';
      final parsed = HiveKeychain.parseSignUri(knownUri);
      expect(parsed.action, 'op');
      expect(parsed.payload, [
        'vote',
        {
          'voter': 'foo',
          'author': 'bar',
          'permlink': 'baz',
          'weight': 10000,
        },
      ]);
      expect(parsed.signer, isNull);
      expect(parsed.callback, isNull);
    });

    test('signOpUri round-trip with signer and callback', () {
      final op = HiveOperation.customJson(
        requiredAuths: const [],
        requiredPostingAuths: const ['alice'],
        id: 'genioo_achievement',
        json: '{"game":"minesweeper","score":42}',
      );
      final uri = HiveKeychain.signOpUri(
        op,
        signer: 'alice',
        callback: 'https://example.com/wallet?tx={{id}}',
      );
      expect(uri.startsWith('hive://sign/op/'), isTrue);
      final parsed = HiveKeychain.parseSignUri(uri);
      expect(parsed.action, 'op');
      expect(parsed.payload, [
        'custom_json',
        {
          'required_auths': [],
          'required_posting_auths': ['alice'],
          'id': 'genioo_achievement',
          'json': '{"game":"minesweeper","score":42}',
        },
      ]);
      expect(parsed.signer, 'alice');
      expect(parsed.callback, 'https://example.com/wallet?tx={{id}}');
    });

    test('signOpsUri and signTxUri round-trip', () {
      final ops = [
        HiveOperation.customJson(
          requiredAuths: const [],
          requiredPostingAuths: const ['alice'],
          id: 'a',
          json: '{}',
        ),
        HiveOperation.customJson(
          requiredAuths: const [],
          requiredPostingAuths: const ['alice'],
          id: 'b',
          json: '{}',
        ),
      ];
      final opsUri = HiveKeychain.signOpsUri(ops);
      expect(HiveKeychain.parseSignUri(opsUri).action, 'ops');
      expect(
        (HiveKeychain.parseSignUri(opsUri).payload as List).length,
        2,
      );

      final tx = HiveTransaction(
        refBlockNum: 1,
        refBlockPrefix: 2,
        expiration: DateTime.utc(2026, 1, 1),
        operations: ops,
      );
      final txUri = HiveKeychain.signTxUri(tx);
      final parsed = HiveKeychain.parseSignUri(txUri);
      expect(parsed.action, 'tx');
      expect((parsed.payload as Map)['ref_block_num'], 1);
    });

    test('parseSignUri rejects non-hive URIs', () {
      expect(
        () => HiveKeychain.parseSignUri('https://example.com/x'),
        throwsA(isA<HiveAuthException>()),
      );
    });
  });
}
