// Example: read-only usage of `hiveblockchain_dart`.
//
// Run with: `dart example/main.dart`
// (reads public data from api.hive.blog; no keys involved).
import 'package:hiveblockchain_dart/hiveblockchain_dart.dart';

Future<void> main() async {
  final client = HiveClient();
  try {
    final account = await client.getAccount('carlosepc');
    if (account == null) {
      print('Account not found.');
      return;
    }
    print('Account: ${account.name} (id ${account.id})');
    print('Balance: ${account.balance} / ${account.hbdBalance}');
    print('Posting keys: ${account.postingKeys}');
    print('Posts: ${account.postCount}');

    final props = await client.getDynamicGlobalProperties();
    print('Head block: ${props.headBlockNumber} '
        '(${props.headBlockId.substring(0, 12)}...)');
    print('Current witness: ${props.currentWitness}');
  } finally {
    client.close();
  }

  // Build (but do NOT broadcast) a custom_json op for a game
  // achievement — this is pure local computation, no network, no keys.
  final op = HiveOperation.customJson(
    requiredAuths: const [],
    requiredPostingAuths: const ['carlosepc'],
    id: 'genioo_achievement',
    json: '{"game":"minesweeper","score":42}',
  );
  print('Op JSON: ${op.toJson()}');
}
