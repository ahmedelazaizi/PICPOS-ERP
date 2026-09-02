// ═══════════════════════════════════════════════════════════════════════════
// عاملُ تقديم الفاتورة الإلكترونيّة على الخادم — يمسح ويقدّم ولا يتوقّف بعثرة.
// ═══════════════════════════════════════════════════════════════════════════
//
// قرارُ المالك: الخادمُ وحدَه يحمل السرَّ ويرسل. وهذا العاملُ هو «يرسل».
//
// ⚠️ **وأخطرُ ما فيه أن يتوقّف عند أوّل إخفاق**: طابورٌ فيه مستندٌ واحدٌ
// معطوبٌ كان سيحجب كلَّ ما بعده إلى الأبد — فلا تصل المصلحةَ فاتورةٌ واحدة،
// ولا يظهر للمستخدم سببٌ لأنّ الإخفاقَ يُسجَّل على ذلك المستند وحدَه.

import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/services/e_invoicing/e_invoice_submission_worker.dart';

void main() {
  test('لا يعمل حين الميزةُ موقوفة — ولا يمسح أصلاً', () async {
    var swept = 0;
    final worker = EInvoiceSubmissionWorker(
      isEnabled: () async => false,
      findDue: ({int limit = 25}) async {
        swept++;
        return const [1, 2];
      },
      submit: (_) async {},
    );

    final n = await worker.runOnce();

    expect(n, 0);
    expect(swept, 0,
        reason: 'مسحُ القاعدة قبل التحقّق من التفعيل عملٌ بلا سبب');
  });

  test('يقدّم كلَّ فاتورةٍ مستحقّة', () async {
    final submitted = <int>[];
    final worker = EInvoiceSubmissionWorker(
      isEnabled: () async => true,
      findDue: ({int limit = 25}) async => const [7, 9, 11],
      submit: (id) async => submitted.add(id),
    );

    expect(await worker.runOnce(), 3);
    expect(submitted, [7, 9, 11]);
  });

  // 🔴 البندُ الذي كُتب الملفُّ من أجله.
  test('🔴 إخفاقُ مستندٍ لا يحجب ما بعده', () async {
    final submitted = <int>[];
    final worker = EInvoiceSubmissionWorker(
      isEnabled: () async => true,
      findDue: ({int limit = 25}) async => const [1, 2, 3],
      submit: (id) async {
        submitted.add(id);
        if (id == 2) throw StateError('البوّابة رفضت الاتصال');
      },
    );

    final n = await worker.runOnce();

    expect(submitted, [1, 2, 3],
        reason: 'توقّفُ الطابور عند مستندٍ معطوبٍ يحجب كلَّ ما بعده للأبد');
    expect(n, 2, reason: 'العدّادُ يحصي الناجحَ لا المحاوَل');
  });

  test('الحدُّ يُمرَّر إلى المسح كما هو', () async {
    int? seen;
    final worker = EInvoiceSubmissionWorker(
      isEnabled: () async => true,
      findDue: ({int limit = 25}) async {
        seen = limit;
        return const [];
      },
      submit: (_) async {},
      batchSize: 5,
    );

    await worker.runOnce();

    expect(seen, 5);
  });

  // إخفاقُ المسح نفسِه (‏قاعدةٌ مقطوعة) لا يُسقط الخادم.
  test('إخفاقُ المسح يُرجع صفراً ولا يرمي', () async {
    final worker = EInvoiceSubmissionWorker(
      isEnabled: () async => true,
      findDue: ({int limit = 25}) async => throw StateError('قاعدةٌ مقطوعة'),
      submit: (_) async {},
    );

    expect(await worker.runOnce(), 0);
  });

  test('وإخفاقُ فحص التفعيل كذلك', () async {
    final worker = EInvoiceSubmissionWorker(
      isEnabled: () async => throw StateError('تعذّرت القراءة'),
      findDue: ({int limit = 25}) async => const [1],
      submit: (_) async {},
    );

    expect(await worker.runOnce(), 0);
  });
}
