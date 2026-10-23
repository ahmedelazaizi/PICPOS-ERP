// دمجُ الفواتير وأوامر الشراء في قائمةٍ واحدة — الترتيبُ والمرشِّح والحدود.
//
// قرارُ المالك 2026-09-18: مرشِّحُ «نوع المستند» يفرّق **فاتورة شراء / أمر
// شراء** — لا فاتورة/مردود.
//
// ═══ ما يُقاس هنا ═══
//
// الدمجُ حسابٌ خالصٌ بلا قاعدةٍ ولا شجرةِ ودجت، فيُقاس مباشرةً: الترتيبُ
// بالأحدث عبر النوعَين معاً (لا نوعاً ثمّ نوعاً)، والمرشِّحُ يُسقط ما لا
// يخصّه، والحالاتُ الحدّيّة (قائمةٌ فارغة · تواريخُ متساوية).

import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/domain/entities/invoice_entity.dart';
import 'package:picpos_erp/domain/models/purchase_doc.dart';

InvoiceEntity _inv(String number, DateTime date) => InvoiceEntity(
      invoiceNumber: number,
      type: InvoiceType.purchase,
      invoiceDate: date,
      lines: const [],
      subtotal: 100,
      total: 100,
      paid: 0,
      status: InvoiceStatus.pending,
    );

PurchaseOrderRow _ord(String number, DateTime date, {int? convertedTo}) =>
    PurchaseOrderRow(
      id: number.hashCode,
      orderNumber: number,
      supplierId: 1,
      orderDate: date,
      total: 500,
      status: 'confirmed',
      convertedToInvoiceId: convertedTo,
    );

List<String> _numbers(List<PurchaseDoc> docs) => [
      for (final d in docs)
        switch (d) {
          PurchaseInvoiceDoc(:final invoice) => invoice.invoiceNumber,
          PurchaseOrderDoc(:final order) => order.orderNumber,
        },
    ];

void main() {
  test('يتشابك النوعان في ترتيبٍ واحدٍ بالأحدث', () {
    // ⚠️ **وهذا هو الفحصُ الذي يعني شيئاً.** إلحاقُ الأوامر بعد الفواتير
    // يمرّ من أيّ فحصِ «عددُ الصفوف = ٤»؛ والخطأُ لا يُرى إلّا حين يقع
    // أمرٌ **بين** فاتورتَين بالتاريخ.
    final docs = mergePurchaseDocs(
      invoices: [
        _inv('PINV-1', DateTime(2026, 9, 10)),
        _inv('PINV-2', DateTime(2026, 9, 6)),
      ],
      orders: [
        _ord('PO-1', DateTime(2026, 9, 8)),
        _ord('PO-2', DateTime(2026, 9, 4)),
      ],
    );
    expect(_numbers(docs), ['PINV-1', 'PO-1', 'PINV-2', 'PO-2']);
  });

  test('ومرشِّحُ «فاتورة شراء» يُسقط الأوامرَ كلَّها', () {
    final docs = mergePurchaseDocs(
      invoices: [_inv('PINV-1', DateTime(2026, 9, 10))],
      orders: [_ord('PO-1', DateTime(2026, 9, 11))],
      typeFilter: PurchaseDocTypeFilter.invoice,
    );
    expect(_numbers(docs), ['PINV-1'],
        reason: 'أمرٌ أحدثُ تاريخاً تسلّل رغم المرشِّح');
  });

  test('ومرشِّحُ «أمر شراء» يُسقط الفواتيرَ كلَّها', () {
    final docs = mergePurchaseDocs(
      invoices: [_inv('PINV-1', DateTime(2026, 9, 10))],
      orders: [_ord('PO-1', DateTime(2026, 9, 4))],
      typeFilter: PurchaseDocTypeFilter.order,
    );
    expect(_numbers(docs), ['PO-1']);
  });

  test('و«الكل» هو الافتراض', () {
    final docs = mergePurchaseDocs(
      invoices: [_inv('PINV-1', DateTime(2026, 9, 10))],
      orders: [_ord('PO-1', DateTime(2026, 9, 4))],
    );
    expect(docs, hasLength(2));
  });

  test('وقائمتان فارغتان ⇒ قائمةٌ فارغةٌ لا استثناء', () {
    expect(mergePurchaseDocs(invoices: const [], orders: const []), isEmpty);
  });

  test('والمستندُ يُعلن مورِدَه وتاريخَه أيّاً كان نوعُه', () {
    // المرشِّحاتُ وأسماءُ الموردين تقرأ هذين الحقلَين من الواجهة المجرّدة،
    // فلو أعاد أحدُ الفرعَين صفراً أو تاريخاً خاطئاً لانكسر الترتيبُ صامتاً.
    final invDoc = PurchaseInvoiceDoc(
      _inv('PINV-9', DateTime(2026, 9, 3)).copyWith(partyId: 77),
    );
    expect(invDoc.supplierId, 77);
    expect(invDoc.date, DateTime(2026, 9, 3));

    final ordDoc = PurchaseOrderDoc(_ord('PO-9', DateTime(2026, 9, 2)));
    expect(ordDoc.supplierId, 1);
    expect(ordDoc.date, DateTime(2026, 9, 2));
  });

  test('و«حُوِّل إلى فاتورة» يُشتقُّ من العمود لا يُفترَض', () {
    expect(_ord('PO-1', DateTime(2026, 9, 2)).isConverted, isFalse);
    expect(
      _ord('PO-2', DateTime(2026, 9, 2), convertedTo: 55).isConverted,
      isTrue,
    );
  });
}
