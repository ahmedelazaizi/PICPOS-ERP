// ═══════════════════════════════════════════════════════════════════════════
// مانعُ Go ١‑٧ — كلمةُ مرور المدير: لا تُقرأ، ولا تُكتَب عن بُعد، ولا تُخمَّن
// ═══════════════════════════════════════════════════════════════════════════
//
// هذه الكلمةُ هي بوّابةُ **تجاوزِ الصلاحيّات كلِّه**: إغلاقُ الوردية، وتعديلُ
// فاتورةٍ مقفلة، وتصعيدُ المسؤول، وفكُّ شاشة القفل. وكانت مكشوفةً من ثلاثة
// أبوابٍ في وقتٍ واحد:
//
//   ١) `GET /api/settings` كان **يُفرغ جدولَ الإعدادات كاملاً** بلا بوّابةِ
//      صلاحيّةٍ — ومن صفوفه `admin_password_hash` و`admin_password_salt`.
//   ٢) `POST /api/settings` كان يكتب أيَّ مفتاح، فمن يملك `settings_edit`
//      يستبدل الكلمةَ عن بُعد ⇒ تصعيدُ امتيازٍ كامل.
//   ٣) لا حدَّ لمحاولات التخمين إطلاقاً على أيٍّ من عشرة مواضعَ تناديها.
//
// وقائمةُ المنع الموجودةُ (`isDeviceLocalSettingKey`) **لا تغطّيها**: تلك
// محورُ «يخصُّ هذا الجهاز» لا محورُ «سرّ».

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/services/api/api_handler.dart';
import 'package:ural_erp/services/api/api_user_context.dart';
import 'package:ural_erp/services/api/server_login_throttle.dart';
import 'package:ural_erp/services/admin_password_service.dart';
import 'package:ural_erp/data/repositories/settings_repository_cached.dart';
import 'package:ural_erp/services/sync/strategies/setting_sync_strategy.dart';

