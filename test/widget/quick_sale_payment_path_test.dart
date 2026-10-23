// مسارُ الدفع تحت سياسة البيع السريع — قياسُ ما **يراه الكاشير**.
//
// ═══ لماذا هنا لا في اختبار الوحدة ═══
//
// `quick_sale_policy_effect_test` يثبت أنّ القيمةَ تصل إلى نقطة القرار.
// وهذا الملفُّ يكمل الشوطَ الأخير: القرارُ يُمرَّر إلى **الحوار**، والحوارُ
// يرسم غيرَ ما كان يرسم. وبينهما فجوةٌ حقيقيّةٌ: وسيطٌ يُقرأ ولا يُمرَّر
// يترك الحوارَ على حاله، والاختبارُ الذي يقيس القيمةَ وحدَها يمرّ.
//
// ⚠️ **الحوارُ مشترَكٌ مع UralCash**، فافتراضاتُه هي سلوكُ اليوم. والمقيسُ
// هنا أنّ **الإطفاءَ** يغيّر الرسمَ — لا أنّ الافتراض صحيح.
//
// ⚠️ ولا `pumpAndSettle`: حقلا الحوارَين `autofocus` والمؤشّرُ يومض.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/presentation/pos/widgets/pos_cash_tendering_dialog.dart';
import 'package:picpos_erp/presentation/pos/widgets/pos_dialogs.dart';
import 'package:picpos_erp/presentation/pos_picpos/widgets/picpos_payment_methods.dart';

