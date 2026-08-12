// المطبوعُ يعرض ما تعرضه الشاشة — بلا بندٍ يسقط في الطريق.
//
// ── فئةُ العطب ────────────────────────────────────────────────────────────
// شاشةُ «تقرير وردية» تقرأ `ShiftClosingSnapshot` مباشرةً فتعرض كلَّ حقلٍ
// فيه. والورقةُ تمرّ بقالبٍ، والقالبُ لا يعرض إلا ما يحلّه
// `TemplatedInvoiceService.resolveShiftValue`. فمفتاحٌ غيرُ مدعومٍ يعني
// بنداً موجوداً على الشاشة وغائباً عن الورقة — والمشغّلُ يقارن الاثنين.
//
// بلاغُ المالك 2026-08-12: «في ural كان الإقفال المطبوع يُظهر إجماليَّ
// الفواتير، وكلَّ بندٍ ماليٍّ ومقابلَه الفعليّ، وتوضيحاً للمبيعات الآجلة
// **بدون جمعها مع الماليات**. والتقرير لازم يكون واضحاً في الورديات
// والإقفال والعرض.»
//
// والآجلُ خصوصاً حسّاس: هو مبيعاتٌ لم تُقبَض، فضمُّه لتسوية الخزائن يخلق
// عجزاً وهمياً. يُعرض للتوضيح ويبقى خارج `shift_total_system`.

import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/domain/entities/shift_closing_snapshot.dart';
import 'package:ural_erp/services/templated_invoice_service.dart';

void main() {
  final snapshot = ShiftClosingSnapshot(
    invoiceCount: 3,
    totalSales: 260,
    systemCash: 100,
    systemCard: 60,
    systemClick: 50,
    actualCash: 100,
    actualCard: 60,
    actualClick: 50,
    cashVariance: 0,
    cardVariance: 0,
    clickVariance: 0,
    totalVariance: 0,
    totalExpenses: 0,
    cashRefunds: 0,
    cashIncome: 100,
    creditSales: 50,
    creditSalesCount: 1,
    openingBalance: 25,
    closedAt: DateTime(2026, 8, 12),
  );

  /// البنودُ الستّةُ التي يعرضها قسمُ «الحركة» على الشاشة
  /// (`picpos_past_shifts_panel.dart`) — واحداً بواحد.
  const movementKeys = {
    'shift_opening_balance': '25.00',
    'shift_total_sales': '260.00',
    'shift_cash_income': '100.00',
    'shift_total_expenses': '0.00',
    'shift_cash_refunds': '0.00',
    'shift_credit_sales': '50.00',
  };

  test('كلُّ بندِ حركةٍ على الشاشة له مفتاحٌ يحلّه القالب', () {
    for (final entry in movementKeys.entries) {
      expect(
        TemplatedInvoiceService.resolveShiftValue(entry.key, snapshot),
        entry.value,
        reason: '${entry.key} — موجودٌ على الشاشة وغائبٌ عن الورقة',
      );
    }
  });

  test('عددُ الفواتير الآجلة يُعرض كعدد', () {
    expect(
      TemplatedInvoiceService.resolveShiftValue('shift_credit_count', snapshot),
      '1',
    );
  });

  test('الآجلُ **خارج** تسوية الخزائن — وإلا فعجزٌ وهميّ', () {
    // ١٠٠ + ٦٠ + ٥٠ = ٢١٠ متحصَّل. والمبيعاتُ ٢٦٠ لأن فيها ٥٠ آجلاً.
    expect(
      TemplatedInvoiceService.resolveShiftValue('shift_total_system', snapshot),
      '210.00',
    );
    expect(
      TemplatedInvoiceService.resolveShiftValue('shift_total_actual', snapshot),
      '210.00',
    );
    // فالحالةُ «مطابق» رغم أن المبيعات ٢٦٠ — وهذا هو الصواب.
    expect(
      TemplatedInvoiceService.resolveShiftValue('shift_status', snapshot),
      'مطابق',
    );
  });
}
