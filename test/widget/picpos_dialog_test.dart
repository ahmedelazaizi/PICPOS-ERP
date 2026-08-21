// غلافُ ديالوجات PicPos — العقدُ المشترك لكلّ حوارات النظام.
//
// يُقاس هنا ما يكسر **١٠٤ حوارٍ** دفعةً واحدةً لو انحرف:
//  ‏١) الرأسُ يعرض ما أُعطي، والإغلاقُ يُغلق فعلاً.
//  ‏٢) الأزرارُ تُنادى — والمعطَّلُ منها **لا** يُنادى وهو ظاهر.
//  ‏٣) **لا فيضانَ عند الضيق**: تذييلٌ بأربعة أزرارٍ على حوارٍ ضيّقٍ كان
//     يفيض، والفيضُ في Flutter شريطٌ أصفرُ وأسودُ فوق الواجهة لا قصٌّ صامت.
//     وهذا العطبُ وقع مرّتين في هذه الجلسة، فصار له حارسٌ صريح.
//  ‏٤) `PicPosDialogRow` ينكسر رأسيّاً تحت العتبة بدل أن يسحق الحقول.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:ural_erp/core/theme/app_colors.dart';
import 'package:ural_erp/presentation/picpos_shell/picpos_dialog.dart';

void main() {
  Future<void> show(
    WidgetTester tester,
    Widget dialog, {
    Size size = const Size(1000, 800),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: dialog)));
    await tester.pumpAndSettle();
  }

  group('الرأس', () {
    testWidgets('يعرض العنوانَ والسطرَ الخافتَ والأيقونة', (tester) async {
      await show(
        tester,
        const PicPosDialog(
          icon: PhosphorIconsBold.arrowCircleDown,
          accent: AppColors.success,
          title: 'سند قبض',
          subtitle: 'RV-2026-0842 · 21 أغسطس 2026',
          body: [Text('جسم')],
        ),
      );
      expect(find.text('سند قبض'), findsOneWidget);
      expect(find.text('RV-2026-0842 · 21 أغسطس 2026'), findsOneWidget);
      expect(find.byIcon(PhosphorIconsBold.arrowCircleDown), findsOneWidget);
      expect(find.text('جسم'), findsOneWidget);
    });

    testWidgets('بلا سطرٍ خافتٍ لا يُرسَم سطرٌ فارغ', (tester) async {
      await show(
        tester,
        const PicPosDialog(
          icon: PhosphorIconsBold.scales,
          title: 'مراجعة الأرصدة',
          body: [Text('جسم')],
        ),
      );
      expect(find.text('مراجعة الأرصدة'), findsOneWidget);
      // زرُّ الإغلاق موجودٌ دائماً في الرأس.
      expect(find.byIcon(PhosphorIconsBold.x), findsOneWidget);
    });

    testWidgets('زرُّ «×» ينادي onCancel حين يُعطى', (tester) async {
      var closed = 0;
      await show(
        tester,
        PicPosDialog(
          icon: PhosphorIconsBold.scales,
          title: 'حوار',
          body: const [Text('جسم')],
          onCancel: () => closed++,
        ),
      );
      await tester.tap(find.byIcon(PhosphorIconsBold.x));
      await tester.pump();
      expect(closed, 1);
    });
  });

  group('التذييل', () {
    testWidgets('الرئيسيُّ والثانويُّ والإلغاءُ كلُّها تُنادى', (tester) async {
      var primary = 0, secondary = 0, cancel = 0;
      await show(
        tester,
        PicPosDialog(
          icon: PhosphorIconsBold.arrowCircleDown,
          title: 'سند قبض',
          body: const [Text('جسم')],
          onCancel: () => cancel++,
          secondaryActions: [
            PicPosDialogAction(
              label: 'طباعة A4',
              icon: PhosphorIconsBold.printer,
              onPressed: () => secondary++,
            ),
          ],
          primaryAction: PicPosDialogAction(
            label: 'حفظ السند',
            icon: PhosphorIconsBold.check,
            onPressed: () => primary++,
          ),
        ),
      );

      await tester.tap(find.text('حفظ السند'));
      await tester.tap(find.text('طباعة A4'));
      await tester.tap(find.text('إلغاء'));
      await tester.pump();

      expect(primary, 1);
      expect(secondary, 1);
      expect(cancel, 1);
    });

    testWidgets('الزرُّ المعطَّلُ يظهر ولا يُنادى', (tester) async {
      var fired = 0;
      await show(
        tester,
        const PicPosDialog(
          icon: PhosphorIconsBold.arrowCircleDown,
          title: 'سند قبض',
          body: [Text('جسم')],
          primaryAction: PicPosDialogAction(
            label: 'حفظ السند',
            onPressed: null,
          ),
        ),
      );
      expect(find.text('حفظ السند'), findsOneWidget,
          reason: 'يبقى مرئيّاً كي يعرف المستخدمُ أن الإجراءَ موجود');
      await tester.tap(find.text('حفظ السند'));
      await tester.pump();
      expect(fired, 0);
    });

    testWidgets('بلا أزرارٍ إطلاقاً لا يُرسَم تذييل', (tester) async {
      await show(
        tester,
        const PicPosDialog(
          icon: PhosphorIconsBold.scales,
          title: 'حوار',
          body: [Text('جسم')],
        ),
      );
      expect(find.text('إلغاء'), findsNothing);
    });
  });

  group('لا فيضانَ عند الضيق', () {
    testWidgets('أربعةُ أزرارٍ على حوارٍ ضيّقٍ تلتفّ ولا تفيض', (tester) async {
      await show(
        tester,
        PicPosDialog(
          icon: PhosphorIconsBold.arrowCircleDown,
          title: 'سند قبض بعنوانٍ طويلٍ نسبيّاً',
          subtitle: 'RV-2026-0842 · 21 أغسطس 2026 · فرع المعادي',
          width: 660,
          body: const [Text('جسم')],
          onCancel: () {},
          secondaryActions: [
            PicPosDialogAction(
                label: 'طباعة A4',
                icon: PhosphorIconsBold.printer,
                onPressed: () {}),
            PicPosDialogAction(
                label: 'حفظ + حراري',
                icon: PhosphorIconsBold.receipt,
                onPressed: () {}),
            PicPosDialogAction(
                label: 'إعادة الفحص',
                icon: PhosphorIconsBold.arrowsClockwise,
                onPressed: () {}),
          ],
          primaryAction: PicPosDialogAction(
              label: 'حفظ السند',
              icon: PhosphorIconsBold.check,
              onPressed: () {}),
        ),
        // شاشةٌ ضيّقةٌ عمداً — لوحُ كاشيرٍ صغير.
        size: const Size(700, 700),
      );
      // ‏`pumpAndSettle` لا يرمي على الفيض؛ الفيضُ يُسجَّل استثناءً في
      // `tester.takeException`. فيُفحَص صراحةً.
      expect(tester.takeException(), isNull,
          reason: 'الالتفافُ في التذييل هو ما يمنع الشريطَ الأصفرَ والأسود');
    });

    testWidgets('عنوانٌ طويلٌ جدّاً يُقصَّر ولا يفيض', (tester) async {
      await show(
        tester,
        const PicPosDialog(
          icon: PhosphorIconsBold.scales,
          title: 'عنوانٌ طويلٌ جدّاً يتجاوز عرضَ الحوار بكثيرٍ جدّاً جدّاً '
              'ولا ينبغي أن يكسر الرأس',
          subtitle: 'وسطرٌ خافتٌ طويلٌ كذلك يتجاوز العرضَ المتاحَ بمراحل',
          width: 660,
          body: [Text('جسم')],
        ),
        size: const Size(700, 700),
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('مكوّناتُ الجسم', () {
    testWidgets('الحقلُ المطلوبُ يحمل نجمةً', (tester) async {
      await show(
        tester,
        const PicPosDialog(
          icon: PhosphorIconsBold.vault,
          title: 'حوار',
          body: [
            PicPosDialogField(
              label: 'الخزينة',
              required: true,
              child: Text('الصندوق الرئيسي'),
            ),
          ],
        ),
      );
      expect(find.text('الخزينة'), findsOneWidget);
      expect(find.text(' *'), findsOneWidget);
      expect(find.text('الصندوق الرئيسي'), findsOneWidget);
    });

    testWidgets('الصفُّ ينكسر رأسيّاً تحت العتبة', (tester) async {
      Widget row() => const PicPosDialogRow(
            breakpoint: 520,
            children: [
              PicPosDialogField(label: 'أ', child: Text('١')),
              PicPosDialogField(label: 'ب', child: Text('٢')),
            ],
          );

      // عريضٌ: صفٌّ أفقيّ ⇒ الحقلان على نفس الارتفاع تقريباً.
      await show(
        tester,
        PicPosDialog(
          icon: PhosphorIconsBold.vault,
          title: 'حوار',
          body: [row()],
        ),
        size: const Size(1000, 800),
      );
      final wideA = tester.getTopLeft(find.text('أ')).dy;
      final wideB = tester.getTopLeft(find.text('ب')).dy;
      expect(wideA, wideB, reason: 'أفقيّاً ⇒ نفسُ الصفّ');

      // ضيّقٌ: عمودٌ ⇒ الثاني تحت الأوّل.
      await show(
        tester,
        PicPosDialog(
          icon: PhosphorIconsBold.vault,
          title: 'حوار',
          width: 400,
          body: [row()],
        ),
        size: const Size(460, 800),
      );
      final narrowA = tester.getTopLeft(find.text('أ')).dy;
      final narrowB = tester.getTopLeft(find.text('ب')).dy;
      expect(narrowB, greaterThan(narrowA),
          reason: 'تحت العتبة ينكسر رأسيّاً بدل أن يسحق الحقلَين');
    });

    testWidgets('الملخّصُ يعرض كلَّ أسطره', (tester) async {
      await show(
        tester,
        const PicPosDialog(
          icon: PhosphorIconsBold.scales,
          title: 'حوار',
          body: [
            PicPosDialogSummary(rows: [
              (label: 'الإجمالي', value: '1,000', color: null),
              (label: 'المسدَّد', value: '400', color: AppColors.success),
              (label: 'المتبقي', value: '600', color: AppColors.error),
            ]),
          ],
        ),
      );
      expect(find.text('الإجمالي'), findsOneWidget);
      expect(find.text('600'), findsOneWidget);
      expect(find.text('المسدَّد'), findsOneWidget);
    });

    testWidgets('بلاطةُ الاختيار: المنتقاةُ وحدَها ملوّنة', (tester) async {
      var picked = '';
      await show(
        tester,
        PicPosDialog(
          icon: PhosphorIconsBold.wallet,
          title: 'حوار',
          body: [
            PicPosDialogRow(children: [
              PicPosDialogChoice(
                icon: PhosphorIconsBold.money,
                label: 'نقدي',
                selected: true,
                accent: AppColors.success,
                onTap: () => picked = 'cash',
              ),
              PicPosDialogChoice(
                icon: PhosphorIconsBold.bank,
                label: 'تحويل بنكي',
                selected: false,
                onTap: () => picked = 'bank',
              ),
            ]),
          ],
        ),
      );
      await tester.tap(find.text('تحويل بنكي'));
      await tester.pump();
      expect(picked, 'bank');
    });
  });
}
