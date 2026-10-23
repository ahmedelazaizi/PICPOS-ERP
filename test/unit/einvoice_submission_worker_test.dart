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
import 'package:picpos_erp/services/e_invoicing/e_invoice_submission_worker.dart';

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

  // ═════════════════════════════════════════════════════════════════════════
  // إشعاراتُ الائتمان — المرتجعاتُ كانت خارجَ المكنسة كلَّها
  // ═════════════════════════════════════════════════════════════════════════

  group('إشعاراتُ الائتمان', () {
    test('🔴 تُمسَح وتُقدَّم مع أصلِ كلٍّ منها', () async {
      final sent = <({int returnSaleId, int originalSaleId})>[];
      final worker = EInvoiceSubmissionWorker(
        isEnabled: () async => true,
        findDue: ({int limit = 25}) async => const [],
        submit: (_) async {},
        findDueCreditNotes: ({int limit = 25}) async => const [
          (returnSaleId: 5, originalSaleId: 1),
          (returnSaleId: 6, originalSaleId: 2),
        ],
        submitCreditNote: (r) async => sent.add(r),
      );

      expect(await worker.runOnce(), 2);
      expect(sent.map((e) => e.returnSaleId), [5, 6]);
      expect(sent.first.originalSaleId, 1,
          reason: 'الأصلُ يُمرَّر — إشعارٌ بلا أصلٍ مستندٌ باطل وسقفُه لا يُفحَص');
    });

    test('🔴 وإخفاقُ إشعارٍ لا يحجب ما بعده', () async {
      final sent = <int>[];
      final worker = EInvoiceSubmissionWorker(
        isEnabled: () async => true,
        findDue: ({int limit = 25}) async => const [],
        submit: (_) async {},
        findDueCreditNotes: ({int limit = 25}) async => const [
          (returnSaleId: 1, originalSaleId: 10),
          (returnSaleId: 2, originalSaleId: 20),
          (returnSaleId: 3, originalSaleId: 30),
        ],
        submitCreditNote: (r) async {
          sent.add(r.returnSaleId);
          // السقفُ الضريبيُّ يرمي على المخالف — ولا يوقف الطابور.
          if (r.returnSaleId == 2) throw Exception('يتجاوز مبلغ الفاتورة');
        },
      );

      expect(await worker.runOnce(), 2);
      expect(sent, [1, 2, 3]);
    });

    test('تُحصى مع الفواتير في عدّادٍ واحد', () async {
      final worker = EInvoiceSubmissionWorker(
        isEnabled: () async => true,
        findDue: ({int limit = 25}) async => const [7],
        submit: (_) async {},
        findDueCreditNotes: ({int limit = 25}) async =>
            const [(returnSaleId: 8, originalSaleId: 1)],
        submitCreditNote: (_) async {},
      );

      expect(await worker.runOnce(), 2);
    });

    test('وإخفاقُ مسحِها لا يُسقط مسحَ الفواتير', () async {
      final worker = EInvoiceSubmissionWorker(
        isEnabled: () async => true,
        findDue: ({int limit = 25}) async => const [7],
        submit: (_) async {},
        findDueCreditNotes: ({int limit = 25}) async =>
            throw StateError('قاعدةٌ مقطوعة'),
        submitCreditNote: (_) async {},
      );

      expect(await worker.runOnce(), 1,
          reason: 'الفاتورةُ قُدِّمت — ولا يُسقطها تعثّرُ مسارٍ آخر');
    });

    test('وبلا مُمرَّرٍ لها لا يتغيّر شيء — عقدُ المنادي القديم', () async {
      final worker = EInvoiceSubmissionWorker(
        isEnabled: () async => true,
        findDue: ({int limit = 25}) async => const [1],
        submit: (_) async {},
      );

      expect(await worker.runOnce(), 1);
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  // استطلاعُ الحالة — المستندُ يبقى `submitted` إلى الأبد بدونه
  // ═════════════════════════════════════════════════════════════════════════

  group('استطلاعُ الحالة', () {
    test('🔴 يُستطلَع كلُّ مستندٍ مستحقّ', () async {
      final polled = <String>[];
      final worker = EInvoiceSubmissionWorker(
        isEnabled: () async => true,
        findDue: ({int limit = 25}) async => const [],
        submit: (_) async {},
        findDueStatusChecks: ({int limit = 25}) async => const [
          (submissionId: 1, documentUuid: 'D-1'),
          (submissionId: 2, documentUuid: 'D-2'),
        ],
        checkStatus: (p) async => polled.add(p.documentUuid),
      );

      await worker.runOnce();

      expect(polled, ['D-1', 'D-2']);
    });

    test('🔴 وإخفاقُ استطلاعٍ لا يحجب ما بعده', () async {
      final polled = <int>[];
      final worker = EInvoiceSubmissionWorker(
        isEnabled: () async => true,
        findDue: ({int limit = 25}) async => const [],
        submit: (_) async {},
        findDueStatusChecks: ({int limit = 25}) async => const [
          (submissionId: 1, documentUuid: 'D-1'),
          (submissionId: 2, documentUuid: 'D-2'),
          (submissionId: 3, documentUuid: 'D-3'),
        ],
        checkStatus: (p) async {
          polled.add(p.submissionId);
          if (p.submissionId == 2) throw Exception('البوّابةُ لم تردّ');
        },
      );

      await worker.runOnce();

      expect(polled, [1, 2, 3],
          reason: 'توقّفٌ عند مستندٍ لا تردّ عنه البوّابةُ يجمّد الطابورَ كلَّه');
    });

    // 🔴 الاستطلاعُ **ليس تقديماً**: لا يُحصى في عدّاد ما قُدِّم، وإلّا بدا
    //    الخادمُ يقدّم مستنداتٍ لا وجودَ لها.
    test('🔴 لا يُحصى في عدّاد التقديم', () async {
      final worker = EInvoiceSubmissionWorker(
        isEnabled: () async => true,
        findDue: ({int limit = 25}) async => const [7],
        submit: (_) async {},
        findDueStatusChecks: ({int limit = 25}) async => const [
          (submissionId: 1, documentUuid: 'D-1'),
          (submissionId: 2, documentUuid: 'D-2'),
        ],
        checkStatus: (_) async {},
      );

      expect(await worker.runOnce(), 1,
          reason: 'فاتورةٌ واحدةٌ قُدِّمت — والاستطلاعان قراءةٌ لا تقديم');
    });

    test('وإخفاقُ مسحِ الاستطلاع لا يُسقط التقديم', () async {
      final worker = EInvoiceSubmissionWorker(
        isEnabled: () async => true,
        findDue: ({int limit = 25}) async => const [7],
        submit: (_) async {},
        findDueStatusChecks: ({int limit = 25}) async =>
            throw StateError('قاعدةٌ مقطوعة'),
        checkStatus: (_) async {},
      );

      expect(await worker.runOnce(), 1);
    });

    test('وبلا مُمرَّرٍ له لا يُستطلَع شيء', () async {
      final worker = EInvoiceSubmissionWorker(
        isEnabled: () async => true,
        findDue: ({int limit = 25}) async => const [1],
        submit: (_) async {},
      );

      expect(await worker.runOnce(), 1);
    });
  });
}
