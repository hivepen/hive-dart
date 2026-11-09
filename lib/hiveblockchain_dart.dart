/// `hiveblockchain_dart` — pure-Dart client for the Hive blockchain.
///
/// v1 scope: JSON-RPC reads over HTTPS, offline transaction building
/// and signing (`custom_json`, `comment`, `comment_options`), and
/// HiveAuth / Hive Keychain auth helpers. No Flutter dependency; no
/// private key ever leaves the caller.
///
/// See `README.md` for usage, scope and security notes.
library;

export 'src/auth.dart';
export 'src/client.dart';
export 'src/constants.dart';
export 'src/crypto.dart';
export 'src/has_crypto.dart';
export 'src/models.dart';
export 'src/operations.dart';
export 'src/serializer.dart' show HiveSerializationException, TxWriter;
export 'src/transaction.dart';
export 'src/utils.dart'
    show
        hexEncode,
        hexDecode,
        base58Encode,
        base58Decode,
        sha256,
        sha512,
        ripemd160;
