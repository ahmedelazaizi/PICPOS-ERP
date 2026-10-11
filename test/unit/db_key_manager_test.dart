// E-01 المرحلة ب: DbKeyManager — التوليد/التخزين/القراءة وحالة «لا توليد».
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/services/db_key_names.dart';
import 'package:ural_erp/services/db_key_types.dart';
import 'package:ural_erp/services/db_keyinfo_file.dart';

import '../helpers/db_key_harness.dart';

void main() {
  late DbKeyHarness h;
  const name = 'picpos_unified.db';

  setUp(() => h = DbKeyHarness());
  tearDown(() => h.dispose());

  group('تثبيت جديد = غياب ملف القاعدة', () {
    test('يولّد مفتاحًا خامًّا، يكتب الفتحتين، ويكتب keyinfo + غلاف استرداد',
        () async {
      final r = await h.manager().resolveForOpen(h.db);

      expect(r, isA<DbKeyReady>());
      final ready = r as DbKeyReady;
      expect(ready.source, DbKeySource.freshInstall);
      expect(ready.key.kind, DbKeyKind.rawV2);
      expect(isValidRawKeyHex(ready.key.value), isTrue);
      expect(ready.needsMigration, isFalse);

      expect(h.memory.values[DbKeyNames.primary(name)], ready.key.value);
      expect(h.memory.values[DbKeyNames.shadow(name)], ready.key.value);
      expect(h.memory.values[DbKeyNames.recoveryPending(name)], isNotNull);

      final info = await KeyInfoFile.read(h.db);
      expect(info!.kind, DbKeyKind.rawV2);
      expect(info.fingerprint, ready.key.fingerprint);
      expect(info.recoveryEnvelope, isNotNull);
      // keyinfo غيرُ سرّيّ: لا يحوي المفتاح.
      expect(await KeyInfoFile.of(h.db).readAsString(),
          isNot(contains(ready.key.value)));
    });

    test('لا يعيد التوليد في المرّة الثانية (نفس المفتاح)', () async {
      final a = await h.manager().resolveForOpen(h.db) as DbKeyReady;
      final b = await h.manager().resolveForOpen(h.db) as DbKeyReady;
      expect(b.key, a.key);
    });

    test('فشل كتابة التخزين ⇒ Unavailable(storeFailure) ولا مفتاح مُعتمَد',
        () async {
      h.flaky.writesThrow = true;
      final r = await h.manager().resolveForOpen(h.db);
      expect(r, isA<DbKeyUnavailable>());
      expect((r as DbKeyUnavailable).reason,
          DbKeyUnavailableReason.storeFailure);
      expect(await KeyInfoFile.of(h.db).exists(), isFalse);
    });

    test('كتابة تُبلَع بصمت تُكشَف بالقراءة بعد الكتابة', () async {
      h.flaky.writesSilentlyDropped = true;
      final r = await h.manager().resolveForOpen(h.db);
      expect((r as DbKeyUnavailable).reason,
          DbKeyUnavailableReason.storeFailure);
    });

    test('كتابة مبتورة (نصف القيمة) تُكشَف بالمقارنة', () async {
      h.flaky.writesTruncate = true;
      final r = await h.manager().resolveForOpen(h.db);
      expect((r as DbKeyUnavailable).reason,
          DbKeyUnavailableReason.storeFailure);
    });
  });

  group('قاعدة موجودة: لا توليدَ أبدًا', () {
    test('المفتاح الجديد غائب (null) + لا مرشّح قديم ⇒ Unavailable بلا أي كتابة',
        () async {
      // قاعدةٌ مشفّرةٌ بمفتاحٍ لا يعرفه أحد.
      await FakeSqlCipherEngine.create(h.db, DbKey.raw('1' * 64));
      h.legacyDerived = null;
      final bytesBefore = await h.db.readAsBytes();

      final r = await h.manager().resolveForOpen(h.db);

      expect(r, isA<DbKeyUnavailable>());
      expect(h.flaky.writeCount, 0, reason: 'لا كتابة في التخزين');
      expect(h.memory.values, isEmpty);
      expect(await KeyInfoFile.of(h.db).exists(), isFalse);
      expect(await h.db.readAsBytes(), bytesBefore);
    });

    test('التخزين يرجع null لكل قراءة مع قاعدة v2 موجودة ⇒ لا توليد', () async {
      final m = h.manager();
      final key = await m.ensureStoredKey(name);
      await FakeSqlCipherEngine.create(h.db, key);
      final before = Map<String, String>.of(h.memory.values);
      h.legacyDerived = null;
      h.flaky.readsReturnNull = true;
      final writesBefore = h.flaky.writeCount;

      final r = await h.manager().resolveForOpen(h.db);

      expect(r, isA<DbKeyUnavailable>());
      expect(h.flaky.writeCount, writesBefore);
      expect(h.memory.values, before);
    });

    test('استثناءُ قراءة التخزين ⇒ Unavailable(storeFailure) لا توليد', () async {
      await FakeSqlCipherEngine.create(h.db, DbKey.raw('2' * 64));
      h.legacyDerived = null;
      h.flaky.readsThrow = true;
      final r = await h.manager().resolveForOpen(h.db);
      expect((r as DbKeyUnavailable).reason,
          DbKeyUnavailableReason.storeFailure);
      expect(h.flaky.writeCount, 0);
    });

    test('مفتاحٌ مخزَّنٌ لا يفتح الملف ⇒ wrongKey', () async {
      await FakeSqlCipherEngine.create(h.db, DbKey.raw('3' * 64));
      h.legacyDerived = null;
      await h.memory.write(DbKeyNames.primary(name), '4' * 64);
      final r = await h.manager().resolveForOpen(h.db);
      expect((r as DbKeyUnavailable).reason, DbKeyUnavailableReason.wrongKey);
    });

    test('قاعدة نصّية SQLite format 3 ⇒ plaintextDatabase', () async {
      await h.db.writeAsBytes([
        ...'SQLite format 3'.codeUnits,
        0,
        ...List.filled(100, 0),
      ]);
      h.legacyDerived = null;
      final r = await h.manager().resolveForOpen(h.db);
      expect((r as DbKeyUnavailable).reason,
          DbKeyUnavailableReason.plaintextDatabase);
    });

    test('فتحةٌ ناقصةٌ تُصلَح من الناجحة', () async {
      final m = h.manager();
      final key = await m.ensureStoredKey(name);
      await FakeSqlCipherEngine.create(h.db, key);
      await h.memory.delete(DbKeyNames.shadow(name));

      final r = await h.manager().resolveForOpen(h.db) as DbKeyReady;

      expect(r.key, key);
      expect(r.source, DbKeySource.primarySlot);
      expect(h.memory.values[DbKeyNames.shadow(name)], key.value);
    });

    test('الأساسيّ تالف والظلّ سليم ⇒ يفتح بالظلّ ويصلح الأساسيّ', () async {
      final m = h.manager();
      final key = await m.ensureStoredKey(name);
      await FakeSqlCipherEngine.create(h.db, key);
      await h.memory.write(DbKeyNames.primary(name), 'truncated');

      final r = await h.manager().resolveForOpen(h.db) as DbKeyReady;

      expect(r.key, key);
      expect(r.source, DbKeySource.shadowSlot);
      expect(h.memory.values[DbKeyNames.primary(name)], key.value);
    });
  });

  group('مرشّحو المفتاح القديم (ق-4/ق-7): للفتح فقط', () {
    test('قاعدة قديمة تفتح بالمشتقّ؛ needsMigration بلا أي تغيير على القرص',
        () async {
      await h.createLegacyDb();
      final before = await h.db.readAsBytes();

      final r = await h.manager().resolveForOpen(h.db) as DbKeyReady;

      expect(r.key.kind, DbKeyKind.legacyDerived);
      expect(r.needsMigration, isTrue);
      expect(h.memory.values, isEmpty, reason: 'لا ترحيل تلقائيّ ولا توليد');
      expect(await KeyInfoFile.of(h.db).exists(), isFalse);
      expect(h.sibling('.v2-new').existsSync(), isFalse);
      expect(await h.db.readAsBytes(), before);
    });

    test('قاعدة بالمفتاح الاحتياطيّ القديم تفتح به (قراءة فقط)', () async {
      final fb = 'f' * 64;
      await h.memory.write(DbKeyNames.legacyFallback, fb);
      h.legacyDerived = null;
      await FakeSqlCipherEngine.create(h.db, DbKey(DbKeyKind.legacyFallback, fb));

      final r = await h.manager().resolveForOpen(h.db) as DbKeyReady;
      expect(r.source, DbKeySource.legacyFallback);
      expect(r.needsMigration, isTrue);
    });
  });

  group('ق-8: حساب ويندوز آخر (المفتاح غائب لكنّ keyinfo يقول مرحَّلة)', () {
    late DbKey key;
    late String code;

    setUp(() async {
      await h.createLegacyDb();
      final svc = h.service(processId: 'A');
      final res = await svc.migrate(h.db);
      expect(res.ok, isTrue, reason: res.toString());
      key = (await h.manager().resolveForOpen(h.db) as DbKeyReady).key;
      code = h.memory.values[DbKeyNames.recoveryPending(name)]!;
      // «حسابٌ آخر»: تخزينٌ آمنٌ فارغ ومعرّفُ الجهاز القديم غير متاح.
      h.memory.values.clear();
      h.legacyDerived = null;
    });

    test('Unavailable(keyMissing) مع إمكان الاسترداد؛ لا مفتاح ولا قاعدة جديدة',
        () async {
      final dbBefore = await h.db.readAsBytes();
      final writesBefore = h.flaky.writeCount;

      final r = await h.manager().resolveForOpen(h.db);

      expect(r, isA<DbKeyUnavailable>());
      final u = r as DbKeyUnavailable;
      expect(u.reason, DbKeyUnavailableReason.keyMissing);
      expect(u.canRecoverWithCode, isTrue);
      expect(u.preMigrationCopyAvailable, isTrue);
      expect(h.flaky.writeCount, writesBefore, reason: 'لا توليد');
      expect(h.memory.values, isEmpty);
      expect(await h.db.readAsBytes(), dbBefore, reason: 'القاعدة لم تُمسّ');
    });

    test('رمز استرداد خاطئ لا يعدّل شيئًا', () async {
      final writesBefore = h.flaky.writeCount;
      final r = await h
          .manager()
          .recoverWithCode(h.db, 'AAAA-AAAA-AAAA-AAAA-AAAA-AAAA-AAAA-AAAA');
      expect((r as DbKeyUnavailable).reason,
          DbKeyUnavailableReason.recoveryFailed);
      expect(h.flaky.writeCount, writesBefore);
      expect(h.memory.values, isEmpty);
    });

    test('رمزٌ بصيغة غير صحيحة يُرفض بلا أثر', () async {
      final r = await h.manager().recoverWithCode(h.db, 'not-a-code');
      expect(r, isA<DbKeyUnavailable>());
      expect(h.memory.values, isEmpty);
    });

    test('الرمز الصحيح يفكّ الغلاف ويعيد كتابة الفتحتين ثم يفتح', () async {
      final r = await h.manager().recoverWithCode(h.db, code);
      expect(r, isA<DbKeyReady>());
      expect((r as DbKeyReady).key, key);
      expect(r.source, DbKeySource.recoveryCode);
      expect(h.memory.values[DbKeyNames.primary(name)], key.value);
      expect(h.memory.values[DbKeyNames.shadow(name)], key.value);

      final again = await h.manager().resolveForOpen(h.db);
      expect(again, isA<DbKeyReady>());
    });

    test('الرمز يعمل بحروف صغيرة وبلا فواصل', () async {
      final r = await h
          .manager()
          .recoverWithCode(h.db, code.replaceAll('-', '').toLowerCase());
      expect(r, isA<DbKeyReady>());
    });

    test('غلافٌ تالف في keyinfo ⇒ فشل بلا أثر', () async {
      final f = KeyInfoFile.of(h.db);
      final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      (j['recoveryEnvelope'] as Map)['ct'] = base64.encode(List.filled(32, 1));
      await f.writeAsString(jsonEncode(j));
      final r = await h.manager().recoverWithCode(h.db, code);
      expect(r, isA<DbKeyUnavailable>());
      expect(h.memory.values, isEmpty);
    });

    test('ملفٌّ غائب + keyinfo مرحَّل + لا مفتاح ⇒ لا تثبيت جديد', () async {
      await h.db.delete();
      h.sibling('.pre-v2').deleteSync();
      final writesBefore = h.flaky.writeCount;

      final r = await h.manager().resolveForOpen(h.db);

      expect((r as DbKeyUnavailable).reason,
          DbKeyUnavailableReason.databaseMissingKeyinfoPresent);
      expect(r.canRecoverWithCode, isTrue);
      expect(h.flaky.writeCount, writesBefore);
      expect(h.memory.values, isEmpty);
      expect(h.db.existsSync(), isFalse, reason: 'لا قاعدة فارغة تُنشأ');
    });
  });

  test('ensureStoredKey يعيد استعمال المفتاح المخزَّن ولا يولّد جديدًا', () async {
    final m = h.manager();
    final a = await m.ensureStoredKey(name);
    final b = await h.manager().ensureStoredKey(name);
    expect(b, a);
  });

  test('البصمة: ثابتة 16 hex ومختلفة بين المفاتيح ولا تكشف المفتاح', () {
    final a = DbKey.raw('0' * 64).fingerprint;
    final b = DbKey.raw('1' * 64).fingerprint;
    expect(a, hasLength(16));
    expect(a, isNot(b));
    expect(a, DbKey.raw('0' * 64).fingerprint);
  });

  test('pragmaLiteral: الخام x\'..\' والقديم عبارة نصّيّة مع تعقيم الاقتباس', () {
    expect(DbKey.raw('a' * 64).pragmaLiteral, "\"x'${'a' * 64}'\"");
    expect(const DbKey(DbKeyKind.legacyDerived, 'abc').pragmaLiteral, "'abc'");
    expect(const DbKey(DbKeyKind.passphrase, "a'b").pragmaLiteral, "'a''b'");
    expect(() => DbKey.raw('xyz'), throwsArgumentError);
  });

  test('DbKey.toString لا يطبع قيمة المفتاح', () {
    expect(DbKey.raw('a' * 64).toString(), isNot(contains('a' * 64)));
  });

  test('أسماء التخزين آمنة لاسم ملف ويندوز (بلا ":")', () {
    for (final n in [
      DbKeyNames.primary(name),
      DbKeyNames.shadow(name),
      DbKeyNames.recoveryPending(name),
      DbKeyNames.probe(name),
    ]) {
      expect(n, matches(RegExp(r'^[A-Za-z0-9._-]+$')));
      expect(DbKeyNames.isProtected(n), isTrue);
    }
    expect(DbKeyNames.isProtected(DbKeyNames.legacyFallback), isTrue);
    expect(DbKeyNames.isProtected('ural_lan_install_secret_v1'), isFalse);
  });

  test('رمز الاسترداد المعلَّق يُحذف بعد التأكيد', () async {
    await h.manager().resolveForOpen(h.db);
    final m = h.manager();
    expect(await m.pendingRecoveryCode(name), isNotNull);
    await m.acknowledgeRecoveryCode(name);
    expect(await m.pendingRecoveryCode(name), isNull);
  });
}
