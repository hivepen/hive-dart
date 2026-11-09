/// Hive mainnet constants, matching dhive
/// (`@hiveio/dhive` 1.3.x, `src/client.ts`).
library;

/// Hive mainnet chain id (dhive `DEFAULT_CHAIN_ID`).
///
/// Source: dhive `src/client.ts` —
/// `Buffer.from('beeab0de00000000000000000000000000000000000000000000000000000000', 'hex')`.
/// Note the first bytes are `beeab0de`, not `beeab0f2` (a value that
/// circulates in some older snippets).
const hiveMainnetChainIdHex =
    'beeab0de00000000000000000000000000000000000000000000000000000000';

/// Hive public-key address prefix (dhive `DEFAULT_ADDRESS_PREFIX`).
/// Hive kept the `STM` prefix from its Steem heritage.
const hiveAddressPrefix = 'STM';

/// Default public API nodes, tried in order. `api.hive.blog` is the
/// canonical community endpoint; the others are well-known fallbacks.
const defaultHiveNodes = <String>[
  'https://api.hive.blog',
  'https://api.deathwing.me',
  'https://hive-api.arcange.eu',
  'https://anyx.io',
];

/// Default per-request timeout for JSON-RPC calls.
const defaultHiveTimeout = Duration(seconds: 15);

/// Default HiveAuth (HAS) server.
const hiveAuthDefaultHost = 'wss://has.hiveauth.com';
