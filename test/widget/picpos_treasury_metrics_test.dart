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
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          backgroundColor: Colors.black,
          body: Directionality(
            textDirection: TextDirection.rtl,
            child: SizedBox(
              width: width,
              child: PicPosTreasurySplitBar(split: split),
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
      expect(find.text('بنكي'), findsOneWidget);
      expect(find.text('75%'), findsOneWidget);
      expect(find.text('25%'), findsOneWidget);
    });

    // ⚠️ الحارسُ الأهمّ: مجموعٌ صفريٌّ أو سالبٌ لا يُرسم له شريط، ولا تُعرض
    // نسبةُ «0%» التي تُقرأ خطأً كأن الرصيدَ صفر.
    testWidgets('مجموعٌ صفريٌّ ⇒ لا شريطَ ولا نسب', (tester) async {
      await show(
        tester,
        split([(kind: 'cash', balance: 500), (kind: 'bank', balance: -500)]),
      );
      expect(find.byType(ClipRRect), findsNothing);
      expect(find.textContaining('%'), findsNothing);
      // والأرقامُ نفسُها تبقى ظاهرة.
      expect(find.text('نقدي'), findsOneWidget);
    });

    testWidgets('مجموعٌ سالبٌ ⇒ لا شريط', (tester) async {
      await show(tester, split([(kind: 'cash', balance: -200)]));
      expect(find.byType(ClipRRect), findsNothing);
    });

    testWidgets('قائمةٌ فارغةٌ لا ترمي ولا ترسم شريطاً', (tester) async {
      await show(tester, split(const []));
      expect(tester.takeException(), isNull);
      expect(find.byType(ClipRRect), findsNothing);
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
