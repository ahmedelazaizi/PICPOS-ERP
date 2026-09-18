// عمودُ «حالة الترحيل» — **يقرأ الأستاذَ، ولا يدّعي علماً لا يملكه.**
//
// ═══ لماذا لا `isLocked` ═══
//
// قرارُ المالك 2026-09-18: «الحالة» عمودان — اعتمادٌ وسداد. والمرشَّحُ
// الوحيدُ لعمود الاعتماد كان `isLocked`، **وهو يكذب في ثلاث حالات**:
//
//   • `createPurchaseInvoice` يرحّل قيدَه مُدمَجاً و**لا يرفعها قطّ** —
//     موثَّقٌ حرفيّاً في `purchase_dao.dart` عند مسار الإلغاء.
//   • `autoPostPurchase` يرفعها.
//   • **والإلغاءُ يرفعها أيضاً** (‏`isLocked: const Value(true)` مع
//     `isDeleted`).
//
// فعمودٌ مبنيٌّ عليها يكتب «مسودة» على فاتورةٍ قيدُها في الأستاذ، و«معتمد»
// على ملغاة. وتعليقان في **نفس الملفّ** يتناقضان في وصفها: أحدُهما يسمّيها
// «the posted-state marker» والآخرُ يقول إنّ المسارَ الأساسيَّ لا يرفعها.
//
// ⚠️ **والحالةُ الثالثةُ ليست ترفاً:** `null` = «لم يُعرَف بعد»، لأنّ
// الاستعلامَ يصل بعد التحميل الأوّل وقد يُخفق. ورسمُ «غير مُرحَّل» حمراءَ
// حينئذٍ يصبغ **كلَّ** الصفوف بإنذارٍ ماليٍّ كاذب — وهو أسوأُ من لا شيء.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/domain/entities/invoice_entity.dart';
import 'package:ural_erp/domain/models/purchase_doc.dart';
import 'package:ural_erp/presentation/purchases_picpos/screens/purchases_picpos_screen.dart';
import 'package:ural_erp/presentation/screens/purchases/purchase_invoices_controller.dart';

InvoiceEntity _inv(int id, String number) => InvoiceEntity(
      id: id,
      invoiceNumber: number,
      type: InvoiceType.purchase,
      invoiceDate: DateTime(2026, 9, 8),
      lines: const [],
      subtotal: 900,
      total: 900,
      paid: 900,
      status: InvoiceStatus.paid,
      // ⚠️ **مرفوعةٌ عمداً على الاثنتين.** لو كان العمودُ ما زال يقرؤها
      // لقال «معتمد» على الاثنتين ولَما فرّق — فهذه هي الطفرةُ مبنيّةً في
      // المعطيات: العمودُ الصادقُ وحدَه يفرّق بينهما.
      isLocked: true,
    );

class _FrozenController extends PurchaseInvoicesController {
  _FrozenController(this._posted);
  final Set<int>? _posted;

  @override
  PurchaseInvoicesScreenState build() => PurchaseInvoicesScreenState(
        isLoading: false,
        allInvoices: [_inv(1, 'PINV-0201'), _inv(2, 'PINV-0202')],
        filteredInvoices: [_inv(1, 'PINV-0201'), _inv(2, 'PINV-0202')],
        // الجدولُ يرسم `filteredDocs` — القائمةَ المدموجة — لا
        // `filteredInvoices`؛ فتركُها فارغةً يعرض حالةَ «لا نتائج».
        filteredDocs: [
          PurchaseInvoiceDoc(_inv(1, 'PINV-0201')),
          PurchaseInvoiceDoc(_inv(2, 'PINV-0202')),
        ],
        postedInvoiceIds: _posted,
      );
}

Future<void> _pump(WidgetTester tester, Set<int>? posted) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        purchaseInvoicesControllerProvider
            .overrideWith(() => _FrozenController(posted)),
      ],
      child: MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: Column(
              children: [
                PurchasesInvoicesTable(
                  onView: (_) {},
                  onEdit: (_) {},
                  onPrint: (_) {},
                  canEdit: true,
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('مرساةٌ — الصفّان رُسما فعلاً', (tester) async {
    await _pump(tester, const {1});
    expect(find.text('PINV-0201'), findsOneWidget);
    expect(find.text('PINV-0202'), findsOneWidget,
        reason: 'الجدولُ لم يرسم الصفَّين — كلُّ ما تحته يقيس لا شيء');
  });

  testWidgets('و«الحالة» عمودان بعنوانَين متمايزَين', (tester) async {
    await _pump(tester, const {1});
    expect(find.text('حالة الترحيل'), findsOneWidget);
    expect(find.text('حالة السداد'), findsOneWidget);
    expect(find.text('الحالة'), findsNothing,
        reason: 'بقي العنوانُ المبهَم — وهو ما طلب المالكُ فصلَه');
  });

  testWidgets('ويفرّق بين المُرحَّل وغيرِه — والاثنتان isLocked',
      (tester) async {
    await _pump(tester, const {1});
    expect(find.text('مُرحَّل'), findsOneWidget);
    expect(find.text('غير مُرحَّل'), findsOneWidget,
        reason: 'لم يُميَّز صفٌّ بلا قيد — العمودُ يقرأ الرايةَ لا الأستاذ');
  });

  testWidgets('ولا قيدَ لأيٍّ منهما ⇒ كلاهما «غير مُرحَّل»', (tester) async {
    await _pump(tester, const {});
    expect(find.text('غير مُرحَّل'), findsNWidgets(2));
    expect(find.text('مُرحَّل'), findsNothing);
  });

  testWidgets('و«لم يُعرَف بعد» لا يُرسَم إنذاراً', (tester) async {
    // ⚠️ هذا هو الفرقُ بين `null` والمجموعة الفارغة، وهو الفرقُ بين
    // «لا نعلم» و«لا شيءَ مُرحَّل» — والثانيةُ تُقلق محاسباً بلا سبب.
    await _pump(tester, null);
    expect(find.text('غير مُرحَّل'), findsNothing,
        reason: 'إنذارٌ ماليٌّ كاذبٌ على كلّ صفٍّ قبل وصول الجواب');
    expect(find.text('مُرحَّل'), findsNothing);
    // ⚠️ ولا يُبحَث عن «—» نصّاً: خليّةُ مركز التكلفة ترسمها أيضاً حين
    // يغيب المركز (Spec 119)، فستّةُ مطابقاتٍ تظهر لصفَّين. والتلميحُ
    // يخصّ هذا الوسمَ وحدَه.
    expect(
      find.byTooltip('حالة الترحيل قيد القراءة من دفتر الأستاذ'),
      findsNWidgets(2),
    );
  });
}
