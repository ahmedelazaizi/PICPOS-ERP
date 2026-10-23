// ═══════════════════════════════════════════════════════════════════════════
// البند ١‑٧ (بقيّتُه) — كلمتا المدير والمطوّر تنتقلان إلى Argon2id
// ═══════════════════════════════════════════════════════════════════════════
//
// الهاشان كانا سلسلةَ SHA‑256 مكرَّرةً — الملحُ يدخل الدورةَ الأولى وحدَها —
// رغم أنّ التعليقَ كان يسمّيها PBKDF2. وكلمةُ المدير هي بوّابةُ تجاوزِ
// الصلاحيّات كلِّها، وكلمةُ المطوّر تحرس نمطَ العمل وأوضاعَ النشر.
//
// ── ما يقيسه هذا الملفّ (وما لا يقيسه) ────────────────────────────────────
//
// ليس «هل Argon2 أقوى» — ذاك مفروغٌ منه. بل الأربعةُ التي **تكسر تنصيبةً
// حقيقيّةً** لو أُخطئ في الترقية:
//
//   ١. الهاشُ الجديد Argon2id فعلاً (وإلّا فالترقيةُ اسمٌ بلا أثر).
//   ٢. الهاشُ **القديم** ما زال يُقبَل — وإلّا لانكسر كلُّ تنصيبٍ قائم.
//   ٣. بعد أوّلِ قبولٍ يُعاد السكُّ Argon2id، والملحُ يُفرَّغ.
//   ٤. 🔴 **وبعد التفريغ ما زال التحقّقُ يعمل.** هذه مصيدةُ الترقية:
//      `_verifyInner` كان يشترط `salt.isNotEmpty`، وArgon2id يُفرغ الملح —
//      فلولا إرخاءُ الشرط لرفض كلَّ كلمةٍ **صحيحة** بعد أوّلِ إعادةِ سكّ،
//      ولقال `isConfigured` في خدمة المطوّر «لا كلمةَ مضبوطة» على كلِّ
//      تنصيبةٍ مرقّاة فيُقفَل بابُ السنة المالية إقفالاً تامّاً.
//
// وكلُّ توكيدٍ هنا يقارن **قيمةً محسوبةً** لا «> صفر»: نصفُ إصلاحٍ يُنتج
// «صحيح» من الفرع القديم فيمرُّ صامتاً.

