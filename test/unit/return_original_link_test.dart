// ═══════════════════════════════════════════════════════════════════════════
// رابطُ المرتجع بفاتورته الأصليّة — مُستخرَجٌ ليُشارَك، لا مُعادُ كتابته.
// ═══════════════════════════════════════════════════════════════════════════
//
// `SalesInvoices` **لا يحمل عموداً** يربط المرتجعَ بأصله؛ الرابطُ نصٌّ في
// `notes` بصيغة `localReturnLinkNote`:
//
//     'Return for invoice #12|gid:<uuid>'
//
// والقراءةُ تحلّ بالـ`gid` **أوّلاً**: المعرّفُ الرقميُّ لا معنى له إلّا في
// المخزن الذي كتبه، والسحبُ يستبدل صفَّ العميل بصفِّ الخادم — فالقراءةُ بالرقم
// وحدَه تُقاصّ الاسترداد على فاتورةٍ خاطئة.
//
// وكان المحلِّلان **خاصَّين** داخلَ `SalesDao`. ومِكنسةُ إشعارات الائتمان
// تحتاجهما، فاستُخرجا إلى موضعٍ واحدٍ يفوّض إليه الأصلُ — بدل نسخةٍ ثانيةٍ
// تتخلّف عن الأولى.

import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/domain/models/return_original_link.dart';

void main() {
  group('البناء', () {
    test('بلا معرّفٍ عالميّ ⇒ الرقمُ وحدَه', () {
      expect(buildReturnOriginalLinkNote(12), 'Return for invoice #12');
    });

    test('مع معرّفٍ عالميّ ⇒ يُلحَق بعد الشرطة', () {
      expect(buildReturnOriginalLinkNote(12, originalGlobalId: 'abc'),
          'Return for invoice #12|gid:abc');
    });

    test('معرّفٌ فارغٌ يُعامَل كغائب', () {
      expect(buildReturnOriginalLinkNote(12, originalGlobalId: ''),
          'Return for invoice #12');
    });
  });

  group('القراءة', () {
    test('يستخرج المعرّفَ العالميّ', () {
      expect(returnOriginalGidFromNote('Return for invoice #12|gid:u-1'), 'u-1');
    });

    test('ويستخرج الرقم', () {
      expect(returnOriginalIdFromNote('Return for invoice #12|gid:u-1'), 12);
      expect(returnOriginalIdFromNote('Return for invoice #7'), 7);
    });

    test('ملاحظةٌ ليست بالصيغة ⇒ لا رابطَ — مرتجعُ نقطةِ بيعٍ بلا أصل', () {
      expect(returnOriginalIdFromNote('مرتجع سريع'), isNull);
      expect(returnOriginalGidFromNote('مرتجع سريع'), isNull);
      expect(returnOriginalIdFromNote(null), isNull);
      expect(returnOriginalGidFromNote(null), isNull);
    });

    // 🔴 التطابقُ مع المحلِّل القائم شرطٌ لا تحسين: لو اختلفا لقُوصَّ
    //    الاستردادُ في شاشةٍ على فاتورةٍ وقُدِّم إشعارُ الائتمان على أخرى.
    test('🔴 يطابق ما يبنيه البناءُ نفسُه — ذهاباً وإياباً', () {
      for (final gid in <String?>[null, '', 'uuid-v7-xyz']) {
        final note = buildReturnOriginalLinkNote(4321, originalGlobalId: gid);
        expect(returnOriginalIdFromNote(note), 4321, reason: 'gid=$gid');
        final expectedGid = (gid == null || gid.isEmpty) ? null : gid;
        expect(returnOriginalGidFromNote(note), expectedGid, reason: 'gid=$gid');
      }
    });

    test('وسمٌ إضافيٌّ بعد الرابط لا يكسر قراءةَ الرقم', () {
      // مسارُ الاستبدال يلحق وسماً ثانياً بنفس الحقل.
      expect(returnOriginalIdFromNote('Return for invoice #9|gid:u|exch:3'), 9);
    });
  });
}
