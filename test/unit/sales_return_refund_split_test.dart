// ═══════════════════════════════════════════════════════════════════════════
// تقسيمُ مرتجعِ المبيعات — الحسابُ الخالص
// ═══════════════════════════════════════════════════════════════════════════
//
// المواصفة: docs/superpowers/specs/2026-08-18-sales-return-cash-shift-rule-design.md
// (اختبارُ ٩ و١٠)
//
// الغرضُ الأوّل: تثبيتُ السلوك **قبل** أن يُستخرَج الحسابُ من
// `returns_repository_impl` — فالاستخراجُ نقلٌ لا تصحيح، وهذه الحالاتُ هي
// البرهانُ على ذلك.
//
// والغرضُ الثاني: أن يعتمد الحارسُ على نفسِ هذا الحساب. فحين يقول
// `requiresOpenShift` «نعم» يكون المسارُ سيُخرِج نقداً فعلاً — لا تخميناً
// موازياً ينحرف يوماً عن السلوك.

import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/domain/models/sales_return_refund_split.dart';

/// مختصرٌ يملأ ما لا تعنيه الحالةُ المختبَرة.
SalesReturnRefundSplit split({
  required double invoiceTotal,
  required double invoicePaid,
  required String? paymentMethod,
  required double totalReturn,
  double cashPaid = 0,
  double bankPaid = 0,
  bool hasCustomer = true,
}) =>
    SalesReturnRefundSplit.from(
      invoiceTotal: invoiceTotal,
      invoicePaid: invoicePaid,
      paymentMethod: paymentMethod,
      cashPaid: cashPaid,
      bankPaid: bankPaid,
      totalReturn: totalReturn,
      hasCustomer: hasCustomer,
    );

