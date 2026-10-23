import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;

import 'db_key_names.dart';
import 'db_key_recovery.dart';
import 'db_key_types.dart';
import 'db_keyinfo_file.dart';
import 'legacy_device_seed.dart';
import 'secret_store.dart';
import 'sqlcipher_engine.dart';
import 'storage_key_migration.dart';

/// محتوى فتحتَي المفتاح في التخزين الآمن (صالحٌ الشكلَ أو `null`).
class StoredKeys {
  const StoredKeys({this.primary, this.shadow, this.storeFailed = false});

  final String? primary;
  final String? shadow;

  /// القراءةُ رمت استثناءً حتى بعد إعادة المحاولة — **ليس** «غائب».
  final bool storeFailed;

  bool get isEmpty => primary == null && shadow == null;
}

/// مفتاحُ قاعدة البيانات العشوائيّ (E-01، المرحلة ب).
///
/// القواعدُ التي لا تُكسَر:
///  * «أوّلُ تشغيل» = **غيابُ ملف القاعدة** لا غيابُ المفتاح. `flutter_secure_storage`
///    على ويندوز يُرجع `null` عند أيّ عطل (ملف مبتور، اعتمادٌ محذوف، حسابُ
///    ويندوز آخر)، فتوليدُ مفتاحٍ عند `null` يُتلف قاعدةً موجودة.
///  * قاعدةٌ موجودةٌ + لا مرشّحَ يفتحها ⇒ [DbKeyUnavailable]؛ **لا توليدَ ولا
///    حذفَ ولا إعادةَ إنشاء** في أيّ فرعٍ منها.
///  * هذا الصنفُ لا يرحّل: الترحيلُ في `DbKeyMigrationService.migrate()` ولا
///    يُستدعى إلا صراحةً (ق-7).
class DbKeyManager {
  DbKeyManager({
    required this.store,
    required this.engine,
    Future<String?> Function()? legacyDerive,
    List<int> Function(int n)? randomBytes,
    DateTime Function()? now,
    Future<void> Function(Duration)? delay,
    this.readRetries = 2,
    this.recoveryMemoryKb = RecoveryEnvelope.defaultMemoryKb,
    this.recoveryIterations = RecoveryEnvelope.defaultIterations,
  })  : _legacyDerive = legacyDerive ?? LegacyDeviceSeed.derive,
        _randomBytes = randomBytes ?? _secureBytes,
        _now = now ?? DateTime.now,
        _delay = delay ?? Future<void>.delayed;

  /// التركيبةُ الإنتاجيّة: تخزينٌ آمن حقيقيّ + SQLCipher عبر drift.
  factory DbKeyManager.production() => DbKeyManager(
        store: SecureStorageSecretStore(),
        engine: const NativeSqlCipherEngine(),
      );

  final SecretStore store;
  final SqlCipherEngine engine;
  final int readRetries;
  final int recoveryMemoryKb;
  final int recoveryIterations;
  final Future<String?> Function() _legacyDerive;
  final List<int> Function(int n) _randomBytes;
  final DateTime Function() _now;
  final Future<void> Function(Duration) _delay;

  /// يُنفَّذ أوّلَ `resolveForOpen` — يربط به `DbKeyMigrationService` تعافيَ
  /// انقطاع الترحيل وتأكيدَ M8 (§2.3/§2.4).
  Future<void> Function(File dbFile)? beforeResolve;

  static List<int> _secureBytes(int n) {
    final r = Random.secure();
    return List<int>.generate(n, (_) => r.nextInt(256));
  }

  static String dbNameOf(File db) => p.basename(db.path);

  DateTime now() => _now();

  // ───────────────────────── التخزين ─────────────────────────

  Future<String?> _readWithRetry(String key, void Function() onFail) async {
    for (var attempt = 0;; attempt++) {
      try {
        return await store.read(key);
      } catch (_) {
        if (attempt >= readRetries) {
          onFail();
          return null;
        }
        await _delay(const Duration(milliseconds: 100));
      }
    }
  }

