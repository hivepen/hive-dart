// Client tests — all network is faked with a canned [http.Client].
import 'dart:convert';
import 'dart:io';

import 'package:hiveblockchain_dart/hiveblockchain_dart.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

/// A fake node that answers from a map of `api.method` → result,
/// and records every request it sees.
class FakeNode extends MockClient {
  FakeNode(this.handlers) : super((_) async => throw UnimplementedError());

  final Map<String, dynamic Function(Map<String, dynamic> request)>
      handlers;
  final requests = <Map<String, dynamic>>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final body = await request.finalize().bytesToString();
    final decoded = jsonDecode(body) as Map<String, dynamic>;
    requests.add(decoded);
    final params = decoded['params'] as List;
    final key = '${params[0]}.${params[1]}';
    final handler = handlers[key];
    if (handler == null) {
      return _respond(200, {
        'jsonrpc': '2.0',
        'error': {'code': -32601, 'message': 'Method not found'},
        'id': decoded['id'],
      });
    }
    final result = handler(decoded);
    if (result is HiveRpcException) {
      return _respond(200, {
        'jsonrpc': '2.0',
        'error': {'code': result.code, 'message': result.message},
        'id': decoded['id'],
      });
    }
    return _respond(200, {
      'jsonrpc': '2.0',
      'result': result,
      'id': decoded['id'],
    });
  }

  http.StreamedResponse _respond(int status, Map<String, dynamic> json) {
    final bytes = utf8.encode(jsonEncode(json));
    return http.StreamedResponse(
      Stream.value(bytes),
      status,
      headers: {'content-type': 'application/json'},
    );
  }
}

Map<String, dynamic> _accountJson() => {
      'id': 1234,
      'name': 'carlosepc',
      'created': '2021-01-01T00:00:00',
      'reputation': 123456789,
      'balance': '10.500 HIVE',
      'hbd_balance': '2.250 HBD',
      'vesting_shares': '1000.000000 VESTS',
      'posting': {
        'weight_threshold': 1,
        'account_auths': [],
        'key_auths': [
          ['STM8QykigLRi9ZUcNy1iXGY3KjRuCiLM8Ga49LHti1F8hgawKFc3K', 1],
        ],
      },
      'json_metadata': '{}',
      'posting_json_metadata':
          '{"profile":{"name":"Carlos Enrique"}}',
      'post_count': 42,
    };

Map<String, dynamic> _dgpJson() => {
      'head_block_number': 98765432,
      'head_block_id':
          '05e3c478f776e542000000000000000000000000000000000000000000000000',
      'time': '2026-11-05T12:00:00',
      'current_witness': 'witness1',
      'total_vesting_fund_hive': '100000.000 HIVE',
      'total_vesting_shares': '200000.000000 VESTS',
    };

HiveClient _client(FakeNode node, {List<String>? nodes}) => HiveClient(
      nodes: nodes ?? ['https://node-a.example', 'https://node-b.example'],
      httpClient: node,
    );