void main() {
  group('الفاتورةُ مدفوعةٌ بالكامل — لا ذمّةَ تُقاصّ', () {
    test('نقداً ⇒ المرتجعُ كلُّه نقدٌ من الدرج', () {
      final s = split(
        invoiceTotal: 100,
        invoicePaid: 100,
        paymentMethod: 'cash',
        totalReturn: 40,
      );

      expect(s.arRefund, 0);
      expect(s.cashRefund, 40);
      expect(s.bankRefund, 0);
      expect(s.requiresOpenShift, isTrue, reason: 'نقدٌ يخرج ⇒ يشترط ورديّة');
    });

    for (final method in ['transfer', 'card', 'bank']) {
      test('$method ⇒ المرتجعُ كلُّه بنكيٌّ ولا يشترط ورديّة', () {
        final s = split(
          invoiceTotal: 100,
          invoicePaid: 100,
          paymentMethod: method,
          totalReturn: 40,
        );

        expect(s.bankRefund, 40);
        expect(s.cashRefund, 0);
        expect(s.requiresOpenShift, isFalse,
            reason: 'الخزنةُ البنكيّةُ ليست درجاً، ولا تدخل expectedCash');
      });
    }
  });

  group('الفاتورةُ غيرُ مسدَّدة — الذمّةُ تُقاصّ أوّلاً', () {
    test('آجلٌ بالكامل ⇒ كلُّه ذمّةٌ ولا نقدَ يخرج', () {
      final s = split(
        invoiceTotal: 100,
        invoicePaid: 0,
        paymentMethod: 'credit',
        totalReturn: 100,
      );

      expect(s.arRefund, 100);
      expect(s.cashRefund, 0);
      expect(s.actualRefundToPay, 0);
      expect(s.requiresOpenShift, isFalse,
          reason: 'لم يدفع العميلُ شيئاً، فلا نقدَ يُعاد ⇒ لا ورديّةَ تُشترط');
    });

    test('مدفوعةٌ جزئيّاً ومرتجعٌ كامل ⇒ الباقي ذمّةٌ والمدفوعُ نقد', () {
      final s = split(
        invoiceTotal: 100,
        invoicePaid: 60,
        paymentMethod: 'cash',
        totalReturn: 100,
      );

      expect(s.arRefund, 40, reason: 'المتبقّي على العميل يُقاصّ');
      expect(s.cashRefund, 60, reason: 'وما دفعه يُعاد إليه نقداً');
      expect(s.arRefund + s.cashRefund + s.bankRefund, 100);
    });

    test('مرتجعٌ أصغرُ من المتبقّي ⇒ ذمّةٌ خالصةٌ بلا نقد', () {
      final s = split(
        invoiceTotal: 100,
        invoicePaid: 0,
        paymentMethod: 'credit',
        totalReturn: 30,
      );

      expect(s.arRefund, 30);
      expect(s.actualRefundToPay, 0);
    });

    test('بلا عميل ⇒ لا مقاصّةَ ذمّةٍ ولو كانت غيرَ مسدَّدة', () {
      final s = split(
        invoiceTotal: 100,
        invoicePaid: 0,
        paymentMethod: 'cash',
        totalReturn: 100,
        hasCustomer: false,
      );

      expect(s.arRefund, 0);
      expect(s.cashRefund, 100,
          reason: 'لا ذمّةَ تُقاصّ فيخرج المرتجعُ كلُّه دفعاً — سلوكُ المسار الأصليّ');
    });
  });

  group('الدفعُ المختلط — تناسبٌ بما قُبض فعلاً', () {
    test('نصفٌ نقدٌ ونصفٌ بنك ⇒ يُقسَم بنفس النسبة', () {
      final s = split(
        invoiceTotal: 100,
        invoicePaid: 100,
        paymentMethod: 'multiple',
        cashPaid: 60,
        bankPaid: 40,
        totalReturn: 50,
      );

      expect(s.cashRefund, closeTo(30, 0.001));
      expect(s.bankRefund, closeTo(20, 0.001));
      expect(s.requiresOpenShift, isTrue);
    });

    test("'mixed' يُعامَل معاملةَ 'multiple'", () {
      final s = split(
        invoiceTotal: 100,
        invoicePaid: 100,
        paymentMethod: 'mixed',
        cashPaid: 25,
        bankPaid: 75,
        totalReturn: 100,
      );

      expect(s.cashRefund, closeTo(25, 0.001));
      expect(s.bankRefund, closeTo(75, 0.001));
    });

    test('مختلطةٌ ولم يُقبض منها شيء ⇒ نقداً (حالةٌ شاذّةٌ منقولةٌ كما هي)', () {
      final s = split(
        invoiceTotal: 100,
        invoicePaid: 100,
        paymentMethod: 'multiple',
        cashPaid: 0,
        bankPaid: 0,
        totalReturn: 40,
      );

      expect(s.cashRefund, 40);
      expect(s.bankRefund, 0);
    });
  });

  group('حدودٌ ومصائد', () {
    // كان هذا الاختبارُ يوثّق فرقاً قائماً؛ صار يحرس توحيدَه.
    //
    // القائمةُ واحدةٌ الآن في `kBankPaymentMethods`، فبيعةُ visa ومرتجعُها
    // يقعان على الخزنة نفسِها. وقبل التوحيد كانت البيعةُ تدخل الخزنةَ
    // البنكيّة والمرتجعُ يخرج من الدرج: عجزٌ في درجٍ ورصيدٌ بنكيٌّ وهميّ، ولا
    // يتقاصّان أبداً.
    for (final method in ['visa', 'mastercard', 'amex', 'mada', 'stcpay']) {
      test('$method ⇒ بنكيٌّ لا نقديّ (كان يخرج من الدرج قبل التوحيد)', () {
        final s = split(
          invoiceTotal: 100,
          invoicePaid: 100,
          paymentMethod: method,
          totalReturn: 40,
        );

        expect(s.bankRefund, 40,
            reason: 'يعود من حيث قُبض — الخزنةُ البنكيّة');
        expect(s.cashRefund, 0, reason: 'ولا يمسّ الدرجَ إطلاقاً');
        expect(s.requiresOpenShift, isFalse,
            reason: 'فلا ورديّةَ تُشترط');
      });
    }

    test('paymentMethod غائبة ⇒ نقداً', () {
      final s = split(
        invoiceTotal: 100,
        invoicePaid: 100,
        paymentMethod: null,
        totalReturn: 10,
      );

      expect(s.cashRefund, 10);
    });

    test('فاتورةٌ دُفع فيها أكثرُ من قيمتها ⇒ لا ذمّةَ سالبة', () {
      final s = split(
        invoiceTotal: 100,
        invoicePaid: 120,
        paymentMethod: 'cash',
        totalReturn: 50,
      );

      expect(s.arRefund, 0, reason: 'clamp يمنع متبقّياً سالباً');
      expect(s.cashRefund, 50);
    });

    test('مرتجعٌ صفريّ ⇒ لا شيءَ يتحرّك ولا ورديّةَ تُشترط', () {
      final s = split(
        invoiceTotal: 100,
        invoicePaid: 100,
        paymentMethod: 'cash',
        totalReturn: 0,
      );

      expect(s.cashRefund, 0);
      expect(s.requiresOpenShift, isFalse);
    });
  });

  test('الحاصلاتُ الثلاثةُ مجموعُها المرتجعُ دائماً', () {
    final cases = [
      split(invoiceTotal: 100, invoicePaid: 60, paymentMethod: 'cash', totalReturn: 100),
      split(invoiceTotal: 250, invoicePaid: 100, paymentMethod: 'credit', totalReturn: 175),
      split(
        invoiceTotal: 80,
        invoicePaid: 80,
        paymentMethod: 'multiple',
        cashPaid: 30,
        bankPaid: 50,
        totalReturn: 80,
      ),
      split(invoiceTotal: 40, invoicePaid: 40, paymentMethod: 'bank', totalReturn: 15),
    ];
    final expected = [100.0, 175.0, 80.0, 15.0];

    for (var i = 0; i < cases.length; i++) {
      final s = cases[i];
      expect(s.arRefund + s.cashRefund + s.bankRefund, closeTo(expected[i], 0.001),
          reason: 'الحالة $i: $s');
      expect(s.actualRefundToPay, closeTo(s.cashRefund + s.bankRefund, 0.001),
          reason: 'الحالة $i: المدفوعُ = نقدٌ + بنك');
    }
  });
}
