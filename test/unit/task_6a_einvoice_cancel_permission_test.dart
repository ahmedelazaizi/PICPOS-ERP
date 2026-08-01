// Task 6a — طبقة الإدارة: الفوترة الإلكترونية (`einvoice_cancel`).
//
// إلغاء فاتورة إلكترونية مُرسَلة كان بيتنفّذ من غير أي فحص صلاحية — الشاشة
// كانت محمية بكود عرض خشن بس (`einvoice_view`). الفحص الحقيقي اتحط جوه
// `_cancelSingle` (خاصة، جوه State خاص) بس اتستخرج منطقه لدالة عامة
// `canCancelEInvoice` في نفس الملف عشان تتفحص من غير تركيب شاشة كاملة
// محتاجة فاتورة بيع حقيقية كـ FK للسجل.
//
// هنا بنفحص الدالة الحقيقية نفسها (`canCancelEInvoice`) — مش إعادة كتابة
// الشرط جوه الاختبار.
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/core/permissions/permission_codes.dart';
import 'package:ural_erp/presentation/screens/e_invoice_dashboard_screen.dart';

void main() {
  group('canCancelEInvoice — einvoice_cancel', () {
    test('من غير الصلاحية ومن غير أدمن: ممنوع', () {
      expect(canCancelEInvoice(const []), isFalse);
      expect(canCancelEInvoice(const ['some_other_perm']), isFalse);
    });

    test('مع einvoice_cancel: مسموح', () {
      expect(canCancelEInvoice([PermissionCodes.einvoiceCancel]), isTrue);
    });

    test('أدمن (system_admin) بيعدّى — الكود ده مش critical financial op',
        () {
      expect(canCancelEInvoice(const ['system_admin']), isTrue);
      expect(canCancelEInvoice(const ['*']), isTrue);
    });
  });
}
