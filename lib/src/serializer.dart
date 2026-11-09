/// Hive binary serialization, mirroring dhive `src/chain/serializer.ts`.
///
/// Wire rules (Graphene/BitShares-derived, as used by Hive):
/// * integers are little-endian (`uint16`/`uint32`/`uint64`);
/// * strings are a LEB128 varint byte-length followed by UTF-8 bytes
///   (`ByteBuffer.writeVString`);
/// * arrays are a varint count followed by the items;
/// * an operation is a varint operation id followed by its fields in
///   declaration order;
/// * a transaction is `ref_block_num:uint16`, `ref_block_prefix:uint32`,
///   `expiration:uint32` (unix seconds), `operations:array`,
///   `extensions:array<string>` (empty in practice).
library;

import 'dart:convert';
import 'dart:typed_data';

/// Thrown when a value cannot be serialised.
class HiveSerializationException implements Exception {
/// Create with an error message.
  HiveSerializationException(this.message);
/// Human-readable error detail.
  final String message;
  @override
  String toString() => 'HiveSerializationException: $message';
}

/// Little-endian byte writer with varint support.
class TxWriter {
  final _buf = BytesBuilder();

/// The bytes written so far.
  Uint8List toBytes() => _buf.toBytes();

/// Write one byte.
  void writeUint8(int value) => _buf.add([value & 0xff]);

/// Write a little-endian uint16.
  void writeUint16(int value) {
    _buf.add([value & 0xff, (value >> 8) & 0xff]);
  }

/// Write a little-endian uint32.
  void writeUint32(int value) {
    _buf.add([
      value & 0xff,
      (value >> 8) & 0xff,
      (value >> 16) & 0xff,
      (value >> 24) & 0xff,
    ]);
  }

/// Write a little-endian uint64.
  void writeUint64(BigInt value) {
    final bytes = Uint8List(8);
    var v = value;
    for (var i = 0; i < 8; i++) {
      bytes[i] = (v & BigInt.from(0xff)).toInt();
      v >>= 8;
    }
    _buf.add(bytes);
  }

  /// Unsigned LEB128 varint (as `ByteBuffer.writeVarint32`).
  void writeVarint(int value) {
    if (value < 0) {
      throw HiveSerializationException('Negative varint: $value');
    }
    var v = value;
    do {
      var byte = v & 0x7f;
      v >>= 7;
      if (v != 0) byte |= 0x80;
      _buf.add([byte]);
    } while (v != 0);
  }

  /// Varint length + UTF-8 bytes.
  void writeString(String value) {
    final bytes = utf8.encode(value);
    writeVarint(bytes.length);
    _buf.add(bytes);
  }

/// Write a signed little-endian int64 (two's complement).
  void writeInt64(BigInt value) {
    final bytes = Uint8List(8);
    var v = value;
    for (var i = 0; i < 8; i++) {
      bytes[i] = (v & BigInt.from(0xff)).toInt();
      v >>= 8;
    }
    _buf.add(bytes);
  }

  /// Write one byte: `1` for true, `0` for false.
  void writeBool(bool value) => _buf.add([value ? 1 : 0]);

  /// Write an asset (`"1000000.000 HBD"`): int64 amount scaled by
  /// 10^precision, uint8 precision, 7-byte symbol zero-padded
  /// (dhive `AssetSerializer`). The amount is parsed exactly from
  /// the decimal string — no float rounding. Like dhive, the symbol
  /// is mapped to its legacy Steem name on the wire (`HIVE` →
  /// `STEEM`, `HBD` → `SBD`); the JSON form keeps the Hive name.
  void writeAsset(String value) {
    final parts = value.split(' ');
    if (parts.length != 2) {
      throw HiveSerializationException('Invalid asset: $value');
    }
    final amountPart = parts[0];
    final symbol = switch (parts[1]) {
      'HIVE' => 'STEEM',
      'HBD' => 'SBD',
      final other => other,
    };
    if (symbol.isEmpty ||
        symbol.length > 7 ||
        symbol.codeUnits.any((c) => c >= 128)) {
      throw HiveSerializationException('Invalid asset symbol: $symbol');
    }
    final dot = amountPart.indexOf('.');
    final precision = dot == -1 ? 0 : amountPart.length - dot - 1;
    final digits = amountPart.replaceAll('.', '');
    BigInt scaled;
    try {
      scaled = BigInt.parse(digits);
    } on FormatException {
      throw HiveSerializationException('Invalid asset amount: $value');
    }
    writeInt64(scaled);
    writeUint8(precision);
    final symbolBytes = Uint8List(7);
    final encoded = utf8.encode(symbol);
    symbolBytes.setRange(0, encoded.length, encoded);
    _buf.add(symbolBytes);
  }

/// Write raw bytes without a length prefix.
  void writeBytes(Uint8List bytes) => _buf.add(bytes);

  /// `array<T>`: varint count, then each item via [writeItem].
  void writeArray<T>(List<T> items, void Function(T item) writeItem) {
    writeVarint(items.length);
    for (final item in items) {
      writeItem(item);
    }
  }
}

/// Operation ids used by this package (dhive `src/chain/operation.ts`).
abstract final class HiveOperationId {
/// `comment` operation id.
  static const int comment = 1;
/// `custom_json` operation id.
  static const int customJson = 18;

/// `comment_options` operation id.
  static const int commentOptions = 19;
}
