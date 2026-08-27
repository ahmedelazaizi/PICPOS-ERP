// test/widget/cheques_picpos_deposit_dialog_test.dart
//
// حوارُ «إيداع شيكات بالبنك» — فورك `DLGS.deposit`.
//
// ═══ ما يحرسه هذا الملفّ ═══
//
// التصميمُ يكتب زرَّ الحفظ `save:'إيداع ٣ شيكات'` وملخّصاً بالإجمالي
// `30,200`. وكلاهما **محسوبٌ من الاختيار** لا نصٌّ ثابت.
//
// ⚠️ **يُقاس الرقمُ لا الحالة** (‏قاعدةٌ ثبتت بالقياس): «الإجماليُّ تحرّك»
// يمرّ على مقدارٍ خاطئ. فالقيمُ هنا مثبَّتةٌ محسوبةً بيد:
//   ‏18,000 + 8,400 = 26,400 · وبعد رفع الثاني = 18,000.
//
// 🔴 **ومرشَّحُ الإيداع لا يشمل المرتجعة**: حارسُ الـDAO
// `if (!['pending','in_portfolio'].contains(paper.status)) throw` يرفضها،
// فالشاشةُ لا تمرّرها أصلاً — وهذا الملفُّ يثبّت أنّ الحوارَ يتصرّف بأدبٍ
// حين تصله قائمةٌ فارغة بدل أن يعرض زرَّ إيداعٍ يُلقي.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/domain/repositories/treasury_repository.dart'
    show SafeData;
import 'package:ural_erp/presentation/settings_picpos/screens/cheques_picpos_deposit_dialog.dart';

const _banks = [
  SafeData(
    id: 4,
    name: 'بنك مصر — المعادي',
    safeType: 'bank',
    balance: 0,
    isDefault: false,
    isActive: true,
    accountNumber: '4471-882-1',
  ),
];

final _candidates = [
  DepositCandidate(
    id: 11,
    paperNumber: '8842',
    amount: 18000,
    dueDate: DateTime(2026, 9, 20),
    partyName: 'سوبر ماركت النور',
  ),
  DepositCandidate(
    id: 12,
    paperNumber: '5540',
    amount: 8400,
    dueDate: DateTime(2026, 8, 18),
    partyName: 'كافيه الركن',
  ),
];

/// يجمع ما أرجعه الحوارُ بعد إغلاقه.
///
/// ⚠️ **حاملٌ لا قيمةٌ مُرجَعة**: النموذجُ لا يصل إلّا بعد أن يُغلَق الحوارُ،
/// وذلك بعد أن تعود `_open`. فقراءتُه تحتاج موضعاً يبقى.
class _Captured {
  DepositBatchForm? form;
}

Future<_Captured> _open(
  WidgetTester tester,
  double width, {
  required List<DepositCandidate> candidates,
  Set<int> preselected = const {},
}) async {
  final out = _Captured();
  tester.view.physicalSize = Size(width, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            out.form = await showChequesPicposDepositDialog(
              context,
              candidates: candidates,
              bankSafes: _banks,
              preselected: preselected,
            );
          },
          child: const Text('افتح'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('افتح'));
  await tester.pumpAndSettle();
  return out;
}

void main() {
  for (final width in [1280.0, 1920.0]) {
    final w = width.toInt();

    group('عرض $w', () {
      testWidgets('عددُ الشيكات في زرّ الحفظ محسوبٌ من الاختيار',
          (tester) async {
        await _open(
          tester,
          width,
          candidates: _candidates,
          preselected: const {11, 12},
        );

        // ‏٢ مختاران ⇒ «إيداع 2 شيكات».
        expect(find.text('إيداع 2 شيكات'), findsOneWidget);

        // رفعُ واحدٍ ⇒ «إيداع 1 شيك» — والمفردُ يُصرَّف.
        await tester.tap(find.textContaining('5540'));
        await tester.pumpAndSettle();
        expect(find.text('إيداع 1 شيك'), findsOneWidget);

        expect(tester.takeException(), isNull);
      });

      testWidgets('الإجماليُّ يطابق مجموعَ المختار — بالقيمة لا بالحركة',
          (tester) async {
        await _open(
          tester,
          width,
          candidates: _candidates,
          preselected: const {11, 12},
        );

        // ‏18,000 + 8,400 = 26,400 — محسوبةٌ بيد.
        expect(find.text('26400.00'), findsOneWidget);

        await tester.tap(find.textContaining('5540'));
        await tester.pumpAndSettle();

        // وبعد الرفع 18,000 بالضبط — لا «أقلّ من قبل».
        expect(find.text('18000.00'), findsOneWidget);
        expect(find.text('26400.00'), findsNothing);

        expect(tester.takeException(), isNull);
      });

      testWidgets('بلا اختيارٍ ⇒ الحفظُ معطَّلٌ ويُقال السبب', (tester) async {
        await _open(tester, width, candidates: _candidates);

        expect(find.text('اختر شيكاً واحداً على الأقلّ'), findsOneWidget);
        // ‏`PicPosDialog._primary` يرسم `ElevatedButton.icon` — والزرُّ
        //    المعطَّلُ هو `onPressed == null` لا زرٌّ غائب.
        final btn = tester.widget<ElevatedButton>(
          find.ancestor(
            of: find.text('إيداع'),
            matching: find.byType(ElevatedButton),
          ),
        );
        expect(btn.onPressed, isNull);

        expect(tester.takeException(), isNull);
      });

      testWidgets('لا مرشَّحين ⇒ يُقال ذلك ولا يُعرَض زرُّ إيداعٍ يعمل',
          (tester) async {
        await _open(tester, width, candidates: const []);

        expect(
          find.textContaining('لا أوراقَ بالخزنة قابلةً للإيداع'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      });

      testWidgets('الحفظُ يُرجع المعرِّفاتِ والبنكَ ورقمَ القسيمة',
          (tester) async {
        final captured = await _open(
          tester,
          width,
          candidates: _candidates,
          preselected: const {11},
        );

        await tester.enterText(
          find.widgetWithText(TextField, 'رقم قسيمة الإيداع'),
          'DEP-2026-0142',
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('إيداع 1 شيك'));
        await tester.pumpAndSettle();

        // ⚠️ ما يصل المستودعَ لا ما يظهر: الحوارُ يُرجع المعرِّفاتِ لا
        //    الأرقامَ المطبوعةَ على الشيكات.
        final form = captured.form;
        expect(form, isNotNull);
        expect(form!.paperIds, [11]);
        expect(form.bankSafeId, 4);
        expect(form.voucherNumber, 'DEP-2026-0142');
      });
    });
  }
}
