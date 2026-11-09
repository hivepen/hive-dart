/// Authentication helpers: HiveAuth (HAS) and Hive Keychain.
///
/// Two flows, neither of which ever touches a private key:
///
/// **HiveAuth (HAS)** — docs.hiveauth.com. The app opens a WebSocket
/// to `wss://has.hiveauth.com` and exchanges JSON messages with the
/// user's wallet (PKSA, e.g. Hive Keychain mobile):
/// `auth_req` → `auth_wait` → `auth_ack` (or `auth_nack`);
/// `sign_req` → `sign_wait` → `sign_ack` (or `sign_nack`).
/// The `data` fields are AES-encrypted (CryptoJS-compatible, see
/// [has_crypto.dart]) with the `auth_key` shared out-of-band via the
/// auth payload (QR code or `has://auth_req/<base64>` deep link), so
/// the HAS server itself cannot read the payloads. This file builds
/// and parses those messages; it does not manage the WebSocket — the
/// app owns the connection and its lifecycle.
///
/// **Hive Keychain (hive-uri)** — the `hive://` URI scheme
/// (`hive-uri` npm package, implemented by Hive Keychain mobile and
/// Ecency): `hive://sign/op/<base64url(JSON op)>`,
/// `hive://sign/ops/<base64url(JSON op array)>`,
/// `hive://sign/tx/<base64url(JSON tx)>`, with optional `s` (signer)
/// and `cb` (base64url callback URL, `{{id}}`/`{{sig}}` templated)
/// query params. The wallet parses the URI, shows the transaction,
/// signs, broadcasts, and redirects to the callback.
///
/// Reference implementations: Genioo web (`hivepen/hivepen-play`)
/// uses `@aioha/aioha` 1.8.5 + `@aioha/providers` 1.8.2, which wrap
/// Keychain extension, HiveAuth and HiveSigner behind one API, plus
/// `@hiveio/dhive` 1.3.5 for reads/broadcasts. There is no Dart Aioha,
/// so this package implements the underlying HAS wire protocol and
/// the hive-uri scheme directly — same flows, no JS bridge.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'constants.dart';
import 'has_crypto.dart';
import 'operations.dart';
import 'transaction.dart';

/// Base64URL without padding (RFC 4648 §5), as used by `hive-uri`.
String base64UrlNoPad(List<int> bytes) =>
    base64Url.encode(bytes).replaceAll('=', '');

/// Decode base64URL without padding (RFC 4648 §5).
Uint8List base64UrlNoPadDecode(String encoded) {
  final padded = encoded + ('=' * ((4 - encoded.length % 4) % 4));
  return base64Url.decode(padded);
}

/// Thrown when an auth message or URI is malformed.
class HiveAuthException implements Exception {
/// Create with an error message.
  HiveAuthException(this.message);
/// Human-readable error detail.
  final String message;
  @override
  String toString() => 'HiveAuthException: $message';
}

// ---------------------------------------------------------------- HiveAuth

/// App metadata sent in `auth_req_data` (HAS protocol).
class HiveAuthApp {
/// Create app metadata.
  HiveAuthApp({required this.name, this.description = '', this.icon = ''});

/// App display name, shown to the user in the wallet.
  final String name;
/// Short app description.
  final String description;
/// App icon URL (may be empty).
  final String icon;

/// JSON form of the app metadata.
  Map<String, dynamic> toJson() => {
        'name': name,
        'description': description,
        'icon': icon,
      };
}

/// The out-of-band payload shared with the wallet via QR code or the
/// `has://auth_req/<base64>` deep link (HAS "authentication payload").
class HiveAuthPayload {
/// Create a payload.
  HiveAuthPayload({
    required this.account,
    required this.uuid,
    required this.key,
    this.host = hiveAuthDefaultHost,
  });

/// Parse from the JSON payload object.
  factory HiveAuthPayload.fromJson(Map<String, dynamic> json) {
    return HiveAuthPayload(
      account: json['account'] as String,
      uuid: json['uuid'] as String,
      key: json['key'] as String,
      host: json['host'] as String? ?? hiveAuthDefaultHost,
    );
  }

/// Parse a `has://auth_req/...` deep link.
  factory HiveAuthPayload.fromDeepLink(String uri) {
    final parsed = Uri.parse(uri);
    // `has://auth_req/<base64>`: Uri treats `auth_req` as the host.
    if (parsed.scheme != 'has' || parsed.host != 'auth_req') {
      throw HiveAuthException('Not a has://auth_req deep link: $uri');
    }
    final encoded = parsed.pathSegments.join('/');
    final json = jsonDecode(utf8.decode(base64Decode(encoded)));
    return HiveAuthPayload.fromJson(json as Map<String, dynamic>);
  }

/// Hive account name being authenticated.
  final String account;
/// Request identifier received with the `auth_wait` reply.
  final String uuid;
/// App-generated session encryption key (the `auth_key`).
  final String key;
/// HAS server URL, e.g. `wss://has.hiveauth.com`.
  final String host;

/// JSON form of the app metadata.
  Map<String, dynamic> toJson() => {
        'account': account,
        'uuid': uuid,
        'key': key,
        'host': host,
      };

  /// `has://auth_req/<base64(JSON payload)>` — show as QR code on
  /// desktop, or open directly on mobile.
  String toDeepLink() {
    final encoded = base64Encode(utf8.encode(jsonEncode(toJson())));
    return 'has://auth_req/$encoded';
  }
}