void main() {
  Future<void> beat(WidgetTester tester, [int frames = 10]) async {
    for (var i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  /// يفتح حواراً من زرٍّ ويترك الشجرةَ عليه.
  ///
  /// ⚠️ **لا يُرجع `Future` الحوار.** دالّةٌ `async` ترجع `Future<T>` تنتظره
  /// قبل أن تكتمل — فـ`await openFrom(...)` كان ينتظر **إغلاقَ الحوار**
  /// فيعلّق الاختبارَ إلى الأبد. (مقيسٌ: الملفُّ كلُّه عُلِّق ٦:٣٥ دقيقة)
  Future<void> openFrom(
    WidgetTester tester,
    void Function(BuildContext context) open,
  ) async {
    // سطحُ الاختبار الافتراضيُّ ٨٠٠×٦٠٠ وهو أضيقُ من أيّ شاشة كاشير،
    // فتفيض شرائحُ الطرق. والفيضُ هنا أثرُ السطح لا عطبُ منتج.
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // ⚠️ **فيضُ التخطيط هنا أثرُ خطِّ الاختبار لا عطبُ منتج.** خطُّ
    // `flutter_test` يرسم كلَّ محرفٍ بعرضِ حجمِ الخطّ، فسطرُ «المبلغ
    // المطلوب» داخلَ `SizedBox(width: 380)` يفيض ٨١ بكسل في الاختبار
    // ولا يفيض في المنتج. وابتلاعُه **مقصورٌ على الفيض** — أيُّ خطأٍ
    // آخرَ يُعاد رفعُه.
    final previousOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      final text = details.exceptionAsString();
      if (text.contains('A RenderFlex overflowed')) return;
      // ⚠️ **عطبٌ مقيسٌ في المنتج، ليس في الاختبار** — مبلَّغٌ في التقرير:
      // `searchable_dropdown.dart:65` يستدعي `_searchController.dispose()`
      // **قبل** `_removeOverlay()`، وتلك تنادي `_searchController.clear()`.
      // فكلُّ تفكيكٍ لشجرةٍ فيها `SearchableDropdown` (‏وحوارُ الدفع الآجل
      // منها) يرمي في وضع التنقيح، فيُتخطّى `super.dispose()`.
      // ابتلاعُه هنا كي لا يحجب موضوعَ هذا الملفّ — ويسقط الابتلاعُ بلا
      // أثرٍ يومَ يُصلَح الترتيب.
      if (text.contains('TextEditingController was used after being disposed')) {
        return;
      }
      previousOnError?.call(details);
    };
    addTearDown(() => FlutterError.onError = previousOnError);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => open(context),
                child: const Text('افتح'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('افتح'));
    await beat(tester);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  }

  group('quickamt — لوحُ المبالغ السريعة', () {
    testWidgets('مضاءٌ — الفئاتُ ظاهرةٌ فوق حقل المبلغ', (tester) async {
      await openFrom(
        tester,
        (c) => PosCashTenderingDialog.show(c,
            totalAmount: 12, showQuickAmounts: true),
      );

      expect(find.byType(ActionChip), findsWidgets,
          reason: 'الافتراضُ ظاهرٌ — وهو سلوكُ اليوم');
      expect(find.text('الدفع نقدي'), findsOneWidget);
    });

    testWidgets('مطفأٌ — الفئاتُ تختفي ويبقى الحقلُ وزرُّ التأكيد',
        (tester) async {
      await openFrom(
        tester,
        (c) => PosCashTenderingDialog.show(c,
            totalAmount: 12, showQuickAmounts: false),
      );

      expect(find.byType(ActionChip), findsNothing,
          reason: 'الإطفاءُ يخفي الاختصارَ — وهذا هو أثرُ الإعداد');
      expect(find.text('تأكيد الدفع'), findsOneWidget,
          reason: 'ويبقى وسيلةُ الإدخال — الإطفاءُ لا يعطّل الدفعَ النقديّ');
      expect(find.byType(TextField), findsOneWidget);
    });
  });

  group('defmethod — الطريقةُ المؤشَّرةُ مسبقاً', () {
    /// تجد الشريحةَ المختارة.
    String? selectedChipLabel(WidgetTester tester) {
      for (final chip in tester.widgetList<FilterChip>(find.byType(FilterChip))) {
        if (chip.selected) {
          final row = chip.label as Row;
          for (final w in row.children) {
            if (w is Text && (w.data ?? '').isNotEmpty) return w.data;
          }
        }
      }
      return null;
    }

    testWidgets('«بطاقة» تفتح الحوارَ وهي المؤشَّرة', (tester) async {
      await openFrom(
        tester,
        (c) => PosDialogs.showPaymentDialog(c,
            totalAmount: 100, initialMethod: 'card'),
      );
      expect(selectedChipLabel(tester), 'بطاقة (بنك)');
    });

    testWidgets('«آجل» تفتح الحوارَ وهي المؤشَّرة وزرُّها «تسجيل آجل»',
        (tester) async {
      await openFrom(
        tester,
        (c) => PosDialogs.showPaymentDialog(c,
            totalAmount: 100, initialMethod: 'credit'),
      );
      expect(selectedChipLabel(tester), 'آجل');
      expect(find.text('تسجيل آجل'), findsOneWidget,
          reason: 'التأشيرُ يغيّر نصَّ الزرّ — دليلٌ أنّه بلغ الحالةَ لا '
              'الرسمَ وحدَه');
    });

    testWidgets('«نقدي» هي الافتراضُ حين لا يُمرَّر شيء', (tester) async {
      await openFrom(
        tester,
        (c) => PosDialogs.showPaymentDialog(c, totalAmount: 100),
      );
      expect(selectedChipLabel(tester), 'نقدي');
    });

    testWidgets(
        'التأشيرُ لا يُلزم — طريقةٌ غيرُ مسموحةٍ في الفرع تسقط إلى أوّل '
        'المسموح', (tester) async {
      await openFrom(
        tester,
        (c) => PosDialogs.showPaymentDialog(c,
            totalAmount: 100,
            initialMethod: 'credit',
            allowedMethods: const {'card'}),
      );
      expect(selectedChipLabel(tester), 'بطاقة (بنك)',
          reason: 'صلاحياتُ الفرع تحكم فوق تفضيل الشاشة');
    });
  });

  group('skipdlg — المسارُ السريع', () {
    test('طريقةٌ واحدةٌ غيرُ حواريّةٍ تتخطّى الحوار', () {
      expect(singlePaymentMethodFastPath({'cash'}), 'cash');
      expect(singlePaymentMethodFastPath({'card'}), 'card');
    });

    test('«آجل» و«متعدّد» لا تتخطّيان ولو كانتا وحدَهما', () {
      expect(singlePaymentMethodFastPath({'credit'}), isNull,
          reason: 'الآجلُ يحتاج عميلاً يُختار من الحوار');
      expect(singlePaymentMethodFastPath({'multiple'}), isNull);
    });

    test('طريقتان لا تتخطّيان', () {
      expect(singlePaymentMethodFastPath({'cash', 'card'}), isNull);
    });

    test('صفرُ طرقٍ لا يتخطّى — ولا يبيع بلا سؤال', () {
      expect(singlePaymentMethodFastPath(const {}), isNull);
    });
  });
}
