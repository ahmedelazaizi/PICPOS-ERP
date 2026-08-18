// ═══════════════════════════════════════════════════════════════════════════
// تكافؤُ نوافذ إدخال المال — مركزُ التكلفة والمخزن
// ═══════════════════════════════════════════════════════════════════════════
//
// العطلُ الذي أنتج هذا الحارس لم يكن منطقاً خاطئاً: كان **شاشةً انحرفت عن
// أخواتها**. نافذةُ فاتورة المشتريات كانت تقرأ `getCostCenters()` — وهي تُرجع
// المعطَّلَ كذلك — بينما المسارات الأربعة الأخرى على `getActiveCostCenters()`.
// وكانت بلا حصر Spec 103 إطلاقاً بينما نافذتا فاتورة المبيعات تحصران.
//
// الانحرافُ من هذا النوع لا يكشفه اختبارُ سلوكٍ لأن كلَّ شاشةٍ «تعمل» وحدَها.
// فالحارسُ نصّيّ بالضرورة، وهو يقفل التكافؤ لا التنفيذ.

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// نوافذُ إدخالٍ تختار مركزَ تكلفة.
const _costCenterPickers = <String>[
  'lib/presentation/screens/purchase_invoices/widgets/purchase_invoice_form.dart',
  'lib/presentation/screens/widgets/sales_invoices/sales_invoice_dialogs.dart',
  'lib/presentation/sales_invoices_picpos/screens/sales_invoice_dialogs.dart',
  'lib/presentation/screens/purchase_orders_screen.dart',
  'lib/presentation/screens/sales_orders_screen.dart',
];

/// نوافذُ الفواتير التي تختار مخزناً وتُحفَظ على فرعه.
///
/// شاشتا أمرِ البيع وأمرِ المشتريات **خارجَ** هذه القائمة عمداً: هما لا
/// تحصران المخازن اليوم، والأمرُ مستندٌ لا فاتورةٌ تُرحَّل على فرع. إدخالُهما
/// هنا يجعل الحارسَ أحمرَ على عملٍ لم يُقرَّر بعد — وحارسٌ يُضبَط ليطابق
/// الواقع أسوأ من حارسٍ صادق.
const _warehouseScopedInvoiceForms = <String>[
  'lib/presentation/screens/purchase_invoices/widgets/purchase_invoice_form.dart',
  'lib/presentation/screens/widgets/sales_invoices/sales_invoice_dialogs.dart',
  'lib/presentation/sales_invoices_picpos/screens/sales_invoice_dialogs.dart',
];

String _read(String relPath) {
  final file = File(relPath);
  expect(file.existsSync(), isTrue,
      reason: 'الملفُّ $relPath غير موجود — حدِّث القائمةَ في هذا الحارس');
  return file.readAsStringSync();
}

void main() {
  group('تكافؤُ نوافذ الإدخال', () {
    test('مراكزُ التكلفة تُقرأ نشطةً لا كاملةً', () {
      for (final path in _costCenterPickers) {
        final src = _read(path);
        expect(src.contains('getActiveCostCenters'), isTrue,
            reason: '$path لا يقرأ `getActiveCostCenters` — مركزٌ أُوقف عمداً '
                'سيظهر في القائمة وتُرحَّل عليه فاتورة');
        expect(src.contains('.getCostCenters('), isFalse,
            reason: '$path يقرأ `getCostCenters()` وهي تُرجع المعطَّل كذلك');
      }
    });

    test('نوافذُ الفواتير تحصر المخازن بفرع الجهاز (Spec 103)', () {
      for (final path in _warehouseScopedInvoiceForms) {
        expect(_read(path).contains('narrowWarehousesToClientBranch'), isTrue,
            reason: '$path بلا حصرِ فرع — الفاتورةُ تُحفَظ بمخزنِ فرعٍ آخر '
                'فتغيب عن قائمة فرعها');
      }
    });

    test('القاعدةُ مصدرُها واحدٌ لا نسخةٌ في كلِّ نافذة', () {
      // النسخُ اليدويُّ هو ما أنتج العطل: قاعدةٌ في نافذتين وغيابٌ في ثالثة.
      final helper = File('lib/domain/models/warehouse_branch_scope.dart');
      expect(helper.existsSync(), isTrue);

      for (final path in _warehouseScopedInvoiceForms) {
        expect(
          RegExp(r'where\(\(w\) => w\.branchId == clientBranchId\)')
              .hasMatch(_read(path)),
          isFalse,
          reason: '$path يحمل نسخةً يدويّةً من قاعدة الحصر بدل الدالّة الخالصة',
        );
      }
    });
  });
}
