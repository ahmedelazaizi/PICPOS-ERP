// E-01: SecurityService يفوّض المفتاح القديم إلى LegacyDeviceSeed (نتيجة
// حرفيّة)، ولا يولّد مفتاحًا احتياطيًّا لقاعدة موجودة؛ وclearAll يحمي مفاتيح القاعدة.
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/services/db_key_names.dart';
import 'package:picpos_erp/services/legacy_device_seed.dart';
import 'package:picpos_erp/services/secure_storage_service.dart';
import 'package:picpos_erp/services/security_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Future<String?> Function() originalProvider;
  setUp(() {
    originalProvider = LegacyDeviceSeed.deviceIdProvider;
    FlutterSecureStorage.setMockInitialValues({});
  });
  tearDown(() => LegacyDeviceSeed.deviceIdProvider = originalProvider);

  const storage = FlutterSecureStorage();

  group('getDatabaseEncryptionKey', () {
    test('ذهبي: المشتقّ القديم حرفيًّا sha256("ABC:UralCash_Security_Pepper_v2")',
        () async {
      LegacyDeviceSeed.deviceIdProvider = () async => 'ABC';
      final expected = sha256
          .convert(utf8.encode('ABC:UralCash_Security_Pepper_v2'))
          .toString();
      expect(await SecurityService.getDatabaseEncryptionKey(), expected);
      expect(
          await SecurityService.getDatabaseEncryptionKey(databaseExists: false),
          expected);
    });

    test('المشتقّ يُرجَّح على الاحتياطيّ المخزَّن', () async {
      FlutterSecureStorage.setMockInitialValues(
          {DbKeyNames.legacyFallback: 'f' * 64});
      LegacyDeviceSeed.deviceIdProvider = () async => 'ABC';
      expect(await SecurityService.getDatabaseEncryptionKey(),
          LegacyDeviceSeed.deriveFor('ABC'));
    });

    test('بلا معرّف جهاز + احتياطيّ مخزَّن ⇒ يُعاد كما هو', () async {
      FlutterSecureStorage.setMockInitialValues(
          {DbKeyNames.legacyFallback: 'f' * 64});
      LegacyDeviceSeed.deviceIdProvider = () async => null;
      expect(await SecurityService.getDatabaseEncryptionKey(), 'f' * 64);
    });

    test('العيب القديم: استثناء عابر من device_info + قاعدة موجودة + لا احتياطيّ '
        '⇒ رمي ولا توليد', () async {
      LegacyDeviceSeed.deviceIdProvider = () async => throw StateError('transient');

      await expectLater(SecurityService.getDatabaseEncryptionKey(),
          throwsA(isA<DatabaseKeyUnavailableException>()));
      await expectLater(
          SecurityService.getDatabaseEncryptionKey(databaseExists: true),
          throwsA(isA<DatabaseKeyUnavailableException>()));

      expect(await storage.read(key: DbKeyNames.legacyFallback), isNull,
          reason: 'لم يُكتب أيّ مفتاح احتياطيّ جديد');
    });

    test('احتياطيّ قصير/تالف + قاعدة موجودة ⇒ رمي ولا استبدال', () async {
      FlutterSecureStorage.setMockInitialValues(
          {DbKeyNames.legacyFallback: 'short'});
      LegacyDeviceSeed.deviceIdProvider = () async => null;
      await expectLater(SecurityService.getDatabaseEncryptionKey(),
          throwsA(isA<DatabaseKeyUnavailableException>()));
      expect(await storage.read(key: DbKeyNames.legacyFallback), 'short');
    });

    test('تثبيت جديد (لا ملف قاعدة) بلا معرّف جهاز ⇒ يولّد احتياطيًّا 64 hex '
        'ويثبت', () async {
      LegacyDeviceSeed.deviceIdProvider = () async => null;
      final k1 =
          await SecurityService.getDatabaseEncryptionKey(databaseExists: false);
      expect(k1, matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(await storage.read(key: DbKeyNames.legacyFallback), k1);
      // ثمّ الملف موجود: يقرأ نفس المفتاح.
      expect(await SecurityService.getDatabaseEncryptionKey(), k1);
    });
  });

  group('SecureStorageService.clearAll', () {
    test('يمحو الأسرار الأخرى ولا يمحو مفاتيح القاعدة', () async {
      FlutterSecureStorage.setMockInitialValues({
        DbKeyNames.primary('picpos_unified.db'): 'p' * 64,
        DbKeyNames.shadow('picpos_unified.db'): 's' * 64,
        DbKeyNames.recoveryPending('picpos_unified.db'): 'CODE',
        DbKeyNames.legacyFallback: 'f' * 64,
        'ural_lan_install_secret_v1': 'secret',
        'e_invoice_secret_x': 'y',
      });

      await SecureStorageService().clearAll();

      final left = await storage.readAll();
      expect(left.keys.toSet(), {
        DbKeyNames.primary('picpos_unified.db'),
        DbKeyNames.shadow('picpos_unified.db'),
        DbKeyNames.recoveryPending('picpos_unified.db'),
        DbKeyNames.legacyFallback,
      });
    });

    test('لا استدعاء .deleteAll( في lib/ (يغلق T15)', () {
      // حارسٌ نصّيّ: لا مسار يمحو التخزين كلَّه.
      final offenders = <String>[];
      for (final e in Directory('lib').listSync(recursive: true)) {
        if (e is! File || !e.path.endsWith('.dart')) continue;
        if (RegExp(r'\.deleteAll\(').hasMatch(e.readAsStringSync())) {
          offenders.add(e.path);
        }
      }
      expect(offenders, isEmpty);
    });
  });
}