  /// يقرأ الفتحتين. القيمةُ التالفةُ الشكل تُعامَل `null`.
  Future<StoredKeys> readStored(String dbName) async {
    var failed = false;
    void fail() => failed = true;
    final a = await _readWithRetry(DbKeyNames.primary(dbName), fail);
    final b = await _readWithRetry(DbKeyNames.shadow(dbName), fail);
    return StoredKeys(
      primary: isValidRawKeyHex(a) ? a : null,
      shadow: isValidRawKeyHex(b) ? b : null,
      storeFailed: failed,
    );
  }

  /// يكتب الفتحتين ثم **يعيد قراءتهما ويقارن**؛ يرمي [DbKeyStoreException].
  Future<void> writeSlots(String dbName, String hex) async {
    if (!isValidRawKeyHex(hex)) {
      throw const DbKeyStoreException('invalid key shape');
    }
    try {
      await store.write(DbKeyNames.primary(dbName), hex);
      await store.write(DbKeyNames.shadow(dbName), hex);
      final a = await store.read(DbKeyNames.primary(dbName));
      final b = await store.read(DbKeyNames.shadow(dbName));
      if (a != hex || b != hex) {
        throw const DbKeyStoreException('read-back mismatch');
      }
    } on DbKeyStoreException {
      rethrow;
    } catch (e) {
      throw DbKeyStoreException('secure storage failure: ${e.runtimeType}');
    }
  }

  String generateKeyHex() => bytesToHex(_randomBytes(32));

  /// يعيد مفتاح v2 المخزَّن (ويصلح الفتحةَ الناقصة) أو يولّد واحدًا جديدًا.
  /// **لا يُستدعى لقاعدةٍ موجودةٍ إلا من الترحيل الصريح (M1)** بعد فتحها
  /// بمفتاحٍ قديم — أي بعد إثبات أنّ الملف ليس «ضاع مفتاحه».
  Future<DbKey> ensureStoredKey(String dbName) async {
    final s = await readStored(dbName);
    if (s.storeFailed) {
      throw const DbKeyStoreException('secure storage unreadable');
    }
    final existing = s.primary ?? s.shadow;
    final hex = existing ?? generateKeyHex();
    await writeSlots(dbName, hex);
    return DbKey.raw(hex);
  }

  // ───────────────────────── رمز الاسترداد ─────────────────────────

  /// يولّد رمزًا جديدًا، يغلّف به [key]، يحفظ الرمزَ بانتظار التأكيد، ويعيد
  /// الغلافَ ليُكتب في keyinfo.
  Future<Map<String, dynamic>> createRecovery(String dbName, DbKey key) async {
    final code = RecoveryCode.generate(randomBytes: _randomBytes);
    final env = await RecoveryEnvelope.wrap(
      key.value,
      code,
      memoryKb: recoveryMemoryKb,
      iterations: recoveryIterations,
      randomBytes: _randomBytes,
    );
    try {
      await store.write(DbKeyNames.recoveryPending(dbName), code);
    } catch (_) {
      throw const DbKeyStoreException('cannot persist recovery code');
    }
    return env;
  }

  /// الرمزُ الذي لم يؤكّد المدير حفظَه بعد (أو `null`).
  Future<String?> pendingRecoveryCode(String dbName) async {
    try {
      return await store.read(DbKeyNames.recoveryPending(dbName));
    } catch (_) {
      return null;
    }
  }

  /// «حفظتُه/طبعتُه» — يُحذف الرمزُ من التخزين.
  Future<void> acknowledgeRecoveryCode(String dbName) =>
      store.delete(DbKeyNames.recoveryPending(dbName));

  // ───────────────────────── المرشّحون ─────────────────────────

