// E-01 المرحلة ب (الجزء 2): المسارُ الفعليّ `openConnection()` على محرّك SQLCipher
// الحقيقيّ — طلبُ ترحيلٍ مؤجَّل ⇒ إقلاعٌ يرحّل ⇒ إقلاعٌ ثانٍ يلتزم ⇒ فقدُ المفتاح
// يحجب (لا قاعدةَ فارغة) ⇒ رمزُ الاسترداد يعيد الوصول.
//
// يتخطّى نفسَه بوضوح بلا SQLCipher (flutter test العاديّ). للتشغيل الحقيقيّ:
//   powershell -NoProfile -ExecutionPolicy Bypass -File tool\run_sqlcipher_tests.ps1 test/integration/db_key_open_connection_real_test.dart
//
// كلُّ شيءٍ في مجلدٍ مؤقّت (PathProvider وهميّ + تخزين آمن وهميّ)؛ لا يُلمس
// Documents ولا أيُّ *.db للمستخدم.
import 'dart:io';

import 'package:drift/drift.dart'
    show OpeningDetails, QueryExecutor, QueryExecutorUser;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:picpos_erp/data/database/connection_io.dart';
import 'package:picpos_erp/services/db_key_boot.dart';
import 'package:picpos_erp/services/db_key_manager.dart';
import 'package:picpos_erp/services/db_key_names.dart';
import 'package:picpos_erp/services/db_key_types.dart';
import 'package:picpos_erp/services/db_keyinfo_file.dart';
import 'package:picpos_erp/services/legacy_device_seed.dart';
import 'package:picpos_erp/services/secret_store.dart';
import 'package:picpos_erp/services/sqlcipher_engine.dart';

import '../helpers/sqlcipher_real.dart';

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.docs);
  final String docs;
  @override
  Future<String?> getApplicationDocumentsPath() async => docs;
}

class _User extends QueryExecutorUser {
  @override
  int get schemaVersion => 7;
  @override
  Future<void> beforeOpen(QueryExecutor e, OpeningDetails d) async {}
}

