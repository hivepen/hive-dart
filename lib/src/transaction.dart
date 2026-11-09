/// Hive transactions: building, serialisation, digest and signing.
///
/// Mirrors dhive (`src/chain/transaction.ts`, `src/crypto.ts`):
/// a transaction is `ref_block_num:uint16`, `ref_block_prefix:uint32`,
/// `expiration:uint32`, `operations`, `extensions`; its digest is
/// `sha256(chain_id || serialized_transaction)`; signatures are hex
/// strings of the 65-byte `[recovery + 31, r, s]` form.
///
/// Reference-block derivation (the standard dhive path, via
/// `condenser_api.get_dynamic_global_properties`, which returns
/// `head_block_number` and `head_block_id`):
/// * `ref_block_num = head_block_number & 0xffff`
/// * `ref_block_prefix = little-endian uint32 of head_block_id bytes
///   [4..8]`.
///
/// Note: `condenser_api.get_block_header` alone cannot yield
/// `ref_block_prefix` — the header carries no block id. The client
/// therefore derives reference-block fields from the dynamic global
/// properties (see [HiveTransaction.refBlockFromHead]).
library;

import 'dart:typed_data';

import 'constants.dart';
import 'crypto.dart';
import 'operations.dart';
import 'serializer.dart';
import 'utils.dart';

/// An unsigned Hive transaction.
class HiveTransaction {
/// Create an unsigned transaction.
  HiveTransaction({
    required this.refBlockNum,
    required this.refBlockPrefix,
    required this.expiration,
    required this.operations,
    this.extensions = const <String>[],
  });

  /// Derive reference-block fields from a head block (see module doc).
  factory HiveTransaction.refBlockFromHead({
    required int headBlockNumber,
    required String headBlockIdHex,
    required DateTime expiration,
    required List<HiveOperation> operations,
    List<String> extensions = const <String>[],
  }) {
    final blockId = hexDecode(headBlockIdHex);
    if (blockId.length != 32) {
      throw HiveSerializationException(
        'Invalid block id length: ${blockId.length}, expected 32',
      );
    }
    // Bytes [4..8] of the block id, little-endian uint32.
    final prefix = blockId[4] |
        (blockId[5] << 8) |
        (blockId[6] << 16) |
        (blockId[7] << 24);
    return HiveTransaction(
      refBlockNum: headBlockNumber & 0xffff,
      refBlockPrefix: prefix,
      expiration: expiration,
      operations: operations,
      extensions: extensions,
    );
  }

  /// `head_block_number & 0xffff`.
  final int refBlockNum;

  /// Little-endian uint32 of the head block id bytes `[4..8]`.
  final int refBlockPrefix;

  /// Expiration, serialised as unix seconds (UTC). Nodes reject
  /// transactions expiring more than ~5 minutes in the future and
  /// anything already expired; callers should use now + 60s.
  final DateTime expiration;

  /// Operations, in order.
  final List<HiveOperation> operations;

  /// Extension strings (empty in practice for v1).
  final List<String> extensions;

  /// Binary serialisation (dhive `Types.Transaction`).
  Uint8List serialize() {
    final writer = TxWriter();
    writer.writeUint16(refBlockNum);
    writer.writeUint32(refBlockPrefix);
    writer.writeUint32(expiration.toUtc().millisecondsSinceEpoch ~/ 1000);
    writer.writeArray<HiveOperation>(operations, (op) => op.serialize(writer));
    writer.writeArray<String>(extensions, writer.writeString);
    return writer.toBytes();
  }

  /// `sha256(chain_id || serialize())` (dhive `transactionDigest`).
  Uint8List digest({String chainIdHex = hiveMainnetChainIdHex}) {
    return sha256(
      concatBytes([hexDecode(chainIdHex), serialize()]),
    );
  }

  /// Sign with [key] and return the signed transaction.
  HiveSignedTransaction sign(
    HivePrivateKey key, {
    String chainIdHex = hiveMainnetChainIdHex,
  }) {
    final signature = key.sign(digest(chainIdHex: chainIdHex));
    return HiveSignedTransaction(this, [signature]);
  }

  /// Sign already-serialised transaction bytes with [key].
  /// Used by tests to cross-check dhive's vectors byte-for-byte
  /// without depending on the operation serializers.
  static HiveSignature signSerialized(
    Uint8List serialized,
    HivePrivateKey key, {
    String chainIdHex = hiveMainnetChainIdHex,
  }) {
    final digest = sha256(concatBytes([hexDecode(chainIdHex), serialized]));
    return key.sign(digest);
  }

  /// JSON form without signatures (as accepted by
  /// `condenser_api.broadcast_transaction` once signed).
  Map<String, dynamic> toJson() => {
        'ref_block_num': refBlockNum,
        'ref_block_prefix': refBlockPrefix,
        'expiration': _formatExpiration(expiration),
        'operations': operations.map((op) => op.toJson()).toList(),
        'extensions': extensions,
      };

  /// Hive's `YYYY-MM-DDTHH:MM:SS` expiration format (no timezone suffix).
  static String _formatExpiration(DateTime expiration) {
    final utc = expiration.toUtc();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${utc.year}-${two(utc.month)}-${two(utc.day)}T'
        '${two(utc.hour)}:${two(utc.minute)}:${two(utc.second)}';
  }
}

/// A signed Hive transaction.
class HiveSignedTransaction {
/// Create a signed transaction from its parts.
  HiveSignedTransaction(this.transaction, this.signatures);

/// The unsigned transaction.
  final HiveTransaction transaction;

  /// Hex-encoded 65-byte signatures.
  final List<HiveSignature> signatures;

  /// Transaction id: `sha256(serialize())` as hex (not the digest —
  /// the id hashes the serialised transaction alone, without chain id).
  String get id => hexEncode(sha256(transaction.serialize()));

  /// JSON form for `condenser_api.broadcast_transaction` /
  /// `broadcast_transaction_synchronous`.
  Map<String, dynamic> toJson() {
    final json = transaction.toJson();
    json['signatures'] = signatures.map((s) => s.toHex()).toList();
    return json;
  }
}
