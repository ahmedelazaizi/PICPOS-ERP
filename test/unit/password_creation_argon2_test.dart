// ═══════════════════════════════════════════════════════════════════════════
// إنشاء كلمات المرور لازم يكون Argon2id — مش التحقق بس
// ═══════════════════════════════════════════════════════════════════════════
//
// ترقية الأسبوع الثامن ضافت Argon2id للتحقق (`verifyPasswordFull`) وإعادة
// التجزئة الشفافة عند أول دخول ناجح. لكن **الإنشاء** فضل PBKDF2-SHA256، فأي
// تنصيب جديد بيطلع بكل كلمات مروره بالـKDF الرخيص لحد ما كل مستخدم يدخل مرة.
//
// وده مهم هنا بالذات لأن `GET /api/users` بيبعت `passwordHash` **و**
// `passwordSalt` مع بعض لكل حامل bearer على الشبكة المحلية — بالتصميم، عشان
// العميل يقدر يصادق محلياً وهو offline. الملح مع الهاش + KDF رخيص = كسر offline.
//
// الحارس البنيوي في test/structural/no_legacy_password_kdf_test.dart بيمنع أي
// نداء جديد؛ الملف ده بيثبّت السلوك الفعلي على أهم مسارين.

import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/services/security_service.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting());
  tearDown(() => db.close());

  group('زرع المدير الافتراضي', () {
    test('كلمة مرور المدير المزروعة Argon2id مش PBKDF2', () async {
      final admin = await (db.select(db.users)
            ..where((u) => u.username.equals('admin')))
          .getSingle();

      expect(SecurityService.isArgon2Hash(admin.passwordHash), isTrue,
          reason: 'التنصيب الجديد بيطلع بالـKDF الرخيص');
    });

    test('الملح المخزَّن مش هو ملح كلمة المرور بعد الترقية', () async {
      final admin = await (db.select(db.users)
            ..where((u) => u.username.equals('admin')))
          .getSingle();

      // سلسلة PHC بتحمل ملحها العشوائي جوّاها، فعمود `passwordSalt` بقى
      // بلا معنى للصفوف الجديدة — وده المقصود: الملح اللي بيتسرّب على
      // الشبكة مبقاش بيفتح أي باب.
      expect(
        SecurityService.hashPassword('admin', admin.passwordSalt),
        isNot(equals(admin.passwordHash)),
        reason: 'الهاش لسه قابل لإعادة الإنتاج من الملح المكشوف',
      );
    });

    test('admin/admin لسه بيصادق بعد الترقية', () async {
      // ⚠️ الضابط الحاكم: لو الترقية كسرت الدخول الافتراضي، التنصيب
      //    الجديد مش هيقدر يدخل أصلاً — أخطر من الثغرة نفسها.
      final user = await db.getUserByEmailAndPassword('admin', 'admin');
      expect(user, isNotNull, reason: 'الدخول الافتراضي اتكسر');
      expect(user!.username, 'admin');
    });

    test('كلمة مرور غلط بترفض', () async {
      expect(await db.getUserByEmailAndPassword('admin', 'wrong-password'), isNull);
    });
  });

  group('التوافق مع الهاش القديم محفوظ', () {
    test('هاش PBKDF2 قديم لسه بيتحقق ويترقّى عند الدخول', () async {
      // ماحدش عنده بيانات قديمة في الميدان، لكن مسار التحقق ده هو نفسه
      // اللي بيخدم الهاشات اللي بتوصل عبر المزامنة من خادم أقدم.
      const salt = 'LEGACY_SALT';
      final legacyHash = SecurityService.hashPassword('s3cret', salt);

      final result = await SecurityService.verifyPasswordFull(
        's3cret',
        salt,
        legacyHash,
      );

      expect(result.verified, isTrue);
      expect(result.needsRehash, isTrue,
          reason: 'الهاش القديم لازم يتعلّم للترقية');
    });
  });
}