import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/data/repositories/settings_repository_cached.dart';
import 'package:picpos_erp/services/admin_password_service.dart';
import 'package:picpos_erp/services/api/server_login_throttle.dart';
import 'package:picpos_erp/services/developer_auth_service.dart';
import 'package:picpos_erp/services/security_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late SettingsRepositoryCached settings;

  setUp(() {
    db = AppDatabase.forTesting();
    settings = SettingsRepositoryCached(db);
    ServerLoginThrottle.reset();
  });

  // ⚠️ لا `db.close()`: مؤقّتُ drift ينتظر في المنطقة الوهميّة فتتعلّق
  //    السويّة. التخلّصُ من المرجع يكفي في اختبارِ وحدة.
  tearDown(ServerLoginThrottle.reset);

  group('كلمةُ مرور المدير — AdminPasswordService', () {
    test('الإنشاءُ يُخرج Argon2id لا سلسلةَ SHA-256', () async {
      final svc = AdminPasswordService(settings);
      await svc.setPassword('s3cret-manager');

      final hash = settings.get('admin_password_hash');
      expect(hash, isNotNull);
      expect(SecurityService.isArgon2Hash(hash!), isTrue,
          reason: 'الإنشاء ما زال على الـKDF الرخيص');

      // والملحُ القديمُ فُرِّغ: `remove` تكتب سلسلةً فارغةً بالتصميم.
      expect(settings.get('admin_password_salt'), isEmpty,
          reason: 'عمودُ ملحٍ باقٍ يُوهم قارئاً لاحقاً بأنّه ذو معنى');
    });

    test('التحقّقُ يقبل الصحيحةَ ويرفض الخاطئة', () async {
      final svc = AdminPasswordService(settings);
      await svc.setPassword('s3cret-manager');

      expect(await svc.verify('s3cret-manager'), isTrue);
      ServerLoginThrottle.reset();
      expect(await svc.verify('s3cret-manageR'), isFalse);
    });

    test('الهاشُ القديمُ (PBKDF2) ما زال يُقبَل — لا تنصيبةَ تنكسر', () async {
      // نزرع تنصيبةً قديمةً حرفيّاً: نفسُ ما كان `setPassword` يكتبه.
      final salt = SecurityService.generateSalt();
      final legacyHash = SecurityService.hashPassword('old-pass', salt);
      await settings.save('admin_password_salt', salt);
      await settings.save('admin_password_hash', legacyHash);

      expect(SecurityService.isArgon2Hash(legacyHash), isFalse,
          reason: 'ضابطٌ: البذرةُ يجب أن تكون بالصيغة القديمة');

      final svc = AdminPasswordService(settings);
      expect(await svc.verify('old-pass'), isTrue,
          reason: 'ترقيةٌ ترفض الهاشَ القديم تقفل كلَّ تنصيبةٍ قائمة');
    });

    test('بعد قبولِ القديم يُعاد السكُّ Argon2id ويُفرَّغ الملح', () async {
      final salt = SecurityService.generateSalt();
      await settings.save('admin_password_salt', salt);
      await settings.save(
          'admin_password_hash', SecurityService.hashPassword('old-pass', salt));

      final svc = AdminPasswordService(settings);
      await svc.verify('old-pass');

      final upgraded = settings.get('admin_password_hash')!;
      expect(SecurityService.isArgon2Hash(upgraded), isTrue,
          reason: 'إعادةُ السكّ لم تقع — الهاشُ الرخيص باقٍ على القرص');
      expect(settings.get('admin_password_salt'), isEmpty);
    });

    test('🔴 وبعد تفريغِ الملح ما زال التحقّقُ يعمل (مصيدةُ الترقية)', () async {
      final salt = SecurityService.generateSalt();
      await settings.save('admin_password_salt', salt);
      await settings.save(
          'admin_password_hash', SecurityService.hashPassword('old-pass', salt));

      final svc = AdminPasswordService(settings);
      expect(await svc.verify('old-pass'), isTrue); // يُرقّي ويُفرغ الملح
      ServerLoginThrottle.reset();

      // نفسُ الكلمة، والملحُ الآن فارغ. لو عاد شرطُ `salt.isNotEmpty`
      // لسقط هذا وحدَه — وهو عينُ ما يراه المستخدمُ: كلمةٌ صحيحةٌ تُرفَض.
      expect(settings.get('admin_password_salt'), isEmpty,
          reason: 'ضابطٌ: الملحُ يجب أن يكون فارغاً هنا');
      expect(await svc.verify('old-pass'), isTrue,
          reason: 'اشتراطُ الملح يرفض كلَّ كلمةٍ صحيحةٍ بعد إعادة السكّ');
    });

    test('حدُّ المحاولات يقفل بعد خمسٍ، فتُرفَض الصحيحةُ نفسُها', () async {
      final svc = AdminPasswordService(settings);
      await svc.setPassword('s3cret-manager');

      for (var i = 0; i < ServerLoginThrottle.maxAttempts; i++) {
        expect(await svc.verify('wrong'), isFalse);
      }
      expect(AdminPasswordService.isLockedOut, isTrue);
      expect(await svc.verify('s3cret-manager'), isFalse,
          reason: 'القفلُ يجب أن يسبق التحقّق، وإلّا فهو حدٌّ بلا أثر');
    });
  });

  group('كلمةُ مرور المطوّر — DeveloperAuthService', () {
    test('الإنشاءُ Argon2id، و`isConfigured` صادقةٌ رغمَ فراغِ الملح', () async {
      final svc = DeveloperAuthService(settings);
      await svc.setPassword('dev-pass');

      expect(
          SecurityService.isArgon2Hash(
              settings.get('developer_password_hash')!),
          isTrue);
      expect(settings.get('developer_password_salt'), isEmpty);

      // 🔴 بوّابتا السنة المالية تفحصان `isConfigured` **قبل** `verify`،
      //    وترفضان بـ«لم تُعَدّ كلمةُ مرور المطوّر». فاشتراطُ الملح هنا
      //    كان يُقفل البابَ على كلِّ تنصيبةٍ مرقّاة.
      expect(svc.isConfigured, isTrue,
          reason: 'اشتراطُ الملح يجعل كلَّ تنصيبةٍ تبدو بلا كلمةِ مطوّر');
      expect(await svc.verify('dev-pass'), isTrue);
    });

    test('الهاشُ القديمُ يُقبَل ثمّ يُرقّى', () async {
      final salt = SecurityService.generateSalt();
      await settings.save('developer_password_salt', salt);
      await settings.save('developer_password_hash',
          SecurityService.hashPassword('dev-old', salt));

      final svc = DeveloperAuthService(settings);
      expect(await svc.verify('dev-old'), isTrue);
      expect(
          SecurityService.isArgon2Hash(
              settings.get('developer_password_hash')!),
          isTrue,
          reason: 'إعادةُ السكّ لم تقع');

      ServerLoginThrottle.reset();
      expect(await svc.verify('dev-old'), isTrue,
          reason: 'التحقّقُ انكسر بعد إعادة السكّ');
    });

    test('حدُّ المحاولات — كان غائباً تماماً عن هذه الخدمة', () async {
      final svc = DeveloperAuthService(settings);
      await svc.setPassword('dev-pass');

      for (var i = 0; i < ServerLoginThrottle.maxAttempts; i++) {
        expect(await svc.verify('wrong'), isFalse);
      }
      expect(DeveloperAuthService.isLockedOut, isTrue,
          reason: 'بلا حدٍّ تُجرَّب آلافُ الكلمات على الجهاز نفسِه');
      expect(await svc.verify('dev-pass'), isFalse);
    });

    test('مفتاحُ الحدِّ منفصلٌ عن مفتاحِ المدير', () async {
      // وإلّا لأقفل خطأٌ في إحداهما البابَ الآخر — أو الأسوأ: لفتحَه.
      expect(DeveloperAuthService.throttleKey,
          isNot(equals(AdminPasswordService.throttleKey)));

      final admin = AdminPasswordService(settings);
      await admin.setPassword('s3cret-manager');
      for (var i = 0; i < ServerLoginThrottle.maxAttempts; i++) {
        await admin.verify('wrong');
      }
      expect(AdminPasswordService.isLockedOut, isTrue);
      expect(DeveloperAuthService.isLockedOut, isFalse,
          reason: 'قفلُ المدير امتدّ إلى المطوّر — المفتاحان مشتركان');
    });
  });

  group('صفرُ بقايا من الـKDF القديم', () {
    test('`hashPassword` باقيةٌ للتحقّقِ من القديم لا للإنشاء', () {
      // الدالّةُ نفسُها يجب أن تبقى — `verifyPasswordFull` تحتاجها لفرعِ
      // الصيغة القديمة. الممنوعُ هو **الإنشاءُ** بها، وذاك يحرسه
      // `test/structural/no_legacy_password_kdf_test.dart`.
      final salt = SecurityService.generateSalt();
      expect(SecurityService.hashPassword('x', salt), isNotEmpty);
    });
  });
}
