// صفُّ أمرِ الشراء في قائمة المشتريات — **لا يدّعي ما ليس فيه.**
//
// قرارُ المالك 2026-09-18: مرشِّحُ «نوع المستند» يفرّق فاتورة شراء / أمر
// شراء، فالقائمةُ تحمل النوعَين.
//
// ═══ فئةُ العطب التي يحرسها هذا الاختبار ═══
//
// أمرُ الشراء **ليس فاتورةً ناقصة**: لا مسدَّدَ له ولا متبقّي ولا قيدَ في
// الأستاذ. فلو رُسم ببطاقة الفاتورة لظهر:
//   • «مدفوع ٠ من ٥٠٠٠» على التزامٍ لم يُستلَم بعد — وصفرٌ في خانة سدادٍ
//     يُقرأ «متأخّراً» لا «غيرَ منطبق».
//   • و«غير مُرحَّل» حمراءَ على مستندٍ **لا يُرحَّل أصلاً** — إنذارٌ ماليٌّ
//     على شيءٍ سليم.
//
// فالخانتان تُرسَمان «—» بتلميحَيهما، وحالةُ الأمر وسمٌ بجوار رقمه.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/domain/entities/invoice_entity.dart';
import 'package:ural_erp/domain/models/purchase_doc.dart';
import 'package:ural_erp/presentation/purchases_picpos/screens/purchases_picpos_screen.dart';
import 'package:ural_erp/presentation/screens/purchases/purchase_invoices_controller.dart';

InvoiceEntity _inv(int id, String number, DateTime date) => InvoiceEntity(
      id: id,
      invoiceNumber: number,
      type: InvoiceType.purchase,
      partyId: 7,
      invoiceDate: date,
      lines: const [],
      subtotal: 900,
      total: 900,
      paid: 900,
      status: InvoiceStatus.paid,
    );

PurchaseOrderRow _ord(int id, String number, DateTime date) => PurchaseOrderRow(
      id: id,
      orderNumber: number,
      supplierId: 7,
      orderDate: date,
      total: 5000,
      status: 'confirmed',
    );

class _FrozenController extends PurchaseInvoicesController {
  _FrozenController(this._docs, this._invoices);
  final List<PurchaseDoc> _docs;
  final List<InvoiceEntity> _invoices;

  @override
  PurchaseInvoicesScreenState build() => PurchaseInvoicesScreenState(
        isLoading: false,
        allInvoices: _invoices,
        filteredInvoices: _invoices,
        filteredDocs: _docs,
        supplierNames: const {7: 'مؤسسة التوريد'},
        postedInvoiceIds: const {1},
      );
}

Future<void> _pump(
  WidgetTester tester, {
  required List<PurchaseDoc> docs,
  required List<InvoiceEntity> invoices,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        purchaseInvoicesControllerProvider
            .overrideWith(() => _FrozenController(docs, invoices)),
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
  final invoice = _inv(1, 'PINV-0201', DateTime(2026, 9, 10));
  final order = _ord(9, 'PO-0044', DateTime(2026, 9, 8));

  testWidgets('مرساةٌ — النوعان يظهران في قائمةٍ واحدة', (tester) async {
    await _pump(
      tester,
      docs: [PurchaseInvoiceDoc(invoice), PurchaseOrderDoc(order)],
      invoices: [invoice],
    );
    expect(find.text('PINV-0201'), findsOneWidget);
    expect(find.text('PO-0044'), findsOneWidget,
        reason: 'أمرُ الشراء لم يُرسَم — كلُّ ما تحته يقيس لا شيء');
  });

  testWidgets('وصفُّ الأمر موسومٌ بنوعه وبدورة حياته', (tester) async {
    await _pump(
      tester,
      docs: [PurchaseInvoiceDoc(invoice), PurchaseOrderDoc(order)],
      invoices: [invoice],
    );
    expect(find.text('أمر شراء'), findsOneWidget);
    expect(find.text('مؤكَّد'), findsOneWidget,
        reason: 'حالةُ الأمر الخمسُ لا تظهر — والقارئُ لا يعرف أوصل أم لا');
  });

  testWidgets('ولا يُوصَم الأمرُ بحالة ترحيلٍ أو سداد', (tester) async {
    await _pump(
      tester,
      docs: [PurchaseOrderDoc(order)],
      invoices: const [],
    );
    // ⚠️ لا «غير مُرحَّل» حمراءَ على مستندٍ لا يُرحَّل أصلاً.
    expect(find.text('غير مُرحَّل'), findsNothing);
    expect(find.text('مُرحَّل'), findsNothing);
    // ولا رقمَ سدادٍ: صفرٌ في خانة سدادٍ يُقرأ «متأخّراً».
    expect(find.text('مدفوع'), findsNothing);
    expect(
      find.byTooltip('أمرُ الشراء التزامٌ — لا سدادَ عليه حتى يُفوتَر'),
      findsOneWidget,
    );
    expect(
      find.byTooltip('أمرُ الشراء لا يُرحَّل إلى دفتر الأستاذ'),
      findsOneWidget,
    );
  });

  testWidgets('والفاتورةُ في نفس القائمة تحتفظ بعموديها', (tester) async {
    await _pump(
      tester,
      docs: [PurchaseInvoiceDoc(invoice), PurchaseOrderDoc(order)],
      invoices: [invoice],
    );
    expect(find.text('مُرحَّل'), findsOneWidget,
        reason: 'وجودُ أمرٍ في القائمة أسقط عمودَ الفاتورة');
    expect(find.text('مدفوع'), findsOneWidget);
  });

  testWidgets('و«تحديد الكل» لا يكتمل بصفوفٍ لا تُحدَّد', (tester) async {
    // ⚠️ الأوامرُ لا خانةَ تحديدٍ لها لأنّ الأفعالَ المجمّعة (طباعةٌ وحذف)
    // مبنيّةٌ على الفواتير. ولو دخلت المقامَ لما اكتمل «تحديدُ الكل» أبداً.
    await _pump(
      tester,
      docs: [PurchaseInvoiceDoc(invoice), PurchaseOrderDoc(order)],
      invoices: [invoice],
    );
    final boxes = find.byType(Checkbox);
    expect(boxes, findsNWidgets(2),
        reason: 'المتوقَّعُ اثنتان: رأسُ الجدول وصفُّ الفاتورة وحدَه');
  });
}