  Future<List<DbKey>> legacyCandidates() async {
    final out = <DbKey>[];
    String? derived;
    try {
      derived = await _legacyDerive();
    } catch (_) {
      derived = null;
    }
    if (derived != null && derived.isNotEmpty) {
      out.add(DbKey(DbKeyKind.legacyDerived, derived));
    }
    // المفتاح الاحتياطيّ القديم: قراءةٌ فقط، **لا يُولَّد أبدًا**.
    try {
      // الاسم الجديد أوّلًا؛ إن غاب يُقرأ الاسم القديم ويُنسخ (وتُتحقَّق
      // القراءة) ثم يُحذف القديم — لا تُفقد قيمةٌ في أيّ نقطة انقطاع.
      final fb = await StorageKeyMigration.read(
        store,
        newKey: DbKeyNames.legacyFallback,
        oldKey: DbKeyNames.legacyFallbackOld,
        isValid: (v) => v.length >= 32,
      );
      if (fb != null && fb.length >= 32) {
        out.add(DbKey(DbKeyKind.legacyFallback, fb));
      }
    } catch (_) {}
    return out;
  }

  Future<({DbKey key, DbKeySource source})?> findOpening(
    File file, {
    required String dbName,
    StoredKeys? stored,
  }) async {
    final s = stored ?? await readStored(dbName);
    final tried = <String>{};
    Future<bool> opens(DbKey k) async {
      if (!tried.add(k.effectiveId)) return false;
      return engine.canOpen(file, k);
    }

    if (s.primary != null) {
      final k = DbKey.raw(s.primary!);
      if (await opens(k)) return (key: k, source: DbKeySource.primarySlot);
    }
    if (s.shadow != null) {
      final k = DbKey.raw(s.shadow!);
      if (await opens(k)) return (key: k, source: DbKeySource.shadowSlot);
    }
    for (final k in await legacyCandidates()) {
      if (await opens(k)) {
        return (
          key: k,
          source: k.kind == DbKeyKind.legacyDerived
              ? DbKeySource.legacyDerived
              : DbKeySource.legacyFallback,
        );
      }
    }
    return null;
  }

  /// مفتاح فتح الملف بأيّ مرشّح، أو `null` (لفحص النسخ قبل الاستعادة).
  Future<DbKey?> findOpeningKey(File file, {required String dbName}) async =>
      (await findOpening(file, dbName: dbName))?.key;

  // ───────────────────────── resolveForOpen ─────────────────────────

  Future<bool> _isPlaintextSqlite(File f) async {
    RandomAccessFile? raf;
    try {
      raf = await f.open();
      final head = await raf.read(16);
      const magic = 'SQLite format 3';
      if (head.length < magic.length) return false;
      return String.fromCharCodes(head.sublist(0, magic.length)) == magic;
    } catch (_) {
      return false;
    } finally {
      await raf?.close();
    }
  }

  Future<bool> _databaseExists(File db) async {
    if (await db.exists()) return true;
    final wal = File('${db.path}-wal');
    return await wal.exists() && await wal.length() > 0;
  }

  /// يحدّد مفتاحَ فتح [dbFile]. لا يرحّل، ولا يولّد مفتاحًا لقاعدةٍ موجودة.
  Future<DbKeyResolution> resolveForOpen(File dbFile) async {
    final hook = beforeResolve;
    if (hook != null) await hook(dbFile);

    final name = dbNameOf(dbFile);
    final info = await KeyInfoFile.read(dbFile);
    final stored = await readStored(name);

    if (!await _databaseExists(dbFile)) {
      return _freshInstall(dbFile, name, info, stored);
    }

    final opening = await findOpening(dbFile, dbName: name, stored: stored);
    if (opening != null) {
      final k = opening.key;
      if (k.kind == DbKeyKind.rawV2) {
        await _repairSlots(name, k.value, stored);
      }
      return DbKeyReady(k, opening.source);
    }

    final hasEnvelope = info?.recoveryEnvelope != null;
    final preV2 = await File('${dbFile.path}.pre-v2').exists();
    DbKeyUnavailable un(DbKeyUnavailableReason r, [String? d]) =>
        DbKeyUnavailable(
          r,
          canRecoverWithCode: hasEnvelope,
          preMigrationCopyAvailable: preV2,
          detail: d,
        );

    if (await _isPlaintextSqlite(dbFile)) {
      return un(DbKeyUnavailableReason.plaintextDatabase);
    }
    if (stored.storeFailed) return un(DbKeyUnavailableReason.storeFailure);
    if (stored.isEmpty) {
      return un(
        info != null && info.claimsMigrated
            ? DbKeyUnavailableReason.keyMissing
            : DbKeyUnavailableReason.noCandidateOpens,
      );
    }
    return un(DbKeyUnavailableReason.wrongKey);
  }

