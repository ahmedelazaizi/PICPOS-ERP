// ═══════════════════════════════════════════════════════════════════════════
// مجموع صف السلة — لازم يطابق اللي الفاتورة بتحسبه
// ═══════════════════════════════════════════════════════════════════════════
//
// البلاغ: صنف بسعر ٥ وكمية ٧ وخصم ٠ كان بيعرض في عمود «المجموع» **٤٠.٦٠٠**،
// والمجموع الفرعي والإجمالي النهائي الاتنين **٣٥.٠٠٠**.
//
// السبب إن `CartItemEntity.total` بيضيف ضريبة الصف بلا شرط، بينما
// `CalculateInvoiceTotalsUseCase` بيتجاهل ضريبة الصف المخزّنة **عن قصد**
// (سبيك ١٣٧ — BUG-C02/BUG-H01) ويعيد حسابها على الصافي ومشروطة بـ
// `taxEnabled`. فالصف كان بيعرض ضريبة الفاتورة قررت ما تحصّلهاش.
//
// الاختبار ده بيثبّت العلاقة نفسها مش الرقم: **مجموع صفوف السلة لازم يساوي
// الأساس اللي الفاتورة بتشتغل عليه**، سواء الضريبة مقفولة أو مفتوحة.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/domain/entities/cart_item_entity.dart';
import 'package:picpos_erp/domain/usecases/sales/calculate_invoice_totals_usecase.dart';

void main() {
  CartItemEntity item({
    double quantity = 7,
    double unitPrice = 5,
    double discountPercent = 0,
    double taxRate = 16,
  }) =>
      CartItemEntity(
        productId: 1,
        productName: 'لوز أرباع',
        productCode: 'P-1',
        quantity: quantity,
        unitPrice: unitPrice,
        discountPercent: discountPercent,
        taxRate: taxRate,
      );

  group('مجموع صف السلة', () {
    test('حالة البلاغ: ٧ × ٥ بلا خصم = ٣٥ مش ٤٠.٦', () {
      final i = item();

      expect(i.totalBeforeTax, 35);
      // `total` لسه بيشمل الضريبة — ده تعريفه، والمشكلة كانت في **عرضه**
      // في عمود جنب السعر والخصم.
      expect(i.total, 40.6);
    });

    test('الصف المعروض يساوي الكمية × السعر − الخصم', () {
      final i = item(quantity: 4, unitPrice: 25, discountPercent: 10);

      // 4 × 25 = 100، ناقص ١٠٪ = ٩٠
      expect(i.totalBeforeTax, 90);
    });

    test('والضريبة مقفولة: مجموع الصفوف = إجمالي الفاتورة', () {
      final items = [
        item(),
        item(quantity: 2, unitPrice: 10),
      ];

      final totals = CalculateInvoiceTotalsUseCase().execute(
        items: items,
        taxEnabled: false,
      );

      final rowsSum =
          items.fold<double>(0, (s, i) => s + i.totalBeforeTax);

      expect(rowsSum, totals.total,
          reason: 'الصفوف لازم تجمع للإجمالي لما مفيش ضريبة');
      // ولو كنا بنعرض `total` كان المجموع هيبقى أكبر من الفاتورة.
      final wrongSum = items.fold<double>(0, (s, i) => s + i.total);
      expect(wrongSum, greaterThan(totals.total));
    });

    test('والضريبة مفتوحة: مجموع الصفوف = الأساس قبل الضريبة', () {
      final items = [item()];

      final totals = CalculateInvoiceTotalsUseCase().execute(
        items: items,
        taxEnabled: true,
      );

      final rowsSum =
          items.fold<double>(0, (s, i) => s + i.totalBeforeTax);

      // الصفوف بتجمع للأساس، والضريبة سطر مستقل فوقه — ودي القراءة اللي
      // بتخلي الفاتورة مفهومة.
      expect(rowsSum, totals.total - totals.taxAmount);
      expect(totals.taxAmount, greaterThan(0));
    });
  });
}
