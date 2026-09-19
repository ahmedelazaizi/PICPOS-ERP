// «المستند المصدر» — خريطةٌ **مغلقةٌ** من القيد إلى ما ولّده.
//
// ═══ ما تحرسه هذه الحزمة ═══
//
// 🔴 **زرٌّ يُعرَض ولا يقفز أسوأُ من غيابه.** المستخدمُ ينقر فلا يحدث شيء،
// فيظنّ الشاشةَ معطَّلةً أو المستندَ محذوفاً — وكلاهما كذب.
//
// و`referenceType` مفرداتٌ **مفتوحةٌ فعلاً**: أكثرُ من أربعين قيمةً تُكتَب في
// المستودع، وأكثرُها لا شاشةَ له تفتح مستنداً بعينه (إقفالُ سنةٍ ماليّة،
// أرصدةٌ افتتاحيّة، تسويةُ ضريبة). فالشرطُ ثلاثيّ: نوعٌ معروف، ومعرّفٌ
// غيرُ فارغ، وشاشةٌ داخلَ النطاق.

import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/core/navigation/screen_id.dart';
import 'package:ural_erp/domain/models/journal_source_document.dart';

void main() {
  final wide = ScreenId.values.toSet();

  JournalSourceTarget? resolve(String? type, int? id,
          {Set<ScreenId>? scope}) =>
      resolveJournalSourceTarget(
        referenceType: type,
        referenceId: id,
        allowedScreenIds: scope ?? wide,
      );

  group('الشروطُ الثلاثة', () {
    test('نوعٌ معروفٌ ومعرّفٌ صحيحٌ ⇒ وجهة', () {
      final t = resolve('sales_invoice', 42);
      expect(t, isNotNull);
      expect(t!.screenId, ScreenId.salesInvoices);
      expect(t.label, 'فاتورة المبيعات');
    });

    test('ونوعٌ غيرُ معروفٍ ⇒ لا زرّ', () {
      // 🔴 هذه هي الحالةُ الشائعة: إقفالُ سنةٍ ماليّة، أرصدةٌ افتتاحيّة،
      // تسويةُ ضريبة — قيودٌ حقيقيّةٌ بلا مستندٍ يُفتَح.
      for (final t in [
        'fiscal_close',
        'opening_balance',
        'vat_settlement',
        'restatement',
        'reversal',
      ]) {
        expect(resolve(t, 1), isNull, reason: '«$t» صار له زرٌّ لا يقفز');
      }
    });

    test('ومعرّفٌ غائبٌ أو صفرٌ ⇒ لا زرّ', () {
      // قيدٌ يحمل نوعاً ولا يحمل رقمَ مستنده: الزرُّ سيفتح شاشةً بلا هدف.
      expect(resolve('sales_invoice', null), isNull);
      expect(resolve('sales_invoice', 0), isNull);
      expect(resolve('sales_invoice', -3), isNull);
    });

    test('ونوعٌ فارغٌ أو معدومٌ ⇒ لا زرّ', () {
      expect(resolve(null, 5), isNull);
      expect(resolve('', 5), isNull);
    });

    test('🔴 وشاشةٌ خارجَ النطاق ⇒ لا زرّ', () {
      // تجهيزةٌ لا تملك شاشةَ الأوراق التجاريّة: زرٌّ يقودها إليها يفتح
      // شاشةً محجوبةً — أو لا شيء.
      final narrow = {ScreenId.salesInvoices};
      expect(resolve('sales_invoice', 9, scope: narrow), isNotNull);
      expect(resolve('commercial_paper', 9, scope: narrow), isNull);
    });
  });

  group('المرادفاتُ التاريخيّة تردّ إلى وجهةٍ واحدة', () {
    test('المبيعات: ثلاثةُ أسماءٍ لحدثٍ واحد', () {
      // ⚠️ إسقاطُ مرادفٍ يعني قيوداً قديمةً بلا زرّ.
      for (final t in ['sales_invoice', 'sale_invoice', 'sale']) {
        expect(resolve(t, 1)?.screenId, ScreenId.salesInvoices,
            reason: '«$t» فقد وجهتَه');
      }
    });

    test('والمشتريات: اسمان لحدثٍ واحد', () {
      for (final t in ['purchase_invoice', 'purchase']) {
        expect(resolve(t, 1)?.screenId, ScreenId.purchases,
            reason: '«$t» فقد وجهتَه');
      }
    });

    test('والخزينة: سندُ القبض والصرف باسمَيهما القديم والجديد', () {
      expect(resolve('receipt_voucher', 1)?.screenId, ScreenId.treasury);
      expect(resolve('receipt', 1)?.screenId, ScreenId.treasury);
      expect(resolve('payment_voucher', 1)?.screenId, ScreenId.treasury);
      expect(resolve('payment', 1)?.screenId, ScreenId.treasury);
    });
  });

  group('الخريطةُ نفسُها', () {
    test('كلُّ تسميةٍ غيرُ فارغة', () {
      for (final e in kJournalSourceTargets.entries) {
        expect(e.value.label.trim(), isNotEmpty,
            reason: 'زرٌّ بلا نصٍّ للنوع «${e.key}»');
      }
    });

    test('ومرادفاتُ الحدث الواحد تتّفق على وجهةٍ واحدة', () {
      // 🔴 مرادفان يقودان شاشتَين مختلفتَين يعني أنّ نفسَ الحدث يُفتَح من
      // بابَين — وأحدُهما خطأٌ بالضرورة.
      const groups = [
        ['sales_invoice', 'sale_invoice', 'sale', 'sales_invoice_void'],
        ['purchase_invoice', 'purchase', 'purchase_invoice_void'],
        ['receipt_voucher', 'receipt'],
        ['payment_voucher', 'payment'],
      ];
      for (final g in groups) {
        final screens =
            g.map((t) => kJournalSourceTargets[t]!.screenId).toSet();
        expect(screens, hasLength(1),
            reason: 'مرادفاتُ ${g.first} تقود إلى ${screens.length} شاشات');
      }
    });
  });
}
