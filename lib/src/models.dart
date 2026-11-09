/// Plain data models for the Hive JSON-RPC responses used by v1.
///
/// Only the fields the apps need are modelled; unknown fields are
/// ignored, so node responses stay forward-compatible.
library;

/// Thrown when a node response cannot be parsed.
class HiveParseException implements Exception {
/// Create with an error message.
  HiveParseException(this.message);
/// Human-readable error detail.
  final String message;
  @override
  String toString() => 'HiveParseException: $message';
}

/// A Hive account (`condenser_api.get_accounts`).
class HiveAccount {
/// Create an account snapshot.
  HiveAccount({
    required this.id,
    required this.name,
    required this.created,
    required this.reputation,
    required this.balance,
    required this.hbdBalance,
    required this.vestingShares,
    required this.posting,
    required this.jsonMetadata,
    this.postingJsonMetadata = '',
    required this.postCount,
  });

/// Parse from a node JSON object.
  factory HiveAccount.fromJson(Map<String, dynamic> json) {
    return HiveAccount(
      id: (json['id'] as num?)?.toInt() ?? 0,
      name: json['name'] as String? ?? '',
      created: json['created'] as String? ?? '',
      reputation: (json['reputation'] as num?)?.toInt() ?? 0,
      balance: json['balance'] as String? ?? '0.000 HIVE',
      hbdBalance: json['hbd_balance'] as String? ?? '0.000 HBD',
      vestingShares: json['vesting_shares'] as String? ?? '0.000000 VESTS',
      posting: HiveAuthority.fromJson(
        json['posting'] as Map<String, dynamic>? ?? const {},
      ),
      jsonMetadata: json['json_metadata'] as String? ?? '',
      postingJsonMetadata: json['posting_json_metadata'] as String? ?? '',
      postCount: (json['post_count'] as num?)?.toInt() ?? 0,
    );
  }

/// Numeric id.
  final int id;
/// Account name (without `@`).
  final String name;
/// Creation time (ISO-8601 string, as returned by the node).
  final String created;
/// Reputation score (raw, unscaled).
  final int reputation;
/// Liquid HIVE balance, e.g. `10.500 HIVE`.
  final String balance;
/// Liquid HBD balance, e.g. `2.250 HBD`.
  final String hbdBalance;
/// Vesting shares, e.g. `1000.000000 VESTS`.
  final String vestingShares;
/// Posting authority (keys allowed to sign posting ops).
  final HiveAuthority posting;
/// Raw `json_metadata` string.
  final String jsonMetadata;

/// Raw `posting_json_metadata` string. This is where the profile
/// block (name, about, avatar) lives for most accounts — `json_metadata`
/// is empty for them (verified live for @carlosepc: `json_metadata`
/// is `''`, the profile is in `posting_json_metadata`).
  final String postingJsonMetadata;
/// Number of posts/comments by the account.
  final int postCount;

  /// The posting public keys, if any.
  List<String> get postingKeys => posting.keyAuths.keys.toList();
}

/// An authority block (`weight_threshold`, `account_auths`, `key_auths`).
class HiveAuthority {
/// Create an authority.
  HiveAuthority({
    required this.weightThreshold,
    required this.accountAuths,
    required this.keyAuths,
  });

/// Parse from a node JSON object.
  factory HiveAuthority.fromJson(Map<String, dynamic> json) {
    Map<String, int> parseAuths(dynamic value) {
      final out = <String, int>{};
      if (value is List) {
        for (final entry in value) {
          if (entry is List && entry.length == 2) {
            out[entry[0] as String] = (entry[1] as num).toInt();
          }
        }
      }
      return out;
    }

    return HiveAuthority(
      weightThreshold: (json['weight_threshold'] as num?)?.toInt() ?? 0,
      accountAuths: parseAuths(json['account_auths']),
      keyAuths: parseAuths(json['key_auths']),
    );
  }

/// Weight required for the authority to act.
  final int weightThreshold;
/// Account authorisations: name → weight.
  final Map<String, int> accountAuths;
/// Key authorisations: public key → weight.
  final Map<String, int> keyAuths;
}

