// مستندٌ جديدٌ من العميل إلى الخادم — **خمسةُ مواضعَ لا أربعة** (§٨، خطوة د).
//
// ═══ 🔴 لماذا يُحرَس العدد ═══
//
// لا دفعَ دلتا عامٌّ في هذا المستودع: الكتابةُ **مستندٌ صريح**. فمرفقٌ
// يُرفَع على عميلٍ يمرّ بخمسةٍ مرتَّبة:
//
//   ١) `cwi_sync.dart`               — الطابورُ والحمولة
//   ٢) `client_write_interceptor`     — المُمرِّرُ الساكن
//   ٣) `server_proxy.dart`            — النداءُ الشبكيّ
//   ٤) `offline_sync_worker.dart`     — إعادةُ التشغيل بعد انقطاع
//   ٥) `api_handler` + `api_data_handler` — المسارُ والمُعالِج
//
// ⚠️ **وسقوطُ الرابعِ وحدَه لا يُسقط اختبارَ سلوكٍ واحد**: كلُّ شيءٍ يعمل
// على شبكةٍ سليمة، ويضيع المرفقُ **حين تنقطع** — أي في الحالة التي وُجد
// الطابورُ من أجلها بالضبط. ولذلك يُحرَس بنيويّاً لا سلوكيّاً.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import '../helpers/api_handler_source.dart';
import '../helpers/library_source.dart';
import '../helpers/api_data_handler_source.dart';

String _read(String p) =>
    p == 'lib/services/api/api_handler.dart' ? readApiHandlerSource() : readLibrarySource(p);

/// نصٌّ بلا أسطر التعليق — فذكرُ الاسم في شرحٍ ليس توصيلاً.
String _code(String raw) => [
      for (final line in raw.split('\n'))
        if (!line.trimLeft().startsWith('//')) line,
    ].join('\n');

