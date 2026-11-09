// Model tests: account-history parsing (both wire shapes) and NAI
// amounts. All network is faked or absent; the real-envelope
// fixture is `test/fixtures/account_history_real.json` — five entries
// captured live from api.hive.blog (`account_history_api.
// get_account_history`, account `carlosepc`, 2026-11-05).
import 'dart:convert';
import 'dart:io';

import 'package:hive_dart/hive_dart.dart';
import 'package:test/test.dart';

Map<String, dynamic> _realEnvelope() {
  final raw = File(
    'test/fixtures/account_history_real.json',
  ).readAsStringSync();
  return jsonDecode(raw) as Map<String, dynamic>;
}

void main() {
  group('formatNaiAmount', () {
    test('formats the three known assets', () {
      expect(
        formatNaiAmount({
          'nai': '@@000000021',
          'amount': '2',
          'precision': 3,
        }),
        '0.002 HIVE',
      );
      expect(
        formatNaiAmount({
          'nai': '@@000000013',
          'amount': '18578',
          'precision': 3,
        }),
        '18.578 HBD',
      );
      expect(
        formatNaiAmount({
          'nai': '@@000000037',
          'amount': '3225107',
          'precision': 6,
        }),
        '3.225107 VESTS',
      );
    });

    test('keeps exactly `precision` decimals, including trailing zeros',
        () {
      expect(
        formatNaiAmount({
          'nai': '@@000000021',
          'amount': '0',
          'precision': 3,
        }),
        '0.000 HIVE',
      );
      expect(
        formatNaiAmount({
          'nai': '@@000000021',
          'amount': '411538',
          'precision': 3,
        }),
        '411.538 HIVE',
      );
    });

    test('handles zero precision and negative amounts', () {
      expect(
        formatNaiAmount({
          'nai': '@@000000021',
          'amount': '5',
          'precision': 0,
        }),
        '5 HIVE',
      );
      expect(
        formatNaiAmount({
          'nai': '@@000000013',
          'amount': '-1500',
          'precision': 3,
        }),
        '-1.500 HBD',
      );
    });

    test('returns null for unknown NAIs and malformed objects', () {
      expect(
        formatNaiAmount({
          'nai': '@@000000099',
          'amount': '1',
          'precision': 3,
        }),
        isNull,
      );
      expect(formatNaiAmount({'nai': '@@000000021', 'amount': '1'}), isNull);
      expect(
        formatNaiAmount({
          'nai': '@@000000021',
          'amount': 'abc',
          'precision': 3,
        }),
        isNull,
      );
      // Extra keys: not a bare amount object.
      expect(
        formatNaiAmount({
          'nai': '@@000000021',
          'amount': '1',
          'precision': 3,
          'extra': true,
        }),
        isNull,
      );
    });
  });

  group('parseHistoryOp', () {
    test('keeps the legacy tuple shape (and normalises its values)',
        () {
      final op = parseHistoryOp([
        'transfer',
        {'from': 'a', 'to': 'b', 'amount': '0.002 HIVE'},
      ]);
      expect(op, [
        'transfer',
        {'from': 'a', 'to': 'b', 'amount': '0.002 HIVE'},
      ]);
    });

    test('strips the _operation suffix from the modern shape', () {
      final op = parseHistoryOp({
        'type': 'comment_operation',
        'value': {'author': 'alice', 'permlink': 'x'},
      });
      expect(op[0], 'comment');
      expect(op[1], {'author': 'alice', 'permlink': 'x'});
    });

    test('converts nested NAI amounts in the modern shape', () {
      final op = parseHistoryOp({
        'type': 'transfer_operation',
        'value': {
          'from': 'a',
          'to': 'b',
          'amount': {'nai': '@@000000021', 'amount': '2', 'precision': 3},
        },
      });
      expect(op[0], 'transfer');
      expect((op[1] as Map)['amount'], '0.002 HIVE');
    });

    test('leaves unknown NAI objects untouched', () {
      final op = parseHistoryOp({
        'type': 'transfer_operation',
        'value': {
          'amount': {'nai': '@@000000099', 'amount': '1', 'precision': 3},
        },
      });
      expect(
        (op[1] as Map)['amount'],
        {'nai': '@@000000099', 'amount': '1', 'precision': 3},
      );
    });

    test('throws on malformed ops', () {
      expect(() => parseHistoryOp(['only-one']), throwsA(isA<HiveParseException>()));
      expect(
        () => parseHistoryOp({'type': 'transfer_operation'}),
        throwsA(isA<HiveParseException>()),
      );
      expect(() => parseHistoryOp('nope'), throwsA(isA<HiveParseException>()));
    });
  });

  group('HiveAccountHistoryEntry.fromJson', () {
    test('parses the real live envelope', () {
      final envelope = _realEnvelope();
      final entries = (envelope['history'] as List)
          .map((e) => HiveAccountHistoryEntry.fromJson(e as List<dynamic>))
          .toList();
      expect(entries, hasLength(5));

      final transfer = entries[0];
      expect(transfer.sequence, 5148);
      expect(transfer.op[0], 'transfer');
      expect((transfer.op[1] as Map)['amount'], '0.002 HIVE');
      expect((transfer.op[1] as Map)['from'], 'curangel');

      final limit = entries[1];
      expect(limit.op[0], 'limit_order_create');
      expect(
        (limit.op[1] as Map)['amount_to_sell'],
        '411.538 HIVE',
      );
      expect((limit.op[1] as Map)['min_to_receive'], '18.578 HBD');

      final claim = entries[2];
      expect(claim.op[0], 'claim_reward_balance');
      expect((claim.op[1] as Map)['reward_hbd'], '0.000 HBD');
      expect((claim.op[1] as Map)['reward_hive'], '0.000 HIVE');
      expect((claim.op[1] as Map)['reward_vests'], '3.225107 VESTS');

      final comment = entries[3];
      expect(comment.op[0], 'comment');
      expect((comment.op[1] as Map)['author'], 'carlosepc');
      expect(
        (comment.op[1] as Map)['permlink'],
        're-gwajnberg-tkuipx',
      );

      final custom = entries[4];
      expect(custom.op[0], 'custom_json');
      expect((custom.op[1] as Map)['id'], 'sm_claim_reward');
    });

    test('still parses the legacy tuple shape', () {
      final entry = HiveAccountHistoryEntry.fromJson([
        10,
        {
          'block': 100,
          'timestamp': '2026-01-01T00:00:00',
          'op': [
            'custom_json',
            {'id': 'test', 'json': '{}'},
          ],
          'trx_id': 'ab' * 20,
        },
      ]);
      expect(entry.sequence, 10);
      expect(entry.op[0], 'custom_json');
      expect(entry.trxId, 'ab' * 20);
    });
  });

  group('HiveAccount', () {
    test('exposes posting_json_metadata', () {
      final account = HiveAccount.fromJson({
        'id': 1,
        'name': 'carlosepc',
        'created': '2024-03-23T05:00:12',
        'reputation': 0,
        'balance': '492.492 HIVE',
        'hbd_balance': '0.920 HBD',
        'vesting_shares': '354906.938299 VESTS',
        'posting': <String, dynamic>{},
        'json_metadata': '',
        'posting_json_metadata':
            '{"profile":{"name":"Carlos Enrique"}}',
        'post_count': 280,
      });
      expect(account.jsonMetadata, '');
      expect(
        account.postingJsonMetadata,
        '{"profile":{"name":"Carlos Enrique"}}',
      );
    });

    test('defaults posting_json_metadata to empty when absent', () {
      final account = HiveAccount.fromJson({
        'id': 1,
        'name': 'alice',
        'created': '2024-01-01T00:00:00',
        'reputation': 0,
        'balance': '0.000 HIVE',
        'hbd_balance': '0.000 HBD',
        'vesting_shares': '0.000000 VESTS',
        'posting': <String, dynamic>{},
        'json_metadata': '{}',
        'post_count': 0,
      });
      expect(account.postingJsonMetadata, '');
    });
  });
}