/// A post or comment (`condenser_api.get_content`).
class HiveContent {
/// Create a content object.
  HiveContent({
    required this.id,
    required this.author,
    required this.permlink,
    required this.parentAuthor,
    required this.parentPermlink,
    required this.title,
    required this.body,
    required this.jsonMetadata,
    required this.created,
    required this.children,
    required this.netVotes,
    required this.pendingPayoutValue,
  });

/// Parse from a node JSON object.
  factory HiveContent.fromJson(Map<String, dynamic> json) {
    return HiveContent(
      id: (json['id'] as num?)?.toInt() ?? 0,
      author: json['author'] as String? ?? '',
      permlink: json['permlink'] as String? ?? '',
      parentAuthor: json['parent_author'] as String? ?? '',
      parentPermlink: json['parent_permlink'] as String? ?? '',
      title: json['title'] as String? ?? '',
      body: json['body'] as String? ?? '',
      jsonMetadata: json['json_metadata'] as String? ?? '',
      created: json['created'] as String? ?? '',
      children: (json['children'] as num?)?.toInt() ?? 0,
      netVotes: (json['net_votes'] as num?)?.toInt() ?? 0,
      pendingPayoutValue:
          json['pending_payout_value'] as String? ?? '0.000 HBD',
    );
  }

/// Numeric id.
  final int id;
/// Author account name.
  final String author;
/// Permlink (URL slug) of the content.
  final String permlink;
/// Parent author (`""` for a top-level post).
  final String parentAuthor;
/// Parent permlink (category tag for a top-level post).
  final String parentPermlink;
/// Post title (`""` for comments).
  final String title;
/// Post/comment body (markdown).
  final String body;
/// Raw `json_metadata` string.
  final String jsonMetadata;
/// Creation time (ISO-8601 string, as returned by the node).
  final String created;
/// Number of direct replies.
  final int children;
/// Net vote count.
  final int netVotes;
/// Pending payout, e.g. `1.250 HBD`.
  final String pendingPayoutValue;
}

/// Dynamic global properties
/// (`condenser_api.get_dynamic_global_properties`).
class HiveDynamicGlobalProperties {
/// Create dynamic global properties.
  HiveDynamicGlobalProperties({
    required this.headBlockNumber,
    required this.headBlockId,
    required this.time,
    required this.currentWitness,
    required this.totalVestingFundHive,
    required this.totalVestingShares,
  });

/// Parse from a node JSON object.
  factory HiveDynamicGlobalProperties.fromJson(Map<String, dynamic> json) {
    return HiveDynamicGlobalProperties(
      headBlockNumber: (json['head_block_number'] as num?)?.toInt() ?? 0,
      headBlockId: json['head_block_id'] as String? ?? '',
      time: json['time'] as String? ?? '',
      currentWitness: json['current_witness'] as String? ?? '',
      totalVestingFundHive:
          json['total_vesting_fund_hive'] as String? ?? '0.000 HIVE',
      totalVestingShares:
          json['total_vesting_shares'] as String? ?? '0.000000 VESTS',
    );
  }

/// Head block number.
  final int headBlockNumber;
/// Head block id (32-byte hex).
  final String headBlockId;
/// Head block time (ISO-8601 string).
  final String time;
/// Current witness (block producer).
  final String currentWitness;
/// Total vesting fund, e.g. `100000.000 HIVE`.
  final String totalVestingFundHive;
/// Total vesting shares, e.g. `200000.000000 VESTS`.
  final String totalVestingShares;
}

/// A block header (`condenser_api.get_block_header`).
class HiveBlockHeader {
/// Create a block header.
  HiveBlockHeader({
    required this.previous,
    required this.timestamp,
    required this.witness,
    required this.transactionMerkleRoot,
  });

/// Parse from a node JSON object.
  factory HiveBlockHeader.fromJson(Map<String, dynamic> json) {
    return HiveBlockHeader(
      previous: json['previous'] as String? ?? '',
      timestamp: json['timestamp'] as String? ?? '',
      witness: json['witness'] as String? ?? '',
      transactionMerkleRoot:
          json['transaction_merkle_root'] as String? ?? '',
    );
  }

/// Previous block id (hex).
  final String previous;
/// Timestamp (ISO-8601 string).
  final String timestamp;
/// Witness that produced the block.
  final String witness;
/// Transaction merkle root (hex).
  final String transactionMerkleRoot;
}

/// NAI (numeric asset identifier) → symbol, per the Hive protocol
/// (`asset_symbol_type`: 21 = HIVE, 13 = HBD, 37 = VESTS).
/// Verified live 2026-11-05 against api.hive.blog: in a
/// `claim_reward_balance` op the fields `reward_hbd` / `reward_hive` /
/// `reward_vests` carry nais `@@000000013` / `@@000000021` /
/// `@@000000037`; a `limit_order_create` sells `@@000000021` (HIVE)
/// for `@@000000013` (HBD); `fill_vesting_withdraw` withdraws
/// `@@000000037` (VESTS).
const Map<String, String> hiveNaiSymbols = {
  '@@000000021': 'HIVE',
  '@@000000013': 'HBD',
  '@@000000037': 'VESTS',
};

