// لوحُ مقاييس الخزينة — **فوركُ PicPos** + شريطُ تقسيم الرصيد.
//
// ═══ لماذا اختبارٌ خاصٌّ بالفورك ═══
//
// حرّاسُ السندَين (`treasury_receipts_create` / `treasury_payments_create`)
// نُقلا بالنسخ. وأيُّ اختبارٍ يفحص الأصلَ `treasury/widgets/…` يبقى أخضرَ ولو
// سقط الحارسُ من النسخة — وهي فئةُ العطب التي وُجد
// `picpos_permission_parity_test` لأجلها، وقد **قِيست فعلاً** على فورك
// الأصناف في نفس الجلسة: أزلتُ حارساً من النسخة فسقط اختبارُها وبقي
// اختبارُ الأصل أخضر.
//
// وشريطُ التقسيم يُقاس هنا لأن قرارَه البصريَّ (‏يُرسم أم لا) يحمل حارساً
// حقيقيّاً: مجموعٌ غيرُ موجبٍ لا يُرسم له شريط.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/domain/models/picpos_treasury_view.dart';
import 'package:ural_erp/presentation/treasury_picpos/widgets/treasury_metrics_panel_picpos.dart';

void main() {
  Future<void> show(
    WidgetTester tester,
    PicPosTreasurySplit split, {
    double width = 700,
    bool onDark = true,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          backgroundColor: onDark ? Colors.black : Colors.white,
          body: Directionality(
            textDirection: TextDirection.rtl,
            child: SizedBox(
              width: width,
              child: PicPosTreasurySplitChips(split: split, onDark: onDark),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  PicPosTreasurySplit split(List<({String kind, double balance})> safes) =>
      PicPosTreasurySplit.from(safes);

  group('شريطُ التقسيم', () {
    testWidgets('يعرض الشريحتَين بقيمهما ونسبهما', (tester) async {
      await show(
        tester,
        split([(kind: 'cash', balance: 750), (kind: 'bank', balance: 250)]),
      );
      expect(find.text('نقدي'), findsOneWidget);
      expect(find.text('بنوك'), findsOneWidget);
      expect(find.text('75%'), findsOneWidget);
      expect(find.text('25%'), findsOneWidget);
    });

    // ⚠️ كليك شريحةٌ مستقلّة — كانت تُضمّ إلى النقديّ في أوّل نسخة، فيظهر
    // مجموعٌ صحيحٌ بتوزيعٍ خاطئ. والنوعُ قائمٌ في التنصيبة الحيّة لا مفترَض.
    testWidgets('يعرض الشرائحَ الثلاثَ بما فيها كليك', (tester) async {
      await show(
        tester,
        split([
          (kind: 'cash', balance: 200),
          (kind: 'bank', balance: 700),
          (kind: 'click', balance: 100),
        ]),
      );
      expect(find.text('نقدي'), findsOneWidget);
      expect(find.text('بنوك'), findsOneWidget);
      expect(find.text('كليك'), findsOneWidget);
      expect(find.text('70%'), findsOneWidget);
      expect(find.text('10%'), findsOneWidget);
    });

    // ⚠️ الحارسُ الأهمّ: مجموعٌ صفريٌّ أو سالبٌ لا تُعرض له نسبٌ — «0%» تُقرأ
    // خطأً كأن الرصيدَ صفر. والأرقامُ نفسُها تبقى ظاهرة.
    testWidgets('مجموعٌ صفريٌّ ⇒ لا نسب، والأرقامُ باقية', (tester) async {
      await show(
        tester,
        split([(kind: 'cash', balance: 500), (kind: 'bank', balance: -500)]),
      );
      expect(find.textContaining('%'), findsNothing);
      expect(find.text('نقدي'), findsOneWidget);
    });

    testWidgets('مجموعٌ سالبٌ ⇒ لا نسب', (tester) async {
      await show(tester, split([(kind: 'cash', balance: -200)]));
      expect(find.textContaining('%'), findsNothing);
    });

    testWidgets('قائمةٌ فارغةٌ لا ترمي', (tester) async {
      await show(tester, split(const []));
      expect(tester.takeException(), isNull);
      expect(find.textContaining('%'), findsNothing);
    });

    // ═══ عقدُ الألوان — الحارسُ الذي كان ناقصاً ═══
    //
    // النسخةُ الأولى شُحنت بنصٍّ أبيضَ على خلفيّةٍ فاتحةٍ فصار غيرَ مقروء.
    // فاللونُ صار مشروطاً بـ`onDark` **المُمرَّر**، ويُقاس الطرفان.
    testWidgets('على الداكن: النصُّ أبيض', (tester) async {
      await show(tester, split([(kind: 'cash', balance: 100)]));
      final label = tester.widget<Text>(find.text('نقدي'));
      expect(label.style?.color, Colors.white70);
    });

    testWidgets('على الفاتح: النصُّ ليس أبيضَ', (tester) async {
      await show(
        tester,
        split([(kind: 'cash', balance: 100)]),
        onDark: false,
      );
      final label = tester.widget<Text>(find.text('نقدي'));
      expect(label.style?.color, isNot(Colors.white70));
      expect(label.style?.color, isNot(Colors.white));
    });

    testWidgets('لا يفيض عند عرضٍ ضيّقٍ بأرقامٍ كبيرة', (tester) async {
      await show(
        tester,
        split([
          (kind: 'cash', balance: 98765432.1),
          (kind: 'bank', balance: 12345678.9),
        ]),
        width: 300,
      );
      expect(tester.takeException(), isNull,
          reason: 'الالتفافُ هو ما يمنع الشريطَ الأصفرَ والأسود');
    });
  });
}
