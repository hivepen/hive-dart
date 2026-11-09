/// JSON-RPC client for public Hive API nodes.
///
/// Transport is plain HTTPS POST with a JSON-RPC 2.0 envelope
/// (`{"jsonrpc":"2.0","method":"call","params":[api, method, args],
/// "id":n}` — the `condenser_api` calling convention dhive uses).
/// No signing happens here: reads need no keys, and broadcasting is an
/// explicit opt-in that only ever sends already-signed transactions.
///
/// Failover: nodes are tried in order; a transport failure (network
/// error, timeout, non-2xx, malformed JSON) moves to the next node.
/// A JSON-RPC `error` object is a node *answer*, not a transport
/// failure, so it is reported immediately without failover.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import 'constants.dart';
import 'crypto.dart';
import 'models.dart';
import 'operations.dart';
import 'transaction.dart';

/// Thrown for transport-level failures (all nodes unreachable, timeout).
class HiveNetworkException implements Exception {
/// Create with a message and optional cause.
  HiveNetworkException(this.message, {this.cause});
/// Human-readable error detail.
  final String message;
/// The underlying error, if any.
  final Object? cause;
  @override
  String toString() => 'HiveNetworkException: $message';
}

/// Thrown when a node answers with a JSON-RPC error object.
class HiveRpcException implements Exception {
/// Create from a JSON-RPC error object.
  HiveRpcException(this.code, this.message, {this.data});
/// JSON-RPC error code.
  final int code;
/// Human-readable error detail.
  final String message;
/// Extra error data from the node, if any.
  final dynamic data;
  @override
  String toString() => 'HiveRpcException($code): $message';
}

/// Result of a synchronous broadcast.
class HiveBroadcastResult {
/// Create a broadcast result.
  HiveBroadcastResult({
    required this.id,
    required this.blockNum,
    required this.trxNum,
    required this.expired,
  });

/// Parse from the broadcast result JSON.
  factory HiveBroadcastResult.fromJson(Map<String, dynamic> json) {
    return HiveBroadcastResult(
      id: json['id'] as String? ?? '',
      blockNum: (json['block_num'] as num?)?.toInt() ?? 0,
      trxNum: (json['trx_num'] as num?)?.toInt() ?? 0,
      expired: json['expired'] as bool? ?? false,
    );
  }

  /// Transaction id (hex).
  final String id;

  /// Block the transaction was included in.
  final int blockNum;

  /// Index within the block.
  final int trxNum;

  /// Whether the transaction expired before inclusion.
  final bool expired;
}

/// A Hive JSON-RPC client.
///
/// Pass a custom [httpClient] in tests (e.g. a fake returning canned
/// responses); in production the default client is used and should be
/// closed with [close] when done.
class HiveClient {
/// Create a client for [nodes] (tried in order on transport failure).
  HiveClient({
    List<String> nodes = defaultHiveNodes,
    this.timeout = defaultHiveTimeout,
    http.Client? httpClient,
    this.chainIdHex = hiveMainnetChainIdHex,
  })  : nodes = List<String>.unmodifiable(nodes),
        _httpClient = httpClient ?? http.Client(),
        _ownsClient = httpClient == null;

  /// API node URLs, tried in order on transport failure.
  final List<String> nodes;

  /// Per-request timeout.
  final Duration timeout;

  /// Chain id used when signing transactions built via this client.
  final String chainIdHex;

  final http.Client _httpClient;
  final bool _ownsClient;
  var _nextId = 1;

  /// Close the underlying HTTP client (only when this client created it).
  void close() {
    if (_ownsClient) _httpClient.close();
  }

  /// Low-level `call`: `api.method(args)` with failover.
  /// Returns the `result` field, or throws [HiveRpcException] /
  /// [HiveNetworkException].
  Future<dynamic> call(String api, String method, dynamic args) async {
    Object? lastError;
    for (final node in nodes) {
      try {
        return await _callOnce(node, api, method, args);
      } on HiveRpcException {
        rethrow;
      } on Exception catch (e) {
        lastError = e;
        continue;
      }
    }
    throw HiveNetworkException(
      'All ${nodes.length} node(s) failed for $api.$method',
      cause: lastError,
    );
  }

  Future<dynamic> _callOnce(
    String node,
    String api,
    String method,
    dynamic args,
  ) async {
    final id = _nextId++;
    final body = jsonEncode({
      'jsonrpc': '2.0',
      'method': 'call',
      'params': [api, method, args],
      'id': id,
    });
    late http.Response response;
    try {
      response = await _httpClient
          .post(
            Uri.parse(node),
            headers: {'Content-Type': 'application/json'},
            body: body,
          )
          .timeout(timeout);
    } on Exception catch (e) {
      throw HiveNetworkException('Request to $node failed: $e', cause: e);
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HiveNetworkException(
        'Node $node answered HTTP ${response.statusCode}',
      );
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw HiveNetworkException('Node $node returned malformed JSON');
    }
    if (decoded['error'] != null) {
      final error = decoded['error'] as Map<String, dynamic>;
      throw HiveRpcException(
        (error['code'] as num?)?.toInt() ?? -1,
        error['message'] as String? ?? 'Unknown RPC error',
        data: error['data'],
      );
    }
    return decoded['result'];
  }

