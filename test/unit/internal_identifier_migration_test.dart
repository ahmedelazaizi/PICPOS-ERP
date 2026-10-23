// Internal-identifier migration (owner decision 2026-10-23,
// docs/security/internal-identifier-migration.md).
//
// For every secure-storage key renamed from the old product name to a PicPos
// name: old data stays readable, the new key works, the migration is idempotent
// and survives an interruption (copy → verify → delete), and a fresh install
// works. Old key names come from `LegacyIdentifiers` (assembled at runtime in
// production); the new names are spelled out here on purpose.
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ural_erp/services/api/api_session_token.dart';
import 'package:ural_erp/services/api/lan_pairing_service.dart';
import 'package:ural_erp/services/api/server_secrets.dart';
import 'package:ural_erp/services/api/table_bill_token.dart';
import 'package:ural_erp/services/db_key_names.dart';
import 'package:ural_erp/services/db_key_types.dart';
import 'package:ural_erp/services/invoice_integrity_service.dart';
import 'package:ural_erp/services/legacy_device_seed.dart';
import 'package:ural_erp/services/legacy_identifiers.dart';
import 'package:ural_erp/services/secret_store.dart';
import 'package:ural_erp/services/secure_storage_service.dart';
import 'package:ural_erp/services/security_service.dart';
import 'package:ural_erp/services/server_proxy.dart';
import 'package:ural_erp/services/storage_key_migration.dart';

import '../helpers/db_key_harness.dart';

/// In-memory store whose failures can be injected per key.
class _Store extends MemorySecretStore {
  _Store([super.initial]);
  final Set<String> failWriteKeys = {};
  final Set<String> dropWriteKeys = {}; // write "succeeds" but stores nothing
  final Set<String> failDeleteKeys = {};
  int writes = 0;

  @override
  Future<void> write(String key, String value) async {
    writes++;
    if (failWriteKeys.contains(key)) throw StateError('write boom');
    if (dropWriteKeys.contains(key)) return;
    return super.write(key, value);
  }

  @override
  Future<void> delete(String key) async {
    if (failDeleteKeys.contains(key)) throw StateError('delete boom');
    return super.delete(key);
  }
}