  Future<DbKeyResolution> _freshInstall(
    File dbFile,
    String name,
    KeyInfo? info,
    StoredKeys stored,
  ) async {
    if (stored.storeFailed) {
      return const DbKeyUnavailable(DbKeyUnavailableReason.storeFailure);
    }
    final existing = stored.primary ?? stored.shadow;
    if (existing == null && info != null && info.claimsMigrated) {
      // الملفُّ غائبٌ لكنّ keyinfo يشهد بقاعدةٍ مرحَّلةٍ كانت هنا والمفتاحُ
      // غائب — لا نتصرّف كتثبيتٍ جديد.
      return DbKeyUnavailable(
        DbKeyUnavailableReason.databaseMissingKeyinfoPresent,
        canRecoverWithCode: info.recoveryEnvelope != null,
      );
    }
    try {
      final key = await ensureStoredKey(name);
      final current = await KeyInfoFile.read(dbFile);
      if (current == null ||
          current.kind != DbKeyKind.rawV2 ||
          current.fingerprint != key.fingerprint) {
        final env = await createRecovery(name, key);
        await KeyInfoFile.write(
          dbFile,
          KeyInfo(
            kind: DbKeyKind.rawV2,
            fingerprint: key.fingerprint,
            createdAt: _now().toIso8601String(),
            recoveryEnvelope: env,
          ),
        );
      }
      return DbKeyReady(key, DbKeySource.freshInstall);
    } on DbKeyStoreException catch (e) {
      return DbKeyUnavailable(DbKeyUnavailableReason.storeFailure,
          detail: e.message);
    }
  }

  /// فتحةٌ ناقصةٌ/مختلفةٌ ⇒ تُصلَح من الناجحة (كتابة + قراءة + مقارنة).
  Future<void> _repairSlots(String name, String hex, StoredKeys s) async {
    if (s.primary == hex && s.shadow == hex) return;
    try {
      await writeSlots(name, hex);
    } on DbKeyStoreException {
      // الفتحُ نجح؛ الإصلاحُ يُعاد في الإقلاع التالي.
    }
  }

  /// الاسترداد برمز الاسترداد (الحالةُ ق-8: حسابُ ويندوز آخر/اعتمادٌ محذوف).
  /// رمزٌ خاطئ أو غلافٌ تالف أو مفتاحٌ لا يفتح ⇒ [DbKeyUnavailable] **دون أيّ
  /// كتابةٍ** في التخزين.
  Future<DbKeyResolution> recoverWithCode(File dbFile, String code) async {
    final info = await KeyInfoFile.read(dbFile);
    final env = info?.recoveryEnvelope;
    if (env == null) {
      return const DbKeyUnavailable(DbKeyUnavailableReason.recoveryFailed,
          detail: 'no recovery envelope');
    }
    DbKeyUnavailable failed(String d) => DbKeyUnavailable(
        DbKeyUnavailableReason.recoveryFailed,
        canRecoverWithCode: true,
        detail: d);
    final String hex;
    try {
      hex = await RecoveryEnvelope.unwrap(env, code);
    } on RecoveryCodeException catch (e) {
      return failed(e.message);
    }
    final key = DbKey.raw(hex);
    if (info!.fingerprint != null && info.fingerprint != key.fingerprint) {
      return failed('fingerprint mismatch');
    }
    if (!await engine.canOpen(dbFile, key)) return failed('key does not open');
    try {
      await writeSlots(dbNameOf(dbFile), hex);
    } on DbKeyStoreException catch (e) {
      return DbKeyUnavailable(DbKeyUnavailableReason.storeFailure,
          canRecoverWithCode: true, detail: e.message);
    }
    return DbKeyReady(key, DbKeySource.recoveryCode);
  }
}