  // ---------------------------------------------------------------- reads

  /// `condenser_api.get_accounts` — returns the accounts for [names].
  Future<List<HiveAccount>> getAccounts(List<String> names) async {
    final result = await call('condenser_api', 'get_accounts', [names]);
    if (result is! List) {
      throw HiveParseException('get_accounts returned non-list: $result');
    }
    return result
        .map((e) => HiveAccount.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// `condenser_api.get_accounts` for a single account, or `null`.
  Future<HiveAccount?> getAccount(String name) async {
    final accounts = await getAccounts([name]);
    return accounts.isEmpty ? null : accounts.first;
  }

  /// `condenser_api.get_content` — a post or comment.
  Future<HiveContent?> getContent(String author, String permlink) async {
    final result = await call(
      'condenser_api',
      'get_content',
      [author, permlink],
    );
    if (result is! Map<String, dynamic>) {
      throw HiveParseException('get_content returned non-object: $result');
    }
    // Nodes return an empty-ish object (id 0, empty author) for missing
    // content; treat that as "not found" rather than a content.
    if ((result['id'] as num?)?.toInt() == 0 &&
        (result['author'] as String? ?? '').isEmpty) {
      return null;
    }
    return HiveContent.fromJson(result);
  }

  /// `condenser_api.get_dynamic_global_properties`.
  Future<HiveDynamicGlobalProperties> getDynamicGlobalProperties() async {
    final result = await call(
      'condenser_api',
      'get_dynamic_global_properties',
      [],
    );
    if (result is! Map<String, dynamic>) {
      throw HiveParseException(
        'get_dynamic_global_properties returned non-object: $result',
      );
    }
    return HiveDynamicGlobalProperties.fromJson(result);
  }

  /// `condenser_api.get_block_header` — the header of [blockNum].
  Future<HiveBlockHeader> getBlockHeader(int blockNum) async {
    final result = await call(
      'condenser_api',
      'get_block_header',
      [blockNum],
    );
    if (result is! Map<String, dynamic>) {
      throw HiveParseException('get_block_header returned non-object');
    }
    return HiveBlockHeader.fromJson(result);
  }

  /// `account_history_api.get_account_history` — the most recent
  /// [limit] operations for [account] (newest first). `start: -1`
  /// means "start from the latest".
  ///
  /// Live nodes answer `{"history": [[seq, {...}], ...]}` with ops
  /// as `{type: "..._operation", value: {...}}` and amounts as NAI
  /// objects — see [HiveAccountHistoryEntry.fromJson]. A bare list
  /// (the legacy `condenser_api` shape) is accepted as well.
  Future<List<HiveAccountHistoryEntry>> getAccountHistory(
    String account, {
    int limit = 20,
  }) async {
    final result = await call('account_history_api', 'get_account_history', {
      'account': account,
      'start': -1,
      'limit': limit,
    });
    final entries = result is Map<String, dynamic> ? result['history'] : result;
    if (entries is! List) {
      throw HiveParseException(
        'get_account_history returned non-list: $result',
      );
    }
    return entries
        .map((e) => HiveAccountHistoryEntry.fromJson(e as List<dynamic>))
        .toList();
  }

  // ------------------------------------------------------- tx preparation

  /// Fetch the head block and build an unsigned transaction for [ops],
  /// expiring 60 seconds from now. The caller signs it (see
  /// [HiveTransaction.sign]) and broadcasts it.
  Future<HiveTransaction> prepareTransaction(
    List<HiveOperation> operations, {
    Duration expiresIn = const Duration(seconds: 60),
  }) async {
    final props = await getDynamicGlobalProperties();
    return HiveTransaction.refBlockFromHead(
      headBlockNumber: props.headBlockNumber,
      headBlockIdHex: props.headBlockId,
      expiration: DateTime.now().toUtc().add(expiresIn),
      operations: operations,
    );
  }

  /// Build, sign and broadcast [operations] with [key] in one step.
  /// Returns the broadcast result. This is the only method that talks
  /// to the chain with a key — and the key never leaves this device.
  Future<HiveBroadcastResult> broadcastOperations(
    List<HiveOperation> operations,
    HivePrivateKey key,
  ) async {
    final tx = await prepareTransaction(operations);
    return broadcastTransaction(tx.sign(key, chainIdHex: chainIdHex));
  }

  /// `condenser_api.broadcast_transaction_synchronous` — broadcast an
  /// already-signed transaction and wait for inclusion. This is
  /// opt-in: nothing in this package broadcasts on its own.
  Future<HiveBroadcastResult> broadcastTransaction(
    HiveSignedTransaction signed,
  ) async {
    final result = await call(
      'condenser_api',
      'broadcast_transaction_synchronous',
      [signed.toJson()],
    );
    if (result is! Map<String, dynamic>) {
      throw HiveParseException(
        'broadcast_transaction_synchronous returned non-object',
      );
    }
    return HiveBroadcastResult.fromJson(result);
  }
}
