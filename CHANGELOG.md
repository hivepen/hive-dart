## 0.2.0

- First public release as `hiveblockchain_dart` (previously `hive_dart`;
  renamed because `hive_dart` is already taken on pub.dev).
- JSON-RPC reads with node failover: accounts, content, account history,
  dynamic global properties, block headers.
- Offline transaction building and signing for `custom_json`, `comment`,
  and `comment_options` (including beneficiaries), verified byte-for-byte
  against dhive 1.3.2.
- HiveAuth (HAS) message building/decoding and Hive Keychain `hive://`
  deep-link helpers.