void main() {
  group('reads', () {
    test('getAccount parses the account', () async {
      final node = FakeNode({
        'condenser_api.get_accounts': (_) => [_accountJson()],
      });
      final client = _client(node);
      final account = await client.getAccount('carlosepc');
      expect(account, isNotNull);
      expect(account!.name, 'carlosepc');
      expect(account.balance, '10.500 HIVE');
      expect(account.postCount, 42);
      expect(
        account.postingJsonMetadata,
        '{"profile":{"name":"Carlos Enrique"}}',
      );
      expect(account.postingKeys, [
        'STM8QykigLRi9ZUcNy1iXGY3KjRuCiLM8Ga49LHti1F8hgawKFc3K',
      ]);
      // The request used the condenser_api calling convention.
      final request = node.requests.single;
      expect(request['method'], 'call');
      expect(request['params'][0], 'condenser_api');
      expect(request['params'][1], 'get_accounts');
      expect(request['params'][2], [
        ['carlosepc'],
      ]);
    });

    test('getAccount returns null when the node returns an empty list',
        () async {
      final node = FakeNode({
        'condenser_api.get_accounts': (_) => [],
      });
      expect(await _client(node).getAccount('nobody'), isNull);
    });

    test('getContent returns null for missing content', () async {
      final node = FakeNode({
        'condenser_api.get_content': (_) => {'id': 0, 'author': ''},
      });
      expect(
        await _client(node).getContent('alice', 'nope'),
        isNull,
      );
    });

    test('getContent parses a post', () async {
      final node = FakeNode({
        'condenser_api.get_content': (_) => {
              'id': 99,
              'author': 'alice',
              'permlink': 'hello',
              'parent_author': '',
              'parent_permlink': 'spanish',
              'title': 'Hello',
              'body': 'Body',
              'json_metadata': '{}',
              'created': '2026-01-01T00:00:00',
              'children': 3,
              'net_votes': 5,
              'pending_payout_value': '1.250 HBD',
            },
      });
      final content = await _client(node).getContent('alice', 'hello');
      expect(content!.title, 'Hello');
      expect(content.netVotes, 5);
      expect(content.children, 3);
    });

    test('getDynamicGlobalProperties + ref-block derivation', () async {
      final node = FakeNode({
        'condenser_api.get_dynamic_global_properties': (_) => _dgpJson(),
      });
      final client = _client(node);
      final props = await client.getDynamicGlobalProperties();
      expect(props.headBlockNumber, 98765432);
      expect(props.headBlockId, _dgpJson()['head_block_id']);
      final tx = await client.prepareTransaction([
        HiveOperation.customJson(
          requiredAuths: const [],
          requiredPostingAuths: const ['alice'],
          id: 'test',
          json: '{}',
        ),
      ]);
      expect(tx.refBlockNum, 98765432 & 0xffff);
      // head_block_id bytes [4..8] are f7 76 e5 42 → 1122334455.
      expect(tx.refBlockPrefix, 1122334455);
    });

    test('getAccountHistory parses entries', () async {
      final node = FakeNode({
        'account_history_api.get_account_history': (_) => [
              [
                10,
                {
                  'block': 100,
                  'timestamp': '2026-01-01T00:00:00',
                  'op': [
                    'custom_json',
                    {
                      'required_auths': [],
                      'required_posting_auths': ['alice'],
                      'id': 'test',
                      'json': '{}',
                    },
                  ],
                  'trx_id': 'ab' * 20,
                },
              ],
            ],
      });
      final entries = await _client(node).getAccountHistory(
        'alice',
        limit: 1,
      );
      expect(entries.single.sequence, 10);
      expect(entries.single.op[0], 'custom_json');
      expect(entries.single.trxId, 'ab' * 20);
    });

    test('getAccountHistory parses the real live envelope', () async {
      // Fixture: five entries captured live from api.hive.blog
      // (account carlosepc, 2026-11-05) — see
      // test/fixtures/account_history_real.json.
      final envelope = jsonDecode(
        File(
          'test/fixtures/account_history_real.json',
        ).readAsStringSync(),
      );
      final node = FakeNode({
        'account_history_api.get_account_history': (_) => envelope,
      });
      final entries = await _client(node).getAccountHistory(
        'carlosepc',
        limit: 5,
      );
      expect(entries, hasLength(5));
      expect(entries[0].op[0], 'transfer');
      expect((entries[0].op[1] as Map)['amount'], '0.002 HIVE');
      expect(entries[1].op[0], 'limit_order_create');
      expect(
        (entries[1].op[1] as Map)['min_to_receive'],
        '18.578 HBD',
      );
      expect(entries[2].op[0], 'claim_reward_balance');
      expect(
        (entries[2].op[1] as Map)['reward_vests'],
        '3.225107 VESTS',
      );
      expect(entries[3].op[0], 'comment');
      expect(entries[4].op[0], 'custom_json');
    });

    test('getAccountHistory rejects a non-list, non-envelope result',
        () async {
      final node = FakeNode({
        'account_history_api.get_account_history': (_) => 'nope',
      });
      expect(
        () => _client(node).getAccountHistory('alice'),
        throwsA(isA<HiveParseException>()),
      );
    });
  });

  group('failover', () {
    test('transport failure moves to the next node', () async {
      var calls = 0;
      final flaky = MockClient((request) async {
        calls++;
        if (calls == 1) {
          return http.Response('boom', 500);
        }
        return http.Response(
          jsonEncode({
            'jsonrpc': '2.0',
            'result': [_accountJson()],
            'id': 1,
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final client = HiveClient(
        nodes: const ['https://node-a.example', 'https://node-b.example'],
        httpClient: flaky,
      );
      final account = await client.getAccount('carlosepc');
      expect(account!.name, 'carlosepc');
      expect(calls, 2);
    });

    test('all nodes failing throws HiveNetworkException', () async {
      final failing = MockClient(
        (_) async => http.Response('boom', 500),
      );
      final client = HiveClient(httpClient: failing);
      expect(
        () => client.getAccount('carlosepc'),
        throwsA(isA<HiveNetworkException>()),
      );
    });

    test('JSON-RPC error is reported, not failed over', () async {
      var calls = 0;
      final node = MockClient((_) async {
        calls++;
        return http.Response(
          jsonEncode({
            'jsonrpc': '2.0',
            'error': {'code': -32003, 'message': 'assert exception'},
            'id': 1,
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final client = HiveClient(httpClient: node);
      await expectLater(
        client.getAccount('carlosepc'),
        throwsA(
          isA<HiveRpcException>().having((e) => e.code, 'code', -32003),
        ),
      );
      expect(calls, 1, reason: 'RPC errors must not trigger failover');
    });
  });

  group('broadcast', () {
    test('broadcast sends the signed tx JSON', () async {
      final node = FakeNode({
        'condenser_api.get_dynamic_global_properties': (_) => _dgpJson(),
        'condenser_api.broadcast_transaction_synchronous': (_) => {
              'id': 'cd' * 20,
              'block_num': 98765433,
              'trx_num': 0,
              'expired': false,
            },
      });
      final client = _client(node);
      final key = HivePrivateKey.fromSeed('hello');
      final result = await client.broadcastOperations(
        [
          HiveOperation.customJson(
            requiredAuths: const [],
            requiredPostingAuths: const ['alice'],
            id: 'test',
            json: '{}',
          ),
        ],
        key,
      );
      expect(result.id, 'cd' * 20);
      expect(result.blockNum, 98765433);
      expect(result.expired, isFalse);
      final broadcast = node.requests.last;
      expect(
        broadcast['params'][1],
        'broadcast_transaction_synchronous',
      );
      final tx = (broadcast['params'][2] as List).single
          as Map<String, dynamic>;
      expect((tx['signatures'] as List).single, isA<String>());
      expect(tx['operations'], [
        [
          'custom_json',
          {
            'required_auths': [],
            'required_posting_auths': ['alice'],
            'id': 'test',
            'json': '{}',
          },
        ],
      ]);
    });
  });
}
