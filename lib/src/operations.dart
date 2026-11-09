/// Hive operations supported by this package (v1 scope).
///
/// Field order follows dhive `src/chain/serializer.ts` exactly:
/// * `comment` (id 1): parent_author, parent_permlink, author, permlink,
///   title, body, json_metadata.
/// * `custom_json` (id 18): required_auths, required_posting_auths, id,
///   json.
/// * `comment_options` (id 19): author, permlink, max_accepted_payout,
///   percent_hbd, allow_votes, allow_curation_rewards, extensions
///   (each extension is a static variant; variant 0 is
///   `{beneficiaries: [{account, weight}]}`).
///
/// The JSON form (`toJson`) is the `[name, {...fields}]` pair used by
/// the `condenser_api.broadcast_transaction` RPC and by the HiveAuth
/// `sign_req` payloads. Assets in the JSON form are strings
/// (`"1000000.000 HBD"`), as dhive emits them.
library;

import 'serializer.dart';

/// One beneficiary route in a `comment_options` op: [account]
/// receives [weight] / 10000 of the post's payout (e.g. weight 1000
/// = 10%).
class HiveBeneficiary {
  /// Create a beneficiary route.
  const HiveBeneficiary(this.account, this.weight);

  /// Account receiving the share.
  final String account;

  /// Share in hundredths of a percent (10000 = 100%).
  final int weight;

  /// JSON form: `{'account': ..., 'weight': ...}`.
  Map<String, dynamic> toJson() => {'account': account, 'weight': weight};
}

/// A single Hive operation: `[name, data]`, e.g.
/// `['custom_json', {'required_auths': [], ...}]`.
class HiveOperation {
  const HiveOperation._(this.name, this.id, this.data);

  /// `custom_json` (id 18): a posting-authority JSON payload.
  ///
  /// [requiredPostingAuths] lists the accounts whose posting key must
  /// sign (usually just the acting account); [requiredAuths] is the
  /// active-authority list (usually empty for app actions). [id] is the
  /// app-defined identifier (e.g. `genioo_achievement`), [json] the
  /// JSON-encoded payload string.
  factory HiveOperation.customJson({
    required List<String> requiredAuths,
    required List<String> requiredPostingAuths,
    required String id,
    required String json,
  }) {
    return HiveOperation._('custom_json', HiveOperationId.customJson, {
      'required_auths': List<String>.unmodifiable(requiredAuths),
      'required_posting_auths': List<String>.unmodifiable(
        requiredPostingAuths,
      ),
      'id': id,
      'json': json,
    });
  }

  /// `comment` (id 1): create a post or a reply.
  ///
  /// For a top-level post, [parentAuthor] is `''` and [parentPermlink]
  /// is the community/category tag (e.g. `hive-123456` or `spanish`).
  /// For a reply, they are the parent post's author/permlink.
  factory HiveOperation.comment({
    required String parentAuthor,
    required String parentPermlink,
    required String author,
    required String permlink,
    required String title,
    required String body,
    required String jsonMetadata,
  }) {
    return HiveOperation._('comment', HiveOperationId.comment, {
      'parent_author': parentAuthor,
      'parent_permlink': parentPermlink,
      'author': author,
      'permlink': permlink,
      'title': title,
      'body': body,
      'json_metadata': jsonMetadata,
    });
  }

  /// `comment_options` (id 19): payout options for a post.
  ///
  /// [maxAcceptedPayout] caps the post's payout (default
  /// `"1000000.000 HBD"`, the usual "no cap" value);
  /// [percentHbd] is the HBD share of the payout in hundredths of a
  /// percent (10000 = 100% HBD, the default); [allowVotes] and
  /// [allowCurationRewards] default to true. [beneficiaries] are the
  /// accounts sharing the payout (weight 1000 = 10%); with no
  /// beneficiaries the op carries empty `extensions`.
  factory HiveOperation.commentOptions({
    required String author,
    required String permlink,
    String maxAcceptedPayout = '1000000.000 HBD',
    int percentHbd = 10000,
    bool allowVotes = true,
    bool allowCurationRewards = true,
    List<HiveBeneficiary> beneficiaries = const [],
  }) {
    return HiveOperation._(
      'comment_options',
      HiveOperationId.commentOptions,
      {
        'author': author,
        'permlink': permlink,
        'max_accepted_payout': maxAcceptedPayout,
        'percent_hbd': percentHbd,
        'allow_votes': allowVotes,
        'allow_curation_rewards': allowCurationRewards,
        'extensions': beneficiaries.isEmpty
            ? const <dynamic>[]
            : [
                [
                  0,
                  {
                    'beneficiaries':
                        beneficiaries.map((b) => b.toJson()).toList(),
                  },
                ],
              ],
      },
    );
  }

  /// Operation name, e.g. `custom_json`.
  final String name;

  /// Numeric operation id (varint-prefixed in the binary form).
  final int id;

  /// Field values in declaration order.
  final Map<String, dynamic> data;

  /// JSON-RPC form: `['custom_json', {...}]`.
  List<dynamic> toJson() => [name, data];

  /// Binary form: varint id + fields in declaration order.
  void serialize(TxWriter writer) {
    writer.writeVarint(id);
    switch (name) {
      case 'custom_json':
        writer.writeArray<String>(
          (data['required_auths'] as List<String>),
          writer.writeString,
        );
        writer.writeArray<String>(
          (data['required_posting_auths'] as List<String>),
          writer.writeString,
        );
        writer.writeString(data['id'] as String);
        writer.writeString(data['json'] as String);
      case 'comment':
        writer.writeString(data['parent_author'] as String);
        writer.writeString(data['parent_permlink'] as String);
        writer.writeString(data['author'] as String);
        writer.writeString(data['permlink'] as String);
        writer.writeString(data['title'] as String);
        writer.writeString(data['body'] as String);
        writer.writeString(data['json_metadata'] as String);
      case 'comment_options':
        writer.writeString(data['author'] as String);
        writer.writeString(data['permlink'] as String);
        writer.writeAsset(data['max_accepted_payout'] as String);
        writer.writeUint16(data['percent_hbd'] as int);
        writer.writeBool(data['allow_votes'] as bool);
        writer.writeBool(data['allow_curation_rewards'] as bool);
        final extensions = data['extensions'] as List<dynamic>;
        writer.writeVarint(extensions.length);
        for (final extension in extensions) {
          final pair = extension as List<dynamic>;
          final variantId = pair[0] as int;
          if (variantId != 0) {
            throw HiveSerializationException(
              'Unknown comment_options extension variant: $variantId',
            );
          }
          writer.writeVarint(variantId);
          final value = pair[1] as Map<String, dynamic>;
          final beneficiaries = value['beneficiaries'] as List<dynamic>;
          writer.writeArray<Map<String, dynamic>>(
            beneficiaries.cast<Map<String, dynamic>>(),
            (beneficiary) {
              writer.writeString(beneficiary['account'] as String);
              writer.writeUint16(beneficiary['weight'] as int);
            },
          );
        }
      default:
        throw HiveSerializationException('No serializer for $name');
    }
  }
}
