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

/// نوافذُ إدخالٍ تختار مخزناً يُورَّث إلى مستندٍ يُرحَّل على فرعه — وتحصره
/// عبر **المستودع** (`getScopedWarehouses`)، فلا يقرأ العرضُ تفضيلاتِ الجهاز.
///
/// قرارُ المالك 2026-08-19: وُسِّع الحصرُ إلى شاشتَي الأمرَين. وأمرُ البيع
/// آكدُ من غيره — أوّلُ مخزنٍ يُنتقى تلقائيّاً فيه، فقائمةٌ غيرُ محصورةٍ قد
/// تختار مخزنَ فرعٍ آخر بلا لمسةٍ من الكاشير.
const _repoScopedWarehousePickers = <String>[
  'lib/presentation/screens/purchase_invoices/widgets/purchase_invoice_form.dart',
  'lib/presentation/screens/purchase_orders_screen.dart',
  'lib/presentation/screens/sales_orders_screen.dart',
];

/// نافذتا فاتورة المبيعات تعملان على `WarehouseData` لا `Warehouse` المولَّد،
/// ومصدرُهما مجرى المستودع لا `getWarehouses` — فتستدعيان القاعدةَ الخالصةَ
/// مباشرةً. الرُّقعتان مختلفتان والقاعدةُ واحدة.
const _pureRuleWarehousePickers = <String>[
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

    // المنعُ هنا على **القائمة** لا على الصفّ.
    //
    // `getScopedWarehouses` تحصر مسارَ الإنشاء، وهذا هو المقصود. أمّا مسارُ
    // **تحرير** فاتورةٍ قائمة فيحتاج قيمةَ الفاتورة نفسِها ولو خرجت من الحصر
    // (مخزنُ فرعٍ آخر، أو مركزُ تكلفةٍ أُوقف بعد الإصدار) — وإلّا أطلق
    // `DropdownButtonFormField` توكيدَه في debug ورسم حقلاً فارغاً في release
    // ثم أُعيد الحفظُ بقيمةٍ أخرى صامتاً.
    //
    // والاستثناءُ يُستوفى **بجلبٍ بالمعرّف** (`getWarehouseById` /
    // `getCostCenterById`): صفٌّ واحدٌ هو صفُّ الفاتورة. فلا حاجةَ إلى رفع
    // المنع عن `getWarehouses()` — المنعُ يبقى كما هو على مسار الإنشاء،
    // والاستثناءُ يُنفَّذ من تحته لا فوقه. والتوكيدُ التالي يقفل الاستثناءَ
    // إيجاباً حتّى لا يسقط في إعادة صياغةٍ لاحقة.
    test('منتقو المخازن يمرّون بـ getScopedWarehouses لا بالقائمة الخام', () {
      for (final path in _repoScopedWarehousePickers) {
        final src = _read(path);
        expect(src.contains('getScopedWarehouses'), isTrue,
            reason: '$path بلا حصرِ فرع — المستندُ يُحفَظ بمخزنِ فرعٍ آخر '
                'فيغيب عن قائمة فرعه');
        expect(RegExp(r'\.getWarehouses\(\)').hasMatch(src), isFalse,
            reason: '$path ما زال يقرأ القائمةَ **الخام** في مسارِ إصدارِ '
                'مستند. ولتحريرِ مستندٍ قائمٍ اجلب صفَّه بالمعرّف '
                '(`getWarehouseById`) بدل رفع الحصر عن القائمة كلِّها');
      }
    });

    test('نافذةُ تحرير المشتريات تضمّ صفَّ الفاتورة الغائبَ عن الحصر', () {
      const path =
          'lib/presentation/screens/purchase_invoices/widgets/purchase_invoice_form.dart';
      final src = _read(path);
      expect(src.contains('widget.editInvoice != null'), isTrue,
          reason: '$path بلا فرعِ تحريرٍ في تحميل القوائم');
      expect(src.contains('getWarehouseById'), isTrue,
          reason: '$path لا يجلب مخزنَ الفاتورة الغائبَ عن القائمة المحصورة — '
              'فتُعرض قيمةٌ فارغةٌ وتُحفظ الفاتورةُ بمخزنٍ آخر');
      expect(src.contains('getCostCenterById'), isTrue,
          reason: '$path لا يجلب مركزَ تكلفة الفاتورة إن كان قد أُوقف بعد '
              'إصدارها — فتفقد الفاتورةُ مركزَها عند أوّل حفظ');
    });

    test('نافذتا فاتورة المبيعات تستدعيان القاعدةَ الخالصة', () {
      for (final path in _pureRuleWarehousePickers) {
        expect(_read(path).contains('narrowWarehousesToClientBranch'), isTrue,
            reason: '$path بلا حصرِ فرع (Spec 103)');
      }
    });

    test('القاعدةُ مصدرُها واحدٌ لا نسخةٌ في كلِّ نافذة', () {
      // النسخُ اليدويُّ هو ما أنتج العطل: قاعدةٌ في نافذتين وغيابٌ في ثالثة.
      final helper = File('lib/domain/models/warehouse_branch_scope.dart');
      expect(helper.existsSync(), isTrue);

      for (final path in [
        ..._repoScopedWarehousePickers,
        ..._pureRuleWarehousePickers,
      ]) {
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
