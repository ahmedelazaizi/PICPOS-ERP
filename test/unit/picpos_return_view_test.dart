// نموذجُ عرضِ شاشتَي المرتجعات — حسابٌ خالصٌ يشترك فيه التوأمان.
//
// ما يُقاس: تسمياتُ الحالة (عقدُ تكافؤٍ مع `_getStatusLabel` الأصليّة)،
// وسطرُ التفاصيل حين **لا يوجد** اسمُ طرفٍ (حالةُ المشتريات الحقيقيّة)،
// والعدّاداتُ التي تعدُّ ولا تخترع مبالغَ مرتجعات.
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/core/constants/app_constants.dart';
import 'package:ural_erp/domain/models/picpos_return_view.dart';

PicPosReturnInvoiceRow _row({
  int id = 1,
  String number = '# INV-1',
  DateTime? date,
  double total = 100,
  PicPosReturnStatus status = PicPosReturnStatus.completed,
  String? partyName,
}) =>
    PicPosReturnInvoiceRow(
      id: id,
      number: number,
      date: date ?? DateTime(2026, 8, 18),
      total: total,
      status: status,
      partyName: partyName,
    );

void main() {
  group('PicPosReturnStatus', () {
    // ⚠️ عقدُ تكافؤ: هذه النصوصُ منقولةٌ عن `_getStatusLabel` في الشاشة
    // الأصليّة. تغييرُها هنا وحدَه يجعل نفسَ الفاتورة توصَف وصفَين.
    test('تقرأ الأكوادَ المخزَّنةَ بتسمياتها', () {
      expect(PicPosReturnStatus.fromCode('completed').label, 'مكتملة');
      expect(PicPosReturnStatus.fromCode('returned').label, 'مرتجعة');
      expect(PicPosReturnStatus.fromCode('partial_return').label, 'مرتجع جزئي');
      expect(PicPosReturnStatus.fromCode('voided').label, 'ملغاة');
    });

    test('كودٌ مجهولٌ يرتدُّ إلى «معلقة» لا يرمي', () {
      expect(PicPosReturnStatus.fromCode('nonsense').label, 'معلقة');
      expect(PicPosReturnStatus.fromCode('').label, 'معلقة');
    });
  });

  group('PicPosReturnInvoiceRow', () {
    test('التاريخُ المختصرُ يوم/شهر كما في التصميم', () {
      expect(_row(date: DateTime(2026, 8, 18)).shortDate, '18/8');
      expect(_row(date: DateTime(2026, 12, 3)).shortDate, '3/12');
    });

    test('سطرُ التفاصيل يضمّ اسمَ الطرف حين يوجد', () {
      expect(
        _row(partyName: 'أحمد', date: DateTime(2026, 8, 18)).subtitle,
        'أحمد · 18/8',
      );
    });

    // ⚠️ الحالةُ الحقيقيّةُ لشاشة المشتريات: لا خريطةَ أسماءِ موردين، فيمرَّر
    // `null` ويجب أن يظهر التاريخُ وحدَه — لا «· 18/8» بفاصلٍ معلَّق.
    test('بلا اسمِ طرفٍ يظهر التاريخُ وحدَه بلا فاصلٍ معلَّق', () {
      expect(_row(date: DateTime(2026, 8, 18)).subtitle, '18/8');
      expect(_row(partyName: '', date: DateTime(2026, 8, 18)).subtitle, '18/8');
      expect(
          _row(partyName: '   ', date: DateTime(2026, 8, 18)).subtitle, '18/8');
    });

    test('نصُّ الإجمالي يستعمل decimalPlaces لا رقماً مكتوباً باليد', () {
      final label = _row(total: 12.5).totalLabel;
      expect(
        label,
        '${(12.5).toStringAsFixed(AppConstants.decimalPlaces)} '
        '${AppConstants.currencySymbolEn}',
      );
    });

    test('البحثُ بالرقم بلا حساسيّةٍ لحالة الأحرف، وفارغٌ يمرّر الكلّ', () {
      final r = _row(number: '# INV-2026-0842');
      expect(r.matchesNumber(''), isTrue);
      expect(r.matchesNumber('   '), isTrue);
      expect(r.matchesNumber('inv-2026'), isTrue);
      expect(r.matchesNumber('0842'), isTrue);
      expect(r.matchesNumber('9999'), isFalse);
    });
  });

  group('PicPosReturnKpis', () {
    test('قائمةٌ فارغةٌ تعطي أصفاراً', () {
      final k = PicPosReturnKpis.from(const []);
      expect(k.invoiceCount, 0);
      expect(k.invoicesTotal, 0);
      expect(k.fullyReturned, 0);
      expect(k.partiallyReturned, 0);
    });

    test('تعدُّ المرتجعَ كليّاً وجزئيّاً كلاًّ في خانته', () {
      final k = PicPosReturnKpis.from([
        _row(id: 1, status: PicPosReturnStatus.completed),
        _row(id: 2, status: PicPosReturnStatus.returned),
        _row(id: 3, status: PicPosReturnStatus.returned),
        _row(id: 4, status: PicPosReturnStatus.partialReturn),
        _row(id: 5, status: PicPosReturnStatus.voided),
      ]);
      expect(k.invoiceCount, 5);
      expect(k.fullyReturned, 2);
      expect(k.partiallyReturned, 1);
    });

    test('الإجماليُّ مجموعُ الفواتير لا مجموعُ المرتجعات', () {
      final k = PicPosReturnKpis.from([
        _row(id: 1, total: 100),
        _row(id: 2, total: 250.5),
      ]);
      expect(k.invoicesTotal, closeTo(350.5, 1e-9));
      expect(k.invoicesTotalLabel,
          (350.5).toStringAsFixed(AppConstants.decimalPlaces));
    });

    test('مبلغٌ أدقُّ من المعروض يدخل المجموعَ مقرَّباً لا مبتوراً', () {
      final k = PicPosReturnKpis.from([_row(total: 0.0006)]);
      expect(k.invoicesTotal, closeTo(0.001, 1e-9));
    });
  });
}
