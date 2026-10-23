// ═══════════════════════════════════════════════════════════════════════════
// متطلبات العميل 2026-07-25 · م4 · البند 5 — تصنيف تعارض الطابور.
// ═══════════════════════════════════════════════════════════════════════════
//
// الطابور كان يعامل **كل** 409 على أنه «الصف موجود على الخادم أصلاً» فيضع
// العنصر ناجحاً ويسحب نسخة الخادم. هذا صحيح لإعادة إرسال نفس الصف، لكنه
// **يُسقط عمل المستخدم صامتاً** حين يكون 409 تعارض عمل حقيقي: فاتورة مختلفة
// تحمل رقم مورد مستخدماً. المستخدم لا يرى شيئاً وفاتورته لا تصل أبداً.
//
// التمييز عبر رمز آلي في جسم الرد، لا عبر تخمين نصّي.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/services/offline_sync_worker.dart';

void main() {
  test('تعارض العمل يُصنَّف نهائياً — لا "ناجح" ولا إعادة محاولة', () {
    expect(
      isTerminalBusinessConflict(
          'DUPLICATE_SUPPLIER_INVOICE_NO: رقم فاتورة المورد "INV-1" مستخدم بالفعل'),
      isTrue,
      reason: 'يجب أن يصل المستخدم إشعار ليصحّح الرقم',
    );
  });

  test('التكرار الحميد (نفس الصف) يبقى غير نهائي فيُطوى كناجح', () {
    expect(isTerminalBusinessConflict('409 Conflict: already exists'), isFalse);
    expect(isTerminalBusinessConflict('UNIQUE constraint failed'), isFalse);
    expect(isTerminalBusinessConflict('duplicate'), isFalse);
  });

  test('الأعطال العابرة ليست تعارضاً نهائياً', () {
    expect(isTerminalBusinessConflict('SocketException: connection refused'),
        isFalse);
    expect(isTerminalBusinessConflict('500 Internal Server Error'), isFalse);
  });
}