/// يفتح بمسار `openConnection()` الحقيقيّ ويقرأ ما فيه ثم يغلق.
Future<({int settings, int users, int userVersion})> _openAndRead() async {
  final ex = openConnection();
  try {
    await ex.ensureOpen(_User());
    return (
      settings: await scalarInt(ex, 'SELECT count(*) FROM settings;'),
      users: await scalarInt(ex, 'SELECT count(*) FROM users;'),
      userVersion: await scalarInt(ex, 'PRAGMA user_version;'),
    );
  } finally {
    await ex.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const engine = NativeSqlCipherEngine();

  late Directory docs;
  late File db;
  late DbKey legacy;
  late String name;
  final savedProvider = LegacyDeviceSeed.deviceIdProvider;

  setUp(() {
    docs = Directory.systemTemp.createTempSync('picpos_real_openconn_');
    PathProviderPlatform.instance = _FakePathProvider(docs.path);
    FlutterSecureStorage.setMockInitialValues({});
    LegacyDeviceSeed.deviceIdProvider = () async => 'TEST-DEVICE-ID-E01';
    legacy = DbKey(DbKeyKind.legacyDerived,
        LegacyDeviceSeed.deriveFor('TEST-DEVICE-ID-E01'));
    db = File(p.join(docs.path, getDatabaseFileName()));
    name = p.basename(db.path);
    DbKeyBoot.resetMemo();
    DbKeyBoot.lastOutcome = null;
    DbKeyBoot.factoryOverride = null;
  });

  tearDown(() {
    LegacyDeviceSeed.deviceIdProvider = savedProvider;
    DbKeyBoot.processIdOverride = null;
    DbKeyBoot.resetMemo();
    try {
      docs.deleteSync(recursive: true);
    } catch (_) {}
  });

  void boot(String id) {
    DbKeyBoot.resetMemo();
    DbKeyBoot.processIdOverride = id;
  }

  test(
      'طلب مؤجَّل ⇒ إقلاع 1 يرحّل ⇒ إقلاع 2 يلتزم ⇒ فقد المفتاح يحجب ⇒ الرمز يستردّ',
      () async {
    if (!await requireSqlCipher()) return;

    // قاعدة قديمة مشفّرة بالمفتاح المشتقّ، بأرقام معلومة.
    await createDb(db, legacy, userVersion: 7, settingsRows: 3);
    expect(looksPlain(db), isFalse);

    // (0) بلا طلب: يُفتح بالقديم ولا يُرحَّل شيء (لا ترحيل تلقائيّ).
    boot('boot0');
    final r0 = await _openAndRead();
    expect((r0.settings, r0.users, r0.userVersion), (3, 1, 7));
    expect(await engine.canOpen(db, legacy), isTrue);
    expect(await KeyInfoFile.read(db), isNull);
    expect(DbKeyBoot.lastOutcome, isNull);

    // (1) المدير يسجّل الطلب (كما تفعل واجهة الإعدادات) — لا شيءَ يتغيّر الآن.
    await DbKeyMigrationRequest(
      requestedAt: DateTime.now(),
      spaceConfirmedByAdmin: true,
    ).write(db);
    expect(await engine.canOpen(db, legacy), isTrue);

    // (2) الإقلاع التالي: openConnection ينفّذ الطلب قبل أيّ مقبض.
    boot('boot1');
    final r1 = await _openAndRead();
    expect((r1.settings, r1.users, r1.userVersion), (3, 1, 7),
        reason: 'البيانات وuser_version محفوظة بعد الترحيل');
    expect(DbKeyBoot.lastOutcome!.kind, DbKeyBootOutcomeKind.migrated,
        reason: DbKeyBoot.lastOutcome?.detail);
    expect(looksPlain(db), isFalse);
    expect(await engine.canOpen(db, legacy), isFalse,
        reason: 'المفتاح المشتقّ القديم لم يعد يفتحها');
    expect(await DbKeyMigrationRequest.read(db), isNull);
    var info = (await KeyInfoFile.read(db))!;
    expect(info.kind, DbKeyKind.rawV2);
    expect(info.migration!.state, 'committedPendingConfirm');
    expect(await File('${db.path}.pre-v2').exists(), isTrue);

    // رمز الاسترداد المعلَّق في التخزين الآمن (يُعرَض للمدير مرة واحدة).
    final store = SecureStorageSecretStore();
    final code = await store.read(DbKeyNames.recoveryPending(name));
    expect(code, isNotNull);

    // (3) الإقلاع الثاني: التزامٌ (M8) — تُحذف .pre-v2 وتبقى نسخة 30 يومًا.
    boot('boot2');
    final r2 = await _openAndRead();
    expect((r2.settings, r2.users, r2.userVersion), (3, 1, 7));
    info = (await KeyInfoFile.read(db))!;
    expect(info.migration!.state, 'done');
    expect(await File('${db.path}.pre-v2').exists(), isFalse);
    expect(
        Directory(p.join(docs.path, 'backups', 'key-migration'))
            .listSync()
            .whereType<File>()
            .any((f) => f.path.endsWith('.db')),
        isTrue);

    // (4) فقد المفتاح (حساب ويندوز آخر): حجبٌ صريح بلا قاعدة فارغة.
    FlutterSecureStorage.setMockInitialValues({});
    final before = await db.readAsBytes();
    final filesBefore = docs
        .listSync(recursive: true)
        .map((e) => p.relative(e.path, from: docs.path))
        .toList()
      ..sort();
    boot('boot3');
    await expectLater(_openAndRead(), throwsA(isA<DbKeyBlockedException>()));
    expect(await db.readAsBytes(), before, reason: 'القاعدة لم تُمَسّ');
    final filesAfter = docs
        .listSync(recursive: true)
        .map((e) => p.relative(e.path, from: docs.path))
        .toList()
      ..sort();
    expect(filesAfter, filesBefore, reason: 'لا ملفّ جديد (لا قاعدة فارغة)');

    // (5) رمز الاسترداد يعيد الوصول.
    final m = DbKeyManager.production();
    final bad = await m.recoverWithCode(db, 'AAAA-BBBB-CCCC-DDDD-EEEE-FFFF');
    expect(bad, isA<DbKeyUnavailable>());
    final ok = await m.recoverWithCode(db, code!);
    expect(ok, isA<DbKeyReady>());
    boot('boot4');
    final r4 = await _openAndRead();
    expect((r4.settings, r4.users, r4.userVersion), (3, 1, 7));
  }, timeout: const Timeout(Duration(minutes: 5)));

  test('تثبيت جديد: openConnection ينشئ مفتاحًا وقاعدةً مشفّرة فقط', () async {
    if (!await requireSqlCipher()) return;
    expect(await db.exists(), isFalse);
    boot('fresh');
    final ex = openConnection();
    try {
      await ex.ensureOpen(_User());
      await ex.runCustom('CREATE TABLE t(a INTEGER);', const []);
    } finally {
      await ex.close();
    }
    expect(await db.exists(), isTrue);
    expect(looksPlain(db), isFalse);
    final info = (await KeyInfoFile.read(db))!;
    expect(info.kind, DbKeyKind.rawV2);
    expect(await engine.canOpen(db, legacy), isFalse);
  }, timeout: const Timeout(Duration(minutes: 3)));
}
