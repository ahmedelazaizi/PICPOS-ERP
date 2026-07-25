// ═══════════════════════════════════════════════════════════════════════════
// متطلبات العميل 2026-07-25 · الموجة م3 · ح-8 — نافذة التاريخ في شاشة فواتير
// المبيعات تسرّب يوماً كاملاً.
// ═══════════════════════════════════════════════════════════════════════════
//
// المسند القديم في `_applyFilters`:
//     inv.invoiceDate.isAfter(start.subtract(Duration(days: 1))) &&
//     inv.invoiceDate.isBefore(end.add(Duration(days: 1)))
//
// `start` القادم من منتقي التاريخ هو منتصف ليل يوم البداية، فـ
// `start − يوم` هو منتصف ليل اليوم **السابق** — وكل فاتورة في ذلك اليوم
// تجتاز `isAfter`. النتيجة: «إجمالي المبيعات» يشمل يوماً لم يطلبه المستخدم.
//
// وفي المقابل بطاقة «المحصّل» تستعمل نافذة مختلفة تماماً
// (`getReceiptVouchersTotal(from: start, to: end)` → `BETWEEN start AND end+1`)،
// فبطاقتان في صف واحد تجيبان سؤالين مختلفين.
//
// النافذة الصحيحة الموحّدة: [بداية يوم البداية، بداية اليوم التالي للنهاية).
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart' show DateTimeRange;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/presentation/screens/sales_invoices_controller.dart';

void main() {
  // المستخدم اختار: 2026-07-01 → 2026-07-31
  final range = DateTimeRange(
    start: DateTime(2026, 7, 1),
    end: DateTime(2026, 7, 31),
  );

  test('فاتورة في اليوم السابق للبداية تُستبعد', () {
    expect(
      invoiceDateInRange(DateTime(2026, 6, 30, 8, 0), range),
      isFalse,
      reason: 'تسريب اليوم السابق هو جوهر ح-8',
    );
    expect(
      invoiceDateInRange(DateTime(2026, 6, 30, 23, 59, 59), range),
      isFalse,
      reason: 'آخر لحظة في اليوم السابق ما زالت خارج النطاق',
    );
  });

  test('فاتورة عند بداية اليوم الأول تُحتسب', () {
    expect(invoiceDateInRange(DateTime(2026, 7, 1), range), isTrue);
    expect(invoiceDateInRange(DateTime(2026, 7, 1, 0, 0, 1), range), isTrue);
  });

  test('فاتورة في آخر لحظة من يوم النهاية تُحتسب', () {
    expect(
      invoiceDateInRange(DateTime(2026, 7, 31, 23, 59, 59), range),
      isTrue,
      reason: 'يوم النهاية مشمول بالكامل',
    );
  });

  test('فاتورة في اليوم التالي للنهاية تُستبعد', () {
    expect(invoiceDateInRange(DateTime(2026, 8, 1), range), isFalse);
    expect(invoiceDateInRange(DateTime(2026, 8, 1, 0, 0, 1), range), isFalse);
  });

  test('نطاق ليوم واحد يشمل ذلك اليوم وحده', () {
    final oneDay = DateTimeRange(
      start: DateTime(2026, 7, 15),
      end: DateTime(2026, 7, 15),
    );
    expect(invoiceDateInRange(DateTime(2026, 7, 14, 23, 59), oneDay), isFalse);
    expect(invoiceDateInRange(DateTime(2026, 7, 15, 0, 0), oneDay), isTrue);
    expect(invoiceDateInRange(DateTime(2026, 7, 15, 23, 59), oneDay), isTrue);
    expect(invoiceDateInRange(DateTime(2026, 7, 16, 0, 0), oneDay), isFalse);
  });

  test('نافذة اليوم الواحدة هي مصدر الحقيقة لبطاقتَي المبيعات والمحصّل', () {
    // بطاقة «المحصّل» تستدعي getReceiptVouchersTotal التي تنفّذ داخلياً
    // `BETWEEN from AND to + يوم`. لتتطابق النافذتان يجب أن يُمرَّر
    // `to = بداية يوم النهاية` — لا النهاية الخام (وإلا فتحت 23:59:59
    // اليومَ التالي بالكامل).
    final w = dayWindowFor(range);
    expect(w.start, DateTime(2026, 7, 1));
    expect(w.endExclusive, DateTime(2026, 8, 1));

    // ما يُمرَّر للـ DAO كـ `to`
    final voucherTo = w.endExclusive.subtract(const Duration(days: 1));
    expect(voucherTo, DateTime(2026, 7, 31),
        reason: 'يجعل نافذة السندات [1 يوليو، 1 أغسطس] — نفس نافذة الفواتير');

    // نهاية مُطبَّعة يجب أن تعطي النافذة نفسها بالضبط.
    final wNorm = dayWindowFor(DateTimeRange(
      start: DateTime(2026, 7, 1),
      end: DateTime(2026, 7, 31, 23, 59, 59),
    ));
    expect(wNorm.start, w.start);
    expect(wNorm.endExclusive, w.endExclusive);
  });

  test('نهاية مُطبَّعة لآخر اليوم لا تمدّد النطاق ليوم إضافي', () {
    // بعض المنتقيات تُرجع النهاية كـ 23:59:59 بدل منتصف الليل — يجب أن تعطي
    // النافذة نفسها لا نافذة أطول بيوم.
    final normalized = DateTimeRange(
      start: DateTime(2026, 7, 1),
      end: DateTime(2026, 7, 31, 23, 59, 59),
    );
    expect(invoiceDateInRange(DateTime(2026, 7, 31, 23, 59, 59), normalized),
        isTrue);
    expect(invoiceDateInRange(DateTime(2026, 8, 1), normalized), isFalse,
        reason: 'النهاية المُطبَّعة يجب ألا تفتح يوم 1 أغسطس');
  });
}
