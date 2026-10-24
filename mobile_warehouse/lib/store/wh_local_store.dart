import 'package:picpos_device/picpos_device.dart';

/// The phone's offline store: SQLCipher database whose key lives in the
/// Android Keystore, with the durable outbox of `picpos_device`.
///
/// W0 skeleton: the outbox exists, is encrypted and survives restarts, but no
/// screen enqueues into it yet (documents arrive in W2+) and there is no
/// sender; the Outbox tab says so. Wiped with the pairing.
class WhLocalStore {
  WhLocalStore(this.store) : outbox = Outbox(store);

  final LocalStore store;
  final Outbox outbox;

  static const dbKeyName = 'picpos_warehouse.db_key.v1';
  static const dbFileName = 'picpos_warehouse_enc.db';

  static Future<WhLocalStore> open(SecretStore secrets) async {
    final key = await DatabaseKey(secrets, storageKey: dbKeyName).obtain();
    return WhLocalStore(await SqlCipherLocalStore.open(fileName: dbFileName, password: key));
  }

  /// In-memory store for tests and previews.
  factory WhLocalStore.memory() => WhLocalStore(MemoryLocalStore());

  Future<void> wipe() => store.clear();
}