void main() {
  group('١‑٧ — الأسرارُ لا تخرج ولا تُكتَب عبر الـAPI', () {
    late AppDatabase db;
    late ApiHandler handler;

    setUp(() async {
      db = AppDatabase.forTesting();
      handler = ApiHandler(db);
      // اعتمادٌ مخزَّنٌ كما في أيِّ تنصيبةٍ حقيقيّة.
      await db.setSetting('admin_password_hash', 'HASH-SECRET');
      await db.setSetting('admin_password_salt', 'SALT-SECRET');
      await db.setSetting('developer_password_hash', 'DEV-HASH');
      await db.setSetting('company_name', 'شركةُ الاختبار');
    });

    tearDown(() async => db.close());

    Future<Map<String, dynamic>> getSettings() async {
      final resp = await handler.buildRouter().call(
            shelf.Request('GET', Uri.parse('http://localhost/api/settings')),
          );
      expect(resp.statusCode, 200);
      final body = jsonDecode(await resp.readAsString()) as Map<String, dynamic>;
      return (body['settings'] as Map).cast<String, dynamic>();
    }

    test('GET /api/settings يسلّم الإعداداتِ العادّيّةَ ولا يسلّم الأسرار',
        () async {
      final settings = await getSettings();

      // مرساةٌ: المسارُ يعمل ويُرجع إعداداتٍ فعلاً — بدونها يمرّ النفيُ
      // أدناه لأنّ الاستجابةَ فارغةٌ لا لأنّ الترشيحَ يعمل.
      expect(settings['company_name'], 'شركةُ الاختبار');

      // 🔴 المعطوب: كلُّها كانت تخرج لأيِّ حاملِ توكن LAN.
      expect(settings.containsKey('admin_password_hash'), isFalse);
      expect(settings.containsKey('admin_password_salt'), isFalse);
      expect(settings.containsKey('developer_password_hash'), isFalse);
    });

    test('POST /api/settings يكتب المسموحَ ويحجب كلمةَ مرور المدير', () async {
      final resp = await handler.buildRouter().call(
            shelf.Request(
              'POST',
              Uri.parse('http://localhost/api/settings'),
              body: jsonEncode({
                'company_name': 'اسمٌ جديد',
                'admin_password_hash': 'ATTACKER-HASH',
                'admin_password_salt': 'ATTACKER-SALT',
              }),
              // هويّةُ المدير الأساسيّ — أوسعُ ما يمكن أن يحمله مستدعٍ.
              context: {ApiUserCtx.userIdKey: 1},
            ),
          );
      expect(resp.statusCode, 200);
      final body = jsonDecode(await resp.readAsString()) as Map;
      expect((body['blocked'] as List?)?.length, 2,
          reason: 'المفتاحان السرّيّان يُبلَّغ عنهما');

      // 🔴 المعطوب: الهاشُ يُستبدَل عن بُعد ⇒ تجاوزُ الصلاحيّات كلِّه لمن
      //    يعرف الكلمةَ الجديدة.
      expect(await db.getSettingValue('admin_password_hash'), 'HASH-SECRET',
          reason: 'كلمةُ مرور المدير لا تُكتَب من الشبكة');
      expect(await db.getSettingValue('admin_password_salt'), 'SALT-SECRET');
      // والمسموحُ كُتب — الحجبُ انتقائيٌّ لا رفضٌ للطلب كلِّه.
      expect(await db.getSettingValue('company_name'), 'اسمٌ جديد');
    });

    test('محورا المنع منفصلان — والسرُّ ليس «إعداداً محلّيّاً»', () {
      // انحدارٌ على الخلط الذي كان سيقع لو حُشرت الأسرارُ في قائمة الجهاز:
      // تلك تمنع المزامنةَ أيضاً، وهو قرارٌ تشغيليٌّ آخر.
      expect(isServerSecretSettingKey('admin_password_hash'), isTrue);
      expect(isDeviceLocalSettingKey('admin_password_hash'), isFalse,
          reason: 'ليست إعداداً يخصُّ الجهاز');
      expect(isDeviceLocalSettingKey('network_mode'), isTrue);
      expect(isServerSecretSettingKey('network_mode'), isFalse);
    });
  });

  group('١‑٧ — حدُّ محاولات كلمة مرور المدير', () {
    late AppDatabase db;
    late AdminPasswordService svc;

    setUp(() async {
      ServerLoginThrottle.reset();
      db = AppDatabase.forTesting();
      final repo = SettingsRepositoryCached(db);
      await repo.preload(const ['admin_password_hash', 'admin_password_salt']);
      svc = AdminPasswordService(repo);
      await svc.setPassword('correct-horse');
    });

    tearDown(() async {
      ServerLoginThrottle.reset();
      await db.close();
    });

    test('الكلمةُ الصحيحةُ تمرّ، والخاطئةُ لا', () {
      expect(svc.verify('correct-horse'), isTrue, reason: 'مرساة');
      expect(svc.verify('wrong'), isFalse);
    });

    test('خمسُ محاولاتٍ خاطئةٍ تقفل — وحتّى الصحيحةُ تُرفَض بعدها', () {
      for (var i = 0; i < 5; i++) {
        expect(svc.verify('wrong-$i'), isFalse);
      }
      expect(AdminPasswordService.isLockedOut, isTrue,
          reason: '🔴 المعطوب: لا قفلَ إطلاقاً — آلافُ المحاولات في الدقيقة');
      expect(svc.verify('correct-horse'), isFalse,
          reason: 'القفلُ يسبق الفحص، وإلّا لم يكن قفلاً');
    });

    test('نجاحٌ قبل بلوغ الحدِّ يصفّر العدّاد', () {
      expect(svc.verify('wrong'), isFalse);
      expect(svc.verify('wrong'), isFalse);
      expect(svc.verify('correct-horse'), isTrue);
      // العدّادُ صُفِّر، فأربعُ محاولاتٍ بعده لا تقفل.
      for (var i = 0; i < 4; i++) {
        expect(svc.verify('wrong-$i'), isFalse);
      }
      expect(AdminPasswordService.isLockedOut, isFalse);
    });
  });
}