String _b64Key(int seed) =>
    base64UrlEncode(List<int>.generate(32, (i) => (i * 7 + seed) & 0xff));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ── every renamed storage key: (label, new name, old name, sample value) ──
  final entries = <({String label, String newKey, String oldKey, String value})>[
    (
      label: 'db fallback key',
      newKey: DbKeyNames.legacyFallback,
      oldKey: LegacyIdentifiers.dbFallbackStorageKey,
      value: 'f' * 64,
    ),
    (
      label: 'invoice integrity secret',
      newKey: 'picpos_invoice_integrity_secret_v2',
      oldKey: LegacyIdentifiers.integritySecretStorageKey,
      value: _b64Key(1),
    ),
    (
      label: 'session HMAC key',
      newKey: ServerSecrets.sessionStorageKey,
      oldKey: LegacyIdentifiers.sessionHmacStorageKey,
      value: _b64Key(2),
    ),
    (
      label: 'table-bill HMAC key',
      newKey: ServerSecrets.tableBillStorageKey,
      oldKey: LegacyIdentifiers.tableBillHmacStorageKey,
      value: _b64Key(3),
    ),
    (
      label: 'LAN install secret',
      newKey: LanPairingService.installSecretStorageKey,
      oldKey: LegacyIdentifiers.lanInstallSecretStorageKey,
      value: _b64Key(4),
    ),
    (
      label: 'API token',
      newKey: 'picpos_api_token',
      oldKey: LegacyIdentifiers.apiTokenStorageKey,
      value: 'token-from-the-old-build',
    ),
  ];

  test('new names are PicPos names; old names are not the new names', () {
    for (final e in entries) {
      expect(e.newKey, startsWith('picpos_'), reason: e.label);
      expect(e.oldKey, isNot(e.newKey), reason: e.label);
      expect(RegExp('ural', caseSensitive: false).hasMatch(e.newKey), isFalse);
    }
  });

  for (final e in entries) {
    group('StorageKeyMigration — ${e.label}', () {
      late _Store store;
      setUp(() => store = _Store());

      Future<String?> read() => StorageKeyMigration.read(store,
          newKey: e.newKey, oldKey: e.oldKey);

      test('old data stays readable and is moved: copy → verify → delete',
          () async {
        store.values[e.oldKey] = e.value;
        expect(await read(), e.value);
        expect(store.values[e.newKey], e.value);
        expect(store.values.containsKey(e.oldKey), isFalse);
      });

      test('idempotent: second and third read change nothing', () async {
        store.values[e.oldKey] = e.value;
        await read();
        final writes = store.writes;
        expect(await read(), e.value);
        expect(await read(), e.value);
        expect(store.writes, writes);
        expect(store.values, {e.newKey: e.value});
      });

      test('fresh install: nothing stored ⇒ null and nothing written', () async {
        expect(await read(), isNull);
        expect(store.values, isEmpty);
        expect(store.writes, 0);
      });

      test('new key works: write goes to the new name, stale old one dropped',
          () async {
        store.values[e.oldKey] = 'stale';
        await StorageKeyMigration.write(store,
            newKey: e.newKey, oldKey: e.oldKey, value: e.value);
        expect(store.values, {e.newKey: e.value});
        expect(await read(), e.value);
      });

      test('delete removes both names (no resurrection through the old one)',
          () async {
        store.values[e.oldKey] = e.value;
        store.values[e.newKey] = e.value;
        await StorageKeyMigration.delete(store,
            newKey: e.newKey, oldKey: e.oldKey);
        expect(store.values, isEmpty);
        expect(await read(), isNull);
      });

      test('interrupted: copy fails ⇒ value still returned, old key untouched, '
          'next run completes', () async {
        store.values[e.oldKey] = e.value;
        store.failWriteKeys.add(e.newKey);
        expect(await read(), e.value);
        expect(store.values, {e.oldKey: e.value}, reason: 'nothing deleted');

        store.failWriteKeys.clear();
        expect(await read(), e.value);
        expect(store.values, {e.newKey: e.value});
      });

      test('interrupted: write silently dropped (read-back differs) ⇒ old key '
          'is NOT deleted', () async {
        store.values[e.oldKey] = e.value;
        store.dropWriteKeys.add(e.newKey);
        expect(await read(), e.value);
        expect(store.values, {e.oldKey: e.value});
      });

      test('interrupted: delete of the old key fails after a good copy ⇒ both '
          'exist, value correct; next read removes the old one', () async {
        store.values[e.oldKey] = e.value;
        store.failDeleteKeys.add(e.oldKey);
        expect(await read(), e.value);
        expect(store.values, {e.oldKey: e.value, e.newKey: e.value});

        store.failDeleteKeys.clear();
        expect(await read(), e.value);
        expect(store.values, {e.newKey: e.value});
      });

      test('new key wins over a different old one, which is left untouched',
          () async {
        store.values[e.newKey] = e.value;
        store.values[e.oldKey] = 'something-else';
        expect(await read(), e.value);
        expect(store.values[e.oldKey], 'something-else');
      });
    });
  }

  // ── site: invoice integrity secret ────────────────────────────────────────
  group('InvoiceIntegrityService', () {
    const newKey = 'picpos_invoice_integrity_secret_v2';
    final oldKey = LegacyIdentifiers.integritySecretStorageKey;
    const storage = FlutterSecureStorage();

    Future<String> sign() async => InvoiceIntegrityService.computeSalesInvoiceHash(
          invoiceNumber: 'INV-9',
          invoiceDate: DateTime.parse('2026-01-01T00:00:00.000Z'),
          total: 10,
          subtotal: 9,
          discount: 0,
          tax: 1,
          paid: 10,
          customerId: 2,
          userId: 3,
          paymentMethod: 'cash',
        );

    String expectedFor(String secret) {
      final payload = [
        'INV-9', '2026-01-01T00:00:00.000Z', '10.0000', '9.0000', '0.0000',
        '1.0000', '10.0000', '2', '3', 'cash', //
      ].join('|');
      return 'v2:${Hmac(sha256, utf8.encode(secret)).convert(utf8.encode(payload))}';
    }

    test('secret written under the old name keeps signing/verifying identically',
        () async {
      final secret = _b64Key(9);
      // An invoice signed by the previous build with this secret:
      final storedByOldBuild = expectedFor(secret);

      FlutterSecureStorage.setMockInitialValues({oldKey: secret});
      await InvoiceIntegrityService.initialize(storage: storage);

      expect(await sign(), storedByOldBuild);
      expect(
        InvoiceIntegrityService.verifySalesInvoiceHash(
          storedHash: storedByOldBuild,
          invoiceNumber: 'INV-9',
          invoiceDate: DateTime.parse('2026-01-01T00:00:00.000Z'),
          total: 10,
          subtotal: 9,
          discount: 0,
          tax: 1,
          paid: 10,
          customerId: 2,
          userId: 3,
          paymentMethod: 'cash',
        ),
        isTrue,
      );
      expect(await storage.read(key: newKey), secret);
      expect(await storage.read(key: oldKey), isNull);

      // idempotent
      await InvoiceIntegrityService.initialize(storage: storage);
      expect(await sign(), storedByOldBuild);
    });

    test('fresh install generates a secret under the PicPos name only',
        () async {
      FlutterSecureStorage.setMockInitialValues({});
      await InvoiceIntegrityService.initialize(storage: storage);
      final generated = await storage.read(key: newKey);
      expect(generated, isNotNull);
      expect(await storage.read(key: oldKey), isNull);
      expect(await sign(), expectedFor(generated!));
    });
  });

  // ── site: server secrets (session HMAC / table-bill HMAC / prev) ──────────
  group('ServerSecrets', () {
    setUp(() {
      ApiSessionToken.clearKey();
      TableBillToken.clearKey();
    });
    tearDown(() {
      ApiSessionToken.clearKey();
      TableBillToken.clearKey();
    });

    final oldSession = LegacyIdentifiers.sessionHmacStorageKey;
    final oldBill = LegacyIdentifiers.tableBillHmacStorageKey;
    final oldBillPrev = '${LegacyIdentifiers.tableBillHmacStorageKey}_prev';
    final newBillPrev = ServerSecrets.previousKeyOf(ServerSecrets.tableBillStorageKey);

    ServerSecrets make(SecretStore s) =>
        ServerSecrets(store: s, logger: (tag, message) async {});

    test('old-named keys are adopted byte-for-byte; existing sessions verify',
        () async {
      final sessionValue = _b64Key(11);
      final store = _Store({
        oldSession: sessionValue,
        oldBill: _b64Key(12),
        oldBillPrev: _b64Key(13),
      });
      // A session token minted by the previous build with the old key.
      ApiSessionToken.setSigningKey(base64Url.decode(sessionValue));
      final token = ApiSessionToken.mint(42);
      ApiSessionToken.clearKey();

      final s = make(store);
      await s.initialize();

      expect(s.sessionKey, base64Url.decode(sessionValue));
      expect(s.tableBillKey, base64Url.decode(_b64Key(12)));
      expect(s.tableBillPreviousKey, base64Url.decode(_b64Key(13)));
      expect(ApiSessionToken.verify(token), 42,
          reason: 'sessions issued before the rename stay valid');
      expect(store.values, {
        ServerSecrets.sessionStorageKey: sessionValue,
        ServerSecrets.tableBillStorageKey: _b64Key(12),
        newBillPrev: _b64Key(13),
      });

      // idempotent: a second boot sees the same keys and writes nothing.
      final writes = store.writes;
      final s2 = make(store);
      await s2.initialize();
      expect(s2.sessionKey, s.sessionKey);
      expect(store.writes, writes);
    });

    test('fresh install creates keys under PicPos names only', () async {
      final store = _Store();
      await make(store).initialize();
      expect(store.values.keys.toSet(), {
        ServerSecrets.sessionStorageKey,
        ServerSecrets.tableBillStorageKey,
      });
    });

    test('copy interrupted ⇒ the old key value is still used and kept',
        () async {
      final store = _Store({oldSession: _b64Key(21), oldBill: _b64Key(22)})
        ..failWriteKeys.add(ServerSecrets.sessionStorageKey);
      final s = make(store);
      await s.initialize();
      expect(s.sessionKey, base64Url.decode(_b64Key(21)));
      expect(store.values[oldSession], _b64Key(21));
    });

    test('rotate writes the new name and removes the old previous-key copy',
        () async {
      final store = _Store({
        oldSession: _b64Key(31),
        oldBill: _b64Key(32),
        oldBillPrev: _b64Key(33),
      });
      final s = make(store);
      await s.initialize();
      await s.rotate(ServerSecretKind.tableBill);
      expect(store.values.keys.toSet(), {
        ServerSecrets.sessionStorageKey,
        ServerSecrets.tableBillStorageKey,
        newBillPrev,
      });
      expect(store.values[newBillPrev], _b64Key(32),
          reason: 'previous = the key that was current');
    });
  });

  // ── site: LAN pairing install secret ──────────────────────────────────────
  group('LanPairingService', () {
    final oldKey = LegacyIdentifiers.lanInstallSecretStorageKey;
    const storage = FlutterSecureStorage();

    String tokenFor(String secret, String device) => base64UrlEncode(
        Hmac(sha256, utf8.encode(secret)).convert(utf8.encode(device)).bytes);

    test('paired-device tokens issued with the old secret keep verifying',
        () async {
      final secret = _b64Key(41);
      final tokenFromOldBuild = tokenFor(secret, 'device-1');
      FlutterSecureStorage.setMockInitialValues({oldKey: secret});

      final svc = LanPairingService(null, storage: SecureStorageService());
      await svc.initialize();

      expect(svc.tokenForDevice('device-1'), tokenFromOldBuild);
      expect(await storage.read(key: LanPairingService.installSecretStorageKey),
          secret);
      expect(await storage.read(key: oldKey), isNull);

      // idempotent: a new instance (restart) yields the same secret.
      final again = LanPairingService(null, storage: SecureStorageService());
      await again.initialize();
      expect(again.tokenForDevice('device-1'), tokenFromOldBuild);
    });

    test('fresh install: secret generated under the PicPos name only',
        () async {
      FlutterSecureStorage.setMockInitialValues({});
      final svc = LanPairingService(null, storage: SecureStorageService());
      await svc.initialize();
      expect(svc.isInitialized, isTrue);
      expect(await storage.read(key: LanPairingService.installSecretStorageKey),
          isNotNull);
      expect(await storage.read(key: oldKey), isNull);
    });
  });

  // ── site: client API token ────────────────────────────────────────────────
  group('ServerProxy token', () {
    final oldKey = LegacyIdentifiers.apiTokenStorageKey;
    const storage = FlutterSecureStorage();

    Future<void> resetProxy() async {
      FlutterSecureStorage.setMockInitialValues({});
      SharedPreferences.setMockInitialValues({});
      ServerProxy.instance.setApiToken(null);
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }

    test('token saved by the old build is restored and moved', () async {
      await resetProxy();
      FlutterSecureStorage.setMockInitialValues({oldKey: 'old-token'});
      await ServerProxy.instance.restoreToken();
      expect(ServerProxy.instance.apiToken, 'old-token');
      expect(await storage.read(key: 'picpos_api_token'), 'old-token');
      expect(await storage.read(key: oldKey), isNull);
    });

    test('set / clear use the new name and leave no old copy', () async {
      await resetProxy();
      FlutterSecureStorage.setMockInitialValues({oldKey: 'stale-old'});
      ServerProxy.instance.setApiToken('fresh');
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(await storage.read(key: 'picpos_api_token'), 'fresh');
      expect(await storage.read(key: oldKey), isNull);

      ServerProxy.instance.setApiToken(null);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(await storage.read(key: 'picpos_api_token'), isNull);
      expect(await storage.read(key: oldKey), isNull);
    });
  });

  // ── site: DB fallback key (the one that can lock the owner out) ───────────
  group('DB key — database created with the OLD fallback key name', () {
    late DbKeyHarness h;
    final oldName = DbKeyNames.legacyFallbackOld;
    const name = 'picpos_unified.db';
    final fallback = sha256.convert(utf8.encode('device-less-fallback')).toString();

    setUp(() => h = DbKeyHarness());
    tearDown(() => h.dispose());

    DbKey fbKey() => DbKey(DbKeyKind.legacyFallback, fallback);

    test('opens via the old-named key, then lives under the new name',
        () async {
      await FakeSqlCipherEngine.create(h.db, fbKey());
      h.legacyDerived = null; // no device id ⇒ only the stored fallback exists
      h.memory.values[oldName] = fallback;

      final found = await h.manager().findOpening(h.db, dbName: name);
      expect(found, isNotNull, reason: 'database must still open');
      expect(found!.source, DbKeySource.legacyFallback);
      expect(found.key.value, fallback);
      expect(h.memory.values, {DbKeyNames.legacyFallback: fallback});

      // second boot: same result, no further storage writes.
      final writes = h.flaky.writeCount;
      final again = await h.manager().findOpening(h.db, dbName: name);
      expect(again!.source, DbKeySource.legacyFallback);
      expect(h.flaky.writeCount, writes);
    });

    test('resolveForOpen also succeeds (the real boot entry point)', () async {
      await FakeSqlCipherEngine.create(h.db, fbKey());
      h.legacyDerived = null;
      h.memory.values[oldName] = fallback;

      final r = await h.manager().resolveForOpen(h.db);
      expect(r, isA<DbKeyReady>());
      final ready = r as DbKeyReady;
      expect(ready.key.value, fallback);
      expect(ready.source, DbKeySource.legacyFallback);
    });

    test('copy to the new name fails ⇒ still opens, old key untouched',
        () async {
      await FakeSqlCipherEngine.create(h.db, fbKey());
      h.legacyDerived = null;
      h.memory.values[oldName] = fallback;
      h.flaky.writesThrow = true;

      final found = await h.manager().findOpening(h.db, dbName: name);
      expect(found!.source, DbKeySource.legacyFallback);
      expect(h.memory.values, {oldName: fallback});
    });

    test('new-named key alone (already migrated) opens the database', () async {
      await FakeSqlCipherEngine.create(h.db, fbKey());
      h.legacyDerived = null;
      h.memory.values[DbKeyNames.legacyFallback] = fallback;
      final found = await h.manager().findOpening(h.db, dbName: name);
      expect(found!.source, DbKeySource.legacyFallback);
    });

    test('fresh install (no database, no keys) is unaffected: v2 key created',
        () async {
      final r = await h.manager().resolveForOpen(h.db);
      expect((r as DbKeyReady).source, DbKeySource.freshInstall);
      expect(h.memory.values.containsKey(oldName), isFalse);
    });

    test('SecurityService.getDatabaseEncryptionKey: old-named fallback is '
        'returned and migrated; fresh install generates under the new name',
        () async {
      final saved = LegacyDeviceSeed.deviceIdProvider;
      addTearDown(() => LegacyDeviceSeed.deviceIdProvider = saved);
      LegacyDeviceSeed.deviceIdProvider = () async => null;
      const storage = FlutterSecureStorage();

      FlutterSecureStorage.setMockInitialValues({oldName: fallback});
      expect(await SecurityService.getDatabaseEncryptionKey(), fallback);
      expect(await storage.read(key: DbKeyNames.legacyFallback), fallback);
      expect(await storage.read(key: oldName), isNull);
      expect(await SecurityService.getDatabaseEncryptionKey(), fallback);

      FlutterSecureStorage.setMockInitialValues({});
      final fresh =
          await SecurityService.getDatabaseEncryptionKey(databaseExists: false);
      expect(fresh, matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(await storage.read(key: DbKeyNames.legacyFallback), fresh);
      expect(await storage.read(key: oldName), isNull);
    });

    test('database exists + no key under either name ⇒ throws, never generates',
        () async {
      final saved = LegacyDeviceSeed.deviceIdProvider;
      addTearDown(() => LegacyDeviceSeed.deviceIdProvider = saved);
      LegacyDeviceSeed.deviceIdProvider = () async => null;
      FlutterSecureStorage.setMockInitialValues({});
      await expectLater(SecurityService.getDatabaseEncryptionKey(),
          throwsA(isA<DatabaseKeyUnavailableException>()));
      expect(await const FlutterSecureStorage().readAll(), isEmpty);
    });

    test('clearAll protects BOTH the old and the new fallback key names',
        () async {
      FlutterSecureStorage.setMockInitialValues({
        oldName: fallback,
        DbKeyNames.legacyFallback: fallback,
        'e_invoice_secret_x': 'y',
      });
      await SecureStorageService().clearAll();
      final left = await const FlutterSecureStorage().readAll();
      expect(left.keys.toSet(), {oldName, DbKeyNames.legacyFallback});
    });
  });
}
