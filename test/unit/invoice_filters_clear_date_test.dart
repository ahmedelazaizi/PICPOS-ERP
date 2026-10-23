// حارسُ مسحِ مدى التاريخ في شاشتَي الفواتير.
//
// العطبُ الذي وُلد منه هذا الملفّ: `copyWith` كانت تكتب
// `dateRange: dateRange ?? this.dateRange`، فتمريرُ `null` — وهو **الطريقةُ
// الوحيدةُ** لطلبِ المسح — كان يعني «لا تغيّر» لا «امسح». فزرُّ الـ«‏×» في
// حبّة التاريخ وزرُّ «إعادة تعيين المرشِّحات» كانا يُنقَران بلا أثر، والقائمةُ
// تبقى مقصوصةً على مدىً لم يعُد ظاهراً في الشريط.
//
// ولا يُقاس هذا بالنظر: التوقيعُ `DateTimeRange?` يقبل `null` بلا شكوى،
// والتحليلُ أخضر، والعطبُ لا يظهر إلّا عند التشغيل.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/presentation/screens/sales_invoices_controller.dart';
import 'package:picpos_erp/presentation/screens/purchases/purchase_invoices_controller.dart';

void main() {
  final range = DateTimeRange(
    start: DateTime(2026, 8, 1),
    end: DateTime(2026, 8, 21),
  );

  group('مسحُ مدى التاريخ عبر copyWith', () {
    test('المبيعات: تمريرُ null يمسح المدى فعلاً', () {
      final withRange = SalesInvoicesScreenState(dateRange: range);
      expect(withRange.dateRange, isNotNull, reason: 'تجهيزةٌ سليمة');

      final cleared = withRange.copyWith(clearDateRange: true);
      expect(cleared.dateRange, isNull,
          reason: 'زرُّ «×» يطلب المسحَ — فليقع المسح');
    });

    test('المبيعات: إغفالُ الوسيط يُبقي المدى', () {
      final withRange = SalesInvoicesScreenState(dateRange: range);
      // الشقُّ الآخر من العقد: كلُّ `copyWith` أخرى في الملفّ لا تمرّر
      // `dateRange`، فلو مسحَ الإغفالُ المدى لضاع المرشِّحُ مع كلّ ضغطةِ مفتاح.
      expect(withRange.copyWith(searchQuery: 'x').dateRange, range);
    });

    test('المشتريات: تمريرُ null يمسح المدى فعلاً', () {
      final withRange = PurchaseInvoicesScreenState(dateRange: range);
      expect(withRange.dateRange, isNotNull, reason: 'تجهيزةٌ سليمة');

      final cleared = withRange.copyWith(clearDateRange: true);
      expect(cleared.dateRange, isNull);
    });

    test('المشتريات: إغفالُ الوسيط يُبقي المدى', () {
      final withRange = PurchaseInvoicesScreenState(dateRange: range);
      expect(withRange.copyWith(searchQuery: 'x').dateRange, range);
    });
  });
}