/// Whether [json] is exactly one NAI amount object
/// (`{nai, amount, precision}`) — the shape the `account_history_api`
/// uses for money instead of the legacy `"1.234 HIVE"` string.
bool _isNaiAmount(Map<String, dynamic> json) =>
    json.length == 3 &&
    json.containsKey('nai') &&
    json.containsKey('amount') &&
    json.containsKey('precision');

/// Format one NAI amount object as a legacy money string
/// (`"0.002 HIVE"`). Returns `null` when [json] is not a NAI amount
/// object, its NAI is unknown, or its amount is not an integer —
///
/// callers keep the raw object in that case, so no data is lost.
String? formatNaiAmount(Map<String, dynamic> json) {
  if (!_isNaiAmount(json)) return null;
  final symbol = hiveNaiSymbols[json['nai'] as String?];
  if (symbol == null) return null;
  final precision = (json['precision'] as num?)?.toInt();
  if (precision == null || precision < 0) return null;
  final units = BigInt.tryParse(json['amount'].toString());
  if (units == null) return null;
  final sign = units.isNegative ? '-' : '';
  final abs = units.abs();
  final divisor = BigInt.from(10).pow(precision);
  final whole = abs ~/ divisor;
  if (precision == 0) return '$sign$whole $symbol';
  final frac = (abs % divisor).toString().padLeft(precision, '0');
  return '$sign$whole.$frac $symbol';
}

/// Recursively convert NAI amount objects in an op value to legacy
/// money strings, so modern-shape entries read exactly like legacy
/// ones. Unknown NAIs and everything else pass through untouched.
dynamic normalizeOpValue(dynamic value) {
  if (value is Map<String, dynamic>) {
    if (_isNaiAmount(value)) return formatNaiAmount(value) ?? value;
    return value.map((key, v) => MapEntry(key, normalizeOpValue(v)));
  }
  if (value is List) return value.map(normalizeOpValue).toList();
  return value;
}

/// Parse one history `op` into the legacy `[name, fields]` tuple.
/// Accepts both shapes:
///
/// * legacy: `["transfer", {...}]` (as `condenser_api` returns);
/// * modern (`account_history_api`): `{"type": "transfer_operation",
///   "value": {...}}` — the `_operation` suffix is stripped and NAI
///   amounts inside the value are normalised to legacy money strings
///   by [normalizeOpValue].
List<dynamic> parseHistoryOp(dynamic op) {
  if (op is List &&
      op.length == 2 &&
      op[0] is String &&
      op[1] is Map<String, dynamic>) {
    return [op[0] as String, normalizeOpValue(op[1])];
  }
  if (op is Map<String, dynamic>) {
    final type = op['type'] as String?;
    final value = op['value'];
    if (type != null && value is Map<String, dynamic>) {
      const suffix = '_operation';
      final name = type.endsWith(suffix)
          ? type.substring(0, type.length - suffix.length)
          : type;
      return [name, normalizeOpValue(value)];
    }
  }
  throw HiveParseException('Malformed account history op: $op');
}

/// One account-history entry
/// (`account_history_api.get_account_history`).
class HiveAccountHistoryEntry {
/// Create an account-history entry.
  HiveAccountHistoryEntry({
    required this.sequence,
    required this.block,
    required this.timestamp,
    required this.op,
    required this.trxId,
  });

  /// Parse one entry `[sequence, {block, timestamp, op, trx_id}]`.
  /// The `op` accepts both the legacy tuple shape and the modern
  /// `{type, value}` shape — see [parseHistoryOp].
  factory HiveAccountHistoryEntry.fromJson(List<dynamic> entry) {
    if (entry.length < 2 || entry[1] is! Map<String, dynamic>) {
      throw HiveParseException('Malformed account history entry: $entry');
    }
    final data = entry[1] as Map<String, dynamic>;
    return HiveAccountHistoryEntry(
      sequence: (entry[0] as num).toInt(),
      block: (data['block'] as num?)?.toInt() ?? 0,
      timestamp: data['timestamp'] as String? ?? '',
      op: parseHistoryOp(data['op']),
      trxId: data['trx_id'] as String? ?? '',
    );
  }

/// Account-history sequence number.
  final int sequence;
/// Block number containing the operation.
  final int block;
/// Timestamp (ISO-8601 string).
  final String timestamp;

  /// `[name, {...fields}]`, same shape as [HiveOperation.toJson].
  final List<dynamic> op;
/// Transaction id (hex).
  final String trxId;
}