/// Builders for the HAS WebSocket messages an app sends.
abstract final class HiveAuth {
  /// `auth_req`: authenticate [account]. [authKey] is the session
  /// encryption key (a UUID the app generates); [app] identifies the
  /// app to the wallet. Returns the message to send over the socket.
  static Map<String, dynamic> authRequest({
    required String account,
    required String authKey,
    required HiveAuthApp app,
    Map<String, dynamic>? challenge,
  }) {
    final data = <String, dynamic>{
      'app': app.toJson(),
      if (challenge != null) 'challenge': challenge,
    };
    return {
      'cmd': 'auth_req',
      'account': account,
      'data': cryptoJsAesEncrypt(jsonEncode(data), authKey),
    };
  }

  /// `sign_req`: ask the wallet to sign [ops] (and broadcast them if
  /// [broadcast] is true). [keyType] is `posting` or `active`.
  static Map<String, dynamic> signRequest({
    required String account,
    required String authKey,
    required List<HiveOperation> ops,
    String keyType = 'posting',
    bool broadcast = true,
  }) {
    final data = {
      'key_type': keyType,
      'ops': ops.map((op) => op.toJson()).toList(),
      'broadcast': broadcast,
    };
    return {
      'cmd': 'sign_req',
      'account': account,
      'data': cryptoJsAesEncrypt(jsonEncode(data), authKey),
    };
  }

  /// Decrypt an `auth_ack`/`sign_ack` payload. `auth_ack` carries the
  /// session `token` and `expire`; `sign_ack` carries either the
  /// broadcast `txID` or the `signed_transaction` (when the app asked
  /// for signing without broadcast). Returns the decoded JSON map.
  static Map<String, dynamic> decryptAck(
    Map<String, dynamic> message,
    String authKey,
  ) {
    final data = message['data'];
    if (data is! String) {
      throw HiveAuthException('Ack message has no encrypted data: $message');
    }
    final plain = cryptoJsAesDecrypt(data, authKey);
    final decoded = jsonDecode(plain);
    if (decoded is! Map<String, dynamic>) {
      throw HiveAuthException('Ack payload is not a JSON object: $plain');
    }
    return decoded;
  }

  /// Parse a `*_wait` message (`auth_wait` / `sign_wait`): the `uuid`
  /// identifies the pending request and `expire` is its unix deadline.
  static ({String uuid, int expire}) parseWait(Map<String, dynamic> message) {
    final uuid = message['uuid'];
    final expire = message['expire'];
    if (uuid is! String || expire is! num) {
      throw HiveAuthException('Malformed wait message: $message');
    }
    return (uuid: uuid, expire: expire.toInt());
  }
}

// ------------------------------------------------------------ Hive Keychain

/// Builders/parsers for the `hive://` URI scheme (hive-uri spec).
abstract final class HiveKeychain {
  /// `hive://sign/op/<base64url(JSON op)>` — ask the wallet to build
  /// a transaction around a single operation, sign and broadcast it.
  /// [signer] pre-fills the signing account; [callback] is the URL
  /// the wallet redirects to after signing (supports `{{id}}` and
  /// `{{sig}}` templates).
  static String signOpUri(
    HiveOperation op, {
    String? signer,
    String? callback,
  }) {
    return _signUri('op', jsonEncode(op.toJson()), signer, callback);
  }

  /// `hive://sign/ops/<base64url(JSON op array)>` — same, for several
  /// operations in one transaction.
  static String signOpsUri(
    List<HiveOperation> ops, {
    String? signer,
    String? callback,
  }) {
    return _signUri(
      'ops',
      jsonEncode(ops.map((op) => op.toJson()).toList()),
      signer,
      callback,
    );
  }

  /// `hive://sign/tx/<base64url(JSON tx)>` — sign an already-built
  /// (unsigned) transaction.
  static String signTxUri(
    HiveTransaction transaction, {
    String? signer,
    String? callback,
  }) {
    return _signUri(
      'tx',
      jsonEncode(transaction.toJson()),
      signer,
      callback,
    );
  }

  static String _signUri(
    String action,
    String jsonPayload,
    String? signer,
    String? callback,
  ) {
    final encoded = base64UrlNoPad(utf8.encode(jsonPayload));
    final params = <String, String>{};
    if (signer != null) params['s'] = signer;
    if (callback != null) {
      params['cb'] = base64UrlNoPad(utf8.encode(callback));
    }
    final query = params.entries
        .map((e) =>
            '${Uri.encodeQueryComponent(e.key)}='
            '${Uri.encodeQueryComponent(e.value)}')
        .join('&');
    return 'hive://sign/$action/$encoded${query.isEmpty ? '' : '?$query'}';
  }

  /// Decode a `hive://sign/...` URI back into its action, JSON
  /// payload and params. (Wallet-side helper, and useful in tests.)
  static ({
    String action,
    dynamic payload,
    String? signer,
    String? callback,
  }) parseSignUri(String uri) {
    final parsed = Uri.parse(uri);
    // `hive://sign/<action>/<base64>`: Uri treats `sign` as the host.
    if (parsed.scheme != 'hive' ||
        parsed.host != 'sign' ||
        parsed.pathSegments.isEmpty) {
      throw HiveAuthException('Not a hive://sign URI: $uri');
    }
    final action = parsed.pathSegments.first;
    final encoded = parsed.pathSegments.sublist(1).join('/');
    final payload = jsonDecode(utf8.decode(base64UrlNoPadDecode(encoded)));
    final callback = parsed.queryParameters['cb'];
    return (
      action: action,
      payload: payload,
      signer: parsed.queryParameters['s'],
      callback: callback == null
          ? null
          : utf8.decode(base64UrlNoPadDecode(callback)),
    );
  }
}
