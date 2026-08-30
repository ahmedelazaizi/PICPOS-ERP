import 'package:flutter/foundation.dart';

import '../../data/database/database.dart';
import '../../domain/entities/shift_closing_snapshot.dart';
import '../../domain/repositories/printers_repository.dart';
import '../invoice_generator.dart';
import '../templated_invoice_service.dart';

/// Prints a shift-closing report from a [ShiftClosingSnapshot].
///
/// Both the close path and the reprint path go through here, which is what
/// guarantees a reprint is the same document rather than a lookalike rebuilt
/// from a second set of assumptions. The close path builds the snapshot,
/// persists it, and prints from it; the reprint path loads the stored one and
/// prints from that.
/// [db] — حين يُمرَّر ويوجد قالبٌ افتراضيٌّ من نوع `shift_closing`، يُطبع
/// التقريرُ **بالقالب** الذي صمّمه المستخدم. وإلا فالمولّدُ الثابتُ كما كان.
///
/// كان المحرِّرُ يعرض نوعَ القالب هذا وستّةَ عشرَ عنصراً تحته، والبذرةُ تزرع
/// قالباً افتراضياً باسمه — ولا شيءَ يقرؤه. فالتصميمُ يُحفظ ولا يُرى.
/// (‏`printing_service.dart` يسأل السؤالَ نفسَه للفواتير منذ البداية.)
Future<void> printShiftClosingSnapshot({
  required ShiftClosingSnapshot snapshot,
  double fontScale = 1.0,
  IPrintersRepository? printersRepo,
  AppDatabase? db,
}) async {
  if (db != null) {
    try {
      if (await TemplatedInvoiceService.hasDefaultTemplate(db, 'shift_closing')) {
        await TemplatedInvoiceService.printWithTemplate(
          db: db,
          type: 'shift_closing',
          category: 'shift_closing',
          documentType: 'shift_closing',
          // ⚠️ `printWithTemplate` افتراضُها `directPrint: false` — أي أنّها
          // تفتح ديالوجَ طباعة ويندوز. وكلُّ نظائرِها تمرّر `true`
          // (`printing_service.dart` للفواتير، و`invoice_generator.dart`)،
          // وهذا النداءُ وحدَه أغفلها. فتقريرُ إقفال الوردية كان يوقف
          // الكاشيرَ بديالوجٍ في **كلِّ** إغلاق — والإقفالُ لحظةُ ازدحامٍ
          // بطبيعته.
          directPrint: true,
          shift: snapshot,
          // تقريرُ الوردية ليس فاتورة: لا بنودَ ولا مبالغَ فاتورة. القيمُ
          // المعروضةُ كلُّها من اللقطة عبر `resolveShiftValue`.
          invoiceNumber: '',
          date: snapshot.closedAt ?? DateTime.now(),
          customerName: null,
          customerPhone: null,
          customerAddress: null,
          items: const [],
          subtotal: 0,
          discount: 0,
          tax: 0,
          deliveryFee: 0,
          total: snapshot.totalSales,
          paid: snapshot.totalSales,
          companyName: snapshot.companyName ?? '',
          companyAddress: '',
          companyPhone: '',
          companyTaxId: null,
          cashierName: snapshot.employeeName,
        );
        return;
      }
    } catch (e) {
      // القالبُ إضافةٌ لا استبدال: أيُّ عطبٍ فيه لا يمنع طباعةَ الإقفال.
      debugPrint('[ShiftClosing] template print failed, falling back: $e');
    }
  }

  return InvoiceGenerator.printShiftClosingReport(
    invoiceCount: snapshot.invoiceCount,
    totalSales: snapshot.totalSales,
    systemCash: snapshot.systemCash,
    systemCard: snapshot.systemCard,
    actualCash: snapshot.actualCash,
    actualCard: snapshot.actualCard,
    cashVariance: snapshot.cashVariance,
    cardVariance: snapshot.cardVariance,
    totalVariance: snapshot.totalVariance,
    systemClick: snapshot.systemClick,
    actualClick: snapshot.actualClick,
    clickVariance: snapshot.clickVariance,
    totalExpenses: snapshot.totalExpenses,
    cashRefunds: snapshot.cashRefunds,
    cashIncome: snapshot.cashIncome,
    creditSales: snapshot.creditSales,
    creditSalesCount: snapshot.creditSalesCount,
    openingBalance: snapshot.openingBalance,
    fontScale: fontScale,
    employeeName: snapshot.employeeName,
    companyName: snapshot.companyName,
    printersRepo: printersRepo,
  );
}
