// E-01 المرحلة ب: رمز الاسترداد (160-بت) + الغلاف + التصدير المحمول.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/services/db_key_portable_export.dart';
import 'package:ural_erp/services/db_key_recovery.dart';
import 'package:ural_erp/services/db_key_types.dart';
import 'package:ural_erp/services/db_keyinfo_file.dart';

import '../helpers/db_key_harness.dart';

void main() {
  // ignore: prefer_const_declarations
  final keyHex = '0123456789abcdef' * 4;

  group('RecoveryCode', () {
    test('32 حرف Base32 (160-بت) في 8 مجموعات من 4', () {
      final c = RecoveryCode.generate();
      expect(c, matches(RegExp(r'^([A-Z2-7]{4}-){7}[A-Z2-7]{4}$')));
    });

    test('غير متكرّر', () {
      expect({for (var i = 0; i < 20; i++) RecoveryCode.generate()}, hasLength(20));
    });

    test('normalize يقبل الصغير والمسافات والفواصل ويرفض الباقي', () {
      final c = RecoveryCode.generate();
      expect(RecoveryCode.normalize(c.toLowerCase().replaceAll('-', ' ')),
          c.replaceAll('-', ''));
      expect(() => RecoveryCode.normalize('ABC'), throwsFormatException);
      expect(() => RecoveryCode.normalize('1' * 32), throwsFormatException);
    });
  });

  group('RecoveryEnvelope', () {
    test('تغليف ثم فك يعيد نفس المفتاح', () async {
      final code = RecoveryCode.generate();
      final env = await RecoveryEnvelope.wrap(keyHex, code);
      expect(env['kdf'], 'argon2id');
      expect(env.toString(), isNot(contains(keyHex)));
      expect(await RecoveryEnvelope.unwrap(env, code), keyHex);
    });

    test('رمز خاطئ ⇒ RecoveryCodeException', () async {
      final env = await RecoveryEnvelope.wrap(keyHex, RecoveryCode.generate(),
          memoryKb: 64, iterations: 1);
      await expectLater(
        RecoveryEnvelope.unwrap(env, RecoveryCode.generate()),
        throwsA(isA<RecoveryCodeException>()),
      );
    });

    test('صيغة رمز خاطئة ⇒ RecoveryCodeException', () async {
      final env = await RecoveryEnvelope.wrap(keyHex, RecoveryCode.generate(),
          memoryKb: 64, iterations: 1);
      await expectLater(RecoveryEnvelope.unwrap(env, 'xx'),
          throwsA(isA<RecoveryCodeException>()));
    });

    test('غلاف معبوث به (تغيير ct/mac/salt) ⇒ RecoveryCodeException', () async {
      final code = RecoveryCode.generate();
      for (final field in ['ct', 'mac', 'salt', 'nonce']) {
        final env = await RecoveryEnvelope.wrap(keyHex, code,
            memoryKb: 64, iterations: 1);
        env[field] = 'AAAAAAAAAAAAAAAAAAAAAA==';
        await expectLater(RecoveryEnvelope.unwrap(env, code),
            throwsA(isA<RecoveryCodeException>()),
            reason: field);
      }
    });

    test('غلاف ناقص الحقول ⇒ RecoveryCodeException (لا استثناء خام)', () async {
      await expectLater(
        RecoveryEnvelope.unwrap({'v': 1, 'kdf': 'argon2id'}, RecoveryCode.generate()),
        throwsA(isA<RecoveryCodeException>()),
      );
    });

    test('مفتاح بشكل خاطئ يُرفض عند التغليف', () async {
      await expectLater(RecoveryEnvelope.wrap('zz', RecoveryCode.generate()),
          throwsArgumentError);
    });

    test('ملحٌّ جديد في كلّ تغليف (نفس المفتاح والرمز ⇒ غلاف مختلف)', () async {
      final code = RecoveryCode.generate();
      final a = await RecoveryEnvelope.wrap(keyHex, code, memoryKb: 64, iterations: 1);
      final b = await RecoveryEnvelope.wrap(keyHex, code, memoryKb: 64, iterations: 1);
      expect(a['ct'], isNot(b['ct']));
    });
  });

  group('PortableExport', () {
    late DbKeyHarness h;
    setUp(() => h = DbKeyHarness());
    tearDown(() => h.dispose());

    test('يصدّر بكلمة مرور ويحفظ user_version؛ يُفتح بالكلمة لا بالمفتاح',
        () async {
      await h.createLegacyDb(tables: {'a': 2}, userVersion: 9);
      final out = File('${h.dir.path}${Platform.pathSeparator}portable.db');
      const pw = 'correct horse battery';

      await PortableExport(h.engine).export(
          src: h.db, srcKey: h.legacyKey, out: out, password: pw);

      const pk = DbKey(DbKeyKind.passphrase, pw);
      expect(await h.engine.canOpen(out, pk), isTrue);
      expect(await h.engine.canOpen(out, h.legacyKey), isFalse);
      expect((await h.engine.inspect(out, pk)).userVersion, 9);
      final info = (await KeyInfoFile.read(out))!;
      expect(info.kind, DbKeyKind.passphrase);
      expect(info.fingerprint, isNull);
    });

    test('كلمة قصيرة تُرفض ولا يُكتب ملف', () async {
      await h.createLegacyDb();
      final out = File('${h.dir.path}${Platform.pathSeparator}p.db');
      await expectLater(
        PortableExport(h.engine).export(
            src: h.db, srcKey: h.legacyKey, out: out, password: 'short'),
        throwsA(isA<PortableExportException>()),
      );
      expect(out.existsSync(), isFalse);
    });

    test('فشل التحقق يحذف الملف الناتج', () async {
      await h.createLegacyDb();
      h.engine.tamper = 'dropRows';
      final out = File('${h.dir.path}${Platform.pathSeparator}p.db');
      await expectLater(
        PortableExport(h.engine).export(
            src: h.db,
            srcKey: h.legacyKey,
            out: out,
            password: 'a-long-enough-password'),
        throwsA(isA<PortableExportException>()),
      );
      expect(out.existsSync(), isFalse);
    });

    test('الوجهة = المصدر تُرفض', () async {
      await h.createLegacyDb();
      await expectLater(
        PortableExport(h.engine).export(
            src: h.db,
            srcKey: h.legacyKey,
            out: h.db,
            password: 'a-long-enough-password'),
        throwsA(isA<PortableExportException>()),
      );
      expect(await h.engine.canOpen(h.db, h.legacyKey), isTrue);
    });
  });
}