void main() {
  late Map<String, String> src;

  setUpAll(() {
    src = {
      for (final p in const [
        'lib/services/interceptor/cwi_sync_foundation.dart',
        'lib/services/interceptor/cwi_core.dart',
        'lib/services/server_proxy.dart',
        'lib/services/offline_sync_worker.dart',
        'lib/services/api/api_handler.dart',
        'lib/services/api/api_data_handler.dart',
        'lib/data/repositories/attachments_repository_impl.dart',
        'lib/domain/models/attachment_policy.dart',
      ])
        p: _code(p == 'lib/services/api/api_data_handler.dart'
            ? readApiDataHandlerSource()
            : _read(p)),
    };
  });

  group('حراسةُ الحارس', () {
    test('الملفّاتُ الثمانيةُ قُرئت غيرَ فارغة', () {
      for (final e in src.entries) {
        expect(e.value.length, greaterThan(200),
            reason: '«${e.key}» قُرئ فارغاً ⇒ الحارسُ يقيس لا شيء.');
      }
    });

    test('ومرساةٌ موجبة — مستندُ مخطَّط القاعة موصولٌ في الخمسة', () {
      // لو انكسر الكشفُ لسقطت هذه أوّلاً، لا أن يمرّ المرفقُ أخضرَ بلا
      // توصيل.
      expect(src['lib/services/interceptor/cwi_sync_foundation.dart'],
          contains('submitFloorPlan'));
      expect(src['lib/services/server_proxy.dart'],
          contains("post('/api/floor-plan'"));
      expect(src['lib/services/offline_sync_worker.dart'],
          contains("case 'floor_plan_items':"));
    });
  });

  group('🔴 المواضعُ الخمسة', () {
    test('١ — `_CwiSync` يطابور الرفعَ والحذف باسم الجدول', () {
      final s = src['lib/services/interceptor/cwi_sync_foundation.dart']!;
      expect(s, contains('static Future<void> submitAttachment('));
      expect(s, contains('static Future<void> submitAttachmentDelete('));
      expect(s, contains("tableName: 'attachments'"));
      expect(s, contains("operation: 'insert'"));
      expect(s, contains("operation: 'delete'"));
    });

    test('٢ — والمُمرِّرُ الساكنُ موجود', () {
      final s = src['lib/services/interceptor/cwi_core.dart']!;
      expect(s, contains('_CwiSyncFoundation.submitAttachment(document)'));
      expect(s, contains('_CwiSyncFoundation.submitAttachmentDelete(document)'));
    });

    test('٣ — والنداءاتُ الثلاثةُ في الوكيل', () {
      final s = src['lib/services/server_proxy.dart']!;
      expect(s, contains("post('/api/attachments'"));
      expect(s, contains("post('/api/attachments/delete'"));
      expect(s, contains('Future<Uint8List?> fetchAttachmentBytes('));
    });

    test('٤ — 🔴 وإعادةُ التشغيل بعد انقطاعٍ تعرف الفعلَين', () {
      final s = src['lib/services/offline_sync_worker.dart']!;
      final at = s.indexOf("case 'attachments':");
      expect(at, greaterThan(0),
          reason: 'لا حالةَ إعادةِ تشغيلٍ للمرفقات ⇒ كلُّ مرفقٍ رُفع والشبكةُ '
              'مقطوعةٌ يبقى في الطابور إلى الأبد ويُرمى بـStateError.');
      // والجسمُ يُقرأ لا الاسمُ وحدَه: حالةٌ فارغةٌ تمرّ بـ`contains`.
      final body = s.substring(at, at + 700);
      expect(body, contains('submitAttachment('));
      expect(body, contains('submitAttachmentDelete('));
    });

    test('٥ — والمساراتُ الثلاثةُ والمُعالِجاتُ الثلاثة', () {
      final router = src['lib/services/api/api_handler.dart']!;
      expect(router, contains("router.post('/api/attachments'"));
      expect(router, contains("router.post('/api/attachments/delete'"));
      expect(router, contains("router.get('/api/attachments/<globalId>'"));

      final handler = src['lib/services/api/api_data_handler.dart']!;
      expect(handler, contains('Future<Response> postAttachment('));
      expect(handler, contains('Future<Response> postAttachmentDelete('));
      expect(handler, contains('Future<Response> getAttachmentBytes('));
    });
  });

  group('والسياسةُ تُطبَّق على الطرفَين لا على العميل وحدَه', () {
    test('🔴 الخادمُ ينادي `validateAttachment` — لا يثق بما وصل', () {
      final handler = src['lib/services/api/api_data_handler.dart']!;
      expect(handler, contains('validateAttachment('),
          reason: 'الخادمُ يقبل ما يرسله العميلُ بلا فحص ⇒ عميلٌ مُعدَّلٌ '
              'يكتب ملفّاً تنفيذيّاً بحجمِ ما شاء في قاعدةٍ تُوزَّع على '
              'كلّ جهازٍ في المنشأة.');
      expect(handler, contains('validateAttachmentBytes('),
          reason: 'البصمةُ تُؤخَذ كما وصلت ⇒ العمودُ حِلْية.');
    });

    test('والمستودعُ ينادي السياسةَ نفسَها قبل الكتابة المحلّيّة', () {
      final repo =
          src['lib/data/repositories/attachments_repository_impl.dart']!;
      expect(repo, contains('validateAttachment('));
      expect(repo, contains('validateAttachmentBytes('));
    });

    test('🔴 والبصمةُ تُحسَب على الخادم لا تُنسَخ من الطلب', () {
      final handler = src['lib/services/api/api_data_handler.dart']!;
      expect(handler, contains('crypto.sha256.convert(bytes)'),
          reason: 'بصمةٌ يرسلها العميلُ ولا تُحسَب على الخادم تجعل الفحصَ '
              'تحصيلَ حاصلٍ يمرّ دائماً.');
    });

    test('وصلاحيةُ المستند هي البوّابة — لا صلاحيةَ عامّةٌ للمرفقات', () {
      final handler = src['lib/services/api/api_data_handler.dart']!;
      expect(handler, contains('entity.attachPermission'));
      expect(handler, contains('viewPermission'));
    });
  });

  group('والهُويّةُ تُختَم قبل الكتابتَين', () {
    test('🔴 `UuidV7.generate()` في المستودع قبل الإرسال والحفظ', () {
      final repo =
          src['lib/data/repositories/attachments_repository_impl.dart']!;
      final mint = repo.indexOf('UuidV7.generate()');
      final send = repo.indexOf('submitAttachment(');
      final save = repo.indexOf('insertAttachment(');
      expect(mint, greaterThan(0));
      expect(send, greaterThan(mint),
          reason: 'الهُويّةُ تُولَّد بعد الإرسال ⇒ صفُّ الخادم وصفُّ العميل '
              'بهُويّتَين لمرفقٍ واحد.');
      expect(save, greaterThan(mint));
    });

    test('ومستندٌ بلا هُويّةٍ عالميّةٍ يُرفَض في وضع العميل', () {
      final repo =
          src['lib/data/repositories/attachments_repository_impl.dart']!;
      expect(repo, contains('isClientMode'));
      expect(repo, contains('لم ينل هُويّتَه العالميّةَ بعد'));
    });
  });

  test('🔴 والخدمةُ الميّتةُ حُذفت — §٨٫١ قرار ٥', () {
    expect(File('lib/services/document_attachment_service.dart').existsSync(),
        isFalse,
        reason: 'شيفرةٌ ميّتةٌ تجسّد التصميمَ الذي رفضته §٨ (ملفٌّ على '
            'القرص + معرِّفٌ من `millisecondsSinceEpoch`) تُقرأ غداً على '
            'أنّها الطريق.');
  });

  test('ولا مُستوردَ لها بقي', () {
    final offenders = <String>[
      for (final f in Directory('lib').listSync(recursive: true))
        if (f is File &&
            f.path.endsWith('.dart') &&
            _code(f.readAsStringSync()).contains('document_attachment_service'))
          f.path,
    ];
    expect(offenders, isEmpty);
  });
}
