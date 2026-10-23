import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/domain/models/exchange_settlement.dart';
import 'package:picpos_erp/domain/models/return_refund_calculator.dart';

void main() {
  group('settleExchange', () {
    test('البديلُ أغلى ⇒ قبضُ الفرق', () {
      final r = settleExchange(returnTotal: 100, saleTotal: 130);
      expect(r.direction, ExchangeCashDirection.collect);
      expect(r.amount, 30);
    });

    test('البديلُ أرخص ⇒ صرفُ الفرق', () {
      final r = settleExchange(returnTotal: 130, saleTotal: 100);
      expect(r.direction, ExchangeCashDirection.refund);
      expect(r.amount, 30);
    });

    test('متساويان ⇒ لا حركةَ إطلاقاً', () {
      final r = settleExchange(returnTotal: 100, saleTotal: 100);
      expect(r.direction, ExchangeCashDirection.none);
      expect(r.amount, 0);
    });

    test('فرقٌ أصغرُ من دقّةِ العرض يُعامَل لا شيئاً', () {
      // ٠٫٠٠٠٤ تحت التقريب إلى ٣ خانات ⇒ حركةٌ بصفرٍ لا معنى لها،
      // وإنشاؤها يلوّث كشفَ الخزنة بصفوفٍ فارغة.
      final r = settleExchange(returnTotal: 100, saleTotal: 100.0004);
      expect(r.direction, ExchangeCashDirection.none);
    });

    test('المبلغُ موجبٌ دائماً — الاتجاهُ يحمل الإشارة', () {
      expect(settleExchange(returnTotal: 130, saleTotal: 100).amount, 30);
      expect(settleExchange(returnTotal: 100, saleTotal: 130).amount, 30);
    });

    test('يحترم دقّةَ الخانات الممرَّرة', () {
      final r = settleExchange(
        returnTotal: 10, saleTotal: 10.126, decimalPlaces: 2,
      );
      expect(r.direction, ExchangeCashDirection.collect);
      expect(r.amount, 0.13);
    });

    test('شقُّ الارتجاع يستعمل أساسَ الاسترداد الموحَّد لا سعرَ الوحدة', () {
      // سطرٌ بيع: كمية ١، سعرُ وحدةٍ ١٠٠، وإجماليُّ السطر ١١٤ (ضريبة ١٤٪).
      const lines = [(id: 1, quantity: 1.0, lineTotal: 114.0)];
      final returnTotal = calculateReturnRefundTotal(
        lines: lines,
        invoiceTotal: 114,
        invoiceDeliveryFee: 0,
        returnQuantities: {1: 1.0},
      );
      // لو أُخذ سعرُ الوحدة لكان ١٠٠ — وهو بعينه العطبُ المقيس.
      expect(returnTotal, 114);

      final r = settleExchange(returnTotal: returnTotal, saleTotal: 114);
      expect(r.direction, ExchangeCashDirection.none,
          reason: 'استبدالٌ بصنفٍ بنفس القيمة يجب ألّا يُنشئ حركةً نقدية');
    });
  });
}
