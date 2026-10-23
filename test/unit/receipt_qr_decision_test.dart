// قرارُ رمز الاستجابة السريعة على الإيصال — ضريبيٌّ أم غيرُ ضريبيٍّ أم لا شيء.
//
// ═══ فئةُ العطب ═══
//
// قرارُ المالك 2026-09-02: الجهازُ الذي فُعِّلت عليه الفاتورةُ الإلكترونيّة
// يطبع رمزاً **ضريبيّاً** من البوّابة؛ والذي لم تُفعَّل عليه يطبع رمزاً
// **غيرَ ضريبيٍّ** ببيانات البيعة وحدَها، بديلاً رقميّاً عن الورق —
// **ولا يُعترف به ضريبيّاً**.
//
// والمأزقُ أنّ الجهازَ لا يميّز الحالتين عند الطباعة الأولى: لا صفَّ تقديمٍ
// في الاثنتين. فلو خمّن خطأً طبع رمزاً غيرَ ضريبيٍّ على إيصال منشأةٍ مسجَّلةٍ
// ضريبيّاً — وهو ما يجب أن يستحيل.
//
// فالرايةُ (‏`einvoice_enabled` في `Settings` المُزامَنة) هي الفاصل، لا غيابُ
// صفِّ التقديم. و`EInvoiceConfigs` تبقى على الخادم لأنّها تحمل السرّ.

import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/domain/models/receipt_qr_decision.dart';

void main() {
  const sale = ReceiptSaleSummary(
    invoiceNumber: 'INV-1042',
    issuedAt: '2026-09-02 14:35',
    total: '250.00',
    companyName: 'مؤسّسةُ النور',
  );

  group('الفاتورةُ الإلكترونيّةُ غيرُ مُفعَّلةٍ على الجهاز', () {
    test('يطبع رمزاً غيرَ ضريبيٍّ يحمل بياناتِ البيعة مقروءةً', () {
      final qr = resolveReceiptQr(
        eInvoiceEnabled: false,
        submissionStatus: null,
        gatewayQrCode: null,
        sale: sale,
      );

      expect(qr.kind, ReceiptQrKind.nonFiscal);
      // بيانات البيعة الأربع حاضرةٌ نصّاً — بديلٌ حقيقيٌّ للورق لا رقمٌ مجرّد.
      expect(qr.payload, contains('INV-1042'));
      expect(qr.payload, contains('2026-09-02 14:35'));
      expect(qr.payload, contains('250.00'));
      expect(qr.payload, contains('مؤسّسةُ النور'));
    });

    test('يحمل وسماً صريحاً أنّه ليس إيصالاً ضريبيّاً', () {
      final qr = resolveReceiptQr(
        eInvoiceEnabled: false,
        submissionStatus: null,
        gatewayQrCode: null,
        sale: sale,
      );

      expect(qr.disclaimer, isNotEmpty);
      expect(qr.disclaimer, contains('ليس إيصالاً ضريبيّاً'));
    });
  });

  group('ReceiptSaleSummary.fromSale — الصياغةُ في موضعٍ واحد', () {
    // المنادي (`printing_service`) لا يستورد `intl`، وصياغةُ التاريخ والمبلغ
    // في موضع النداء تتكرّر وتختلف. فالمصنعُ يثبّتها هنا حيث تُختبَر.
    test('التاريخُ بالدقيقة والمبلغُ بمنزلتين', () {
      final s = ReceiptSaleSummary.fromSale(
        invoiceNumber: 'INV-9',
        issuedAt: DateTime(2026, 9, 2, 14, 5),
        total: 250,
        companyName: 'مؤسّسة',
      );

      expect(s.invoiceNumber, 'INV-9');
      expect(s.issuedAt, '2026-09-02 14:05');
      expect(s.total, '250.00');
      expect(s.companyName, 'مؤسّسة');
    });

    test('الشهرُ واليومُ والساعةُ تُصفَّر إلى خانتين', () {
      final s = ReceiptSaleSummary.fromSale(
        invoiceNumber: 'x',
        issuedAt: DateTime(2026, 1, 3, 7, 8),
        total: 0.5,
        companyName: 'x',
      );

      expect(s.issuedAt, '2026-01-03 07:08');
      expect(s.total, '0.50');
    });
  });

  group('الفاتورةُ الإلكترونيّةُ مُفعَّلةٌ على الجهاز', () {
    test('اعتمادُ البوّابة وصل ⇒ يطبع الرمزَ الضريبيَّ كما ورد', () {
      final qr = resolveReceiptQr(
        eInvoiceEnabled: true,
        submissionStatus: 'valid',
        gatewayQrCode: 'AQ1RUUEBAgMEBQYHCA==',
        sale: sale,
      );

      expect(qr.kind, ReceiptQrKind.fiscal);
      expect(qr.payload, 'AQ1RUUEBAgMEBQYHCA==');
      // الضريبيُّ لا وسمَ عليه — الوسمُ علامةُ غيرِ الضريبيّ وحدَه.
      expect(qr.disclaimer, isEmpty);
    });

    test('لا صفَّ تقديمٍ بعد ⇒ لا رمزَ إطلاقاً', () {
      final qr = resolveReceiptQr(
        eInvoiceEnabled: true,
        submissionStatus: null,
        gatewayQrCode: null,
        sale: sale,
      );

      expect(qr.kind, ReceiptQrKind.none);
      expect(qr.payload, isEmpty);
    });

    test('التقديمُ معلَّقٌ ولم يُعتمَد ⇒ لا رمزَ إطلاقاً', () {
      final qr = resolveReceiptQr(
        eInvoiceEnabled: true,
        submissionStatus: 'pending',
        gatewayQrCode: null,
        sale: sale,
      );

      expect(qr.kind, ReceiptQrKind.none);
      expect(qr.payload, isEmpty);
    });

    // ═══ الثابتُ الأمنيُّ ═══
    //
    // هذا هو البندُ الذي من أجله كُتب الملفُّ كلُّه: جهازٌ مسجَّلٌ ضريبيّاً
    // **لا يطبع رمزاً غيرَ ضريبيٍّ أبداً** مهما كانت حالةُ التقديم. وإلّا
    // خرج من ماكينةِ منشأةٍ مسجَّلةٍ رمزٌ يبدو ضريبيّاً وليس فيه بياناتٌ
    // ضريبيّة.
    test('لا يُنتج رمزاً غيرَ ضريبيٍّ في أيّ حالةِ تقديم', () {
      const everyStatus = <String?>[
        null,
        'pending',
        'submitted',
        'valid',
        'invalid',
        'rejected',
        'cancelled',
        'unknown-future-status',
      ];

      for (final status in everyStatus) {
        for (final qrFromGateway in <String?>[null, '', 'AQ1RUUE=']) {
          final qr = resolveReceiptQr(
            eInvoiceEnabled: true,
            submissionStatus: status,
            gatewayQrCode: qrFromGateway,
            sale: sale,
          );

          expect(
            qr.kind,
            isNot(ReceiptQrKind.nonFiscal),
            reason:
                'حالة=$status رمز=$qrFromGateway — جهازٌ مُفعَّلٌ طبع رمزاً '
                'غيرَ ضريبيّ',
          );
          expect(
            qr.disclaimer,
            isEmpty,
            reason: 'حالة=$status — وسمُ «غير ضريبيّ» ظهر على جهازٍ مُفعَّل',
          );
        }
      }
    });
  });
}
