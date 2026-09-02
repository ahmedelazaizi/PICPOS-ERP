// ═══════════════════════════════════════════════════════════════════════════
// استطلاعُ الحالة — أيُّ مستندٍ ما زال ينتظر حكمَ البوّابة؟
// ═══════════════════════════════════════════════════════════════════════════
//
// ═══ فئةُ العطب ═══
//
// التقديمُ يترك المستندَ عند `submitted`: البوّابةُ قبلت **الاستلامَ** لا
// المستند. والاعتمادُ (`valid`) أو الرفضُ يأتي لاحقاً باستطلاع.
//
// ولم يكن يستطلعه أحدٌ إلّا المستخدمُ بزرٍّ في الشاشة. فمستندٌ لا يفتح أحدٌ
// شاشتَه يبقى `submitted` **إلى الأبد** — ولا رمزَ ضريبيَّ يُطبع على إيصاله
// لأنّ القرارَ يشترط `valid` (‏`receipt_qr_decision`). أي أنّ الإيصالَ يخرج
// بلا رمزٍ وإن كانت المصلحةُ قد اعتمدت المستندَ من دقائق.
//
// ═══ والتباعُدُ شرطٌ لا تحسين ═══
//
// نبضةٌ كلَّ دقيقتين على طابورٍ فيه مئاتُ المستندات = مئاتُ النداءات كلَّ
// دقيقتين على بوّابةٍ حكوميّةٍ محدودةِ المعدّل. فيُستطلَع ما لم يُستطلَع
// حديثاً فقط.

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';

void main() {
  late AppDatabase db;
  late int whId;

  setUp(() async {
    db = AppDatabase.forTesting();
    final branchId = await db.into(db.branches).insert(
        BranchesCompanion.insert(name: 'ف', globalId: const Value('br-st')));
    whId = await db.into(db.warehouses).insert(WarehousesCompanion.insert(
        name: 'م', branchId: Value(branchId), globalId: const Value('wh-st')));
  });

  tearDown(() => db.close());

  Future<int> sale(String number) =>
      db.into(db.salesInvoices).insert(SalesInvoicesCompanion.insert(
            invoiceNumber: number,
            warehouseId: whId,
            userId: 1,
            invoiceDate: DateTime(2026, 9, 1),
            total: const Value(100),
          ));

  /// يزرع تقديماً بحالةٍ ومعرّفٍ ووقتِ استطلاعٍ محدَّدة.
  Future<int> submission(
    String number, {
    required String status,
    String? documentUuid,
    DateTime? lastCheckedAt,
  }) async {
    final saleId = await sale(number);
    final id = await db.createSubmission(saleId: saleId, platform: 'eta');
    await (db.update(db.eInvoiceSubmissions)..where((s) => s.id.equals(id)))
        .write(EInvoiceSubmissionsCompanion(
      status: Value(status),
      documentUuid: Value(documentUuid),
      lastCheckedAt: Value(lastCheckedAt),
    ));
    return id;
  }

  final now = DateTime(2026, 9, 2, 12, 0);
  const gap = Duration(minutes: 10);

  test('مرساة: مستندٌ مُرسَلٌ بمعرّفٍ ولم يُستطلَع قطُّ يُلتقَط', () async {
    final id = await submission('S-1',
        status: 'submitted', documentUuid: 'DOC-1');

    final due = await db.findSubmissionsAwaitingStatus(
        limit: 50, notCheckedSince: now.subtract(gap));

    expect(due.map((e) => e.submissionId), contains(id));
    expect(due.single.documentUuid, 'DOC-1');
  });

  test('🔴 المعتمَدُ والمرفوضُ لا يُستطلَعان — حكمٌ نهائيّ', () async {
    await submission('S-2', status: 'valid', documentUuid: 'D2');
    await submission('S-3', status: 'invalid', documentUuid: 'D3');
    await submission('S-4', status: 'rejected', documentUuid: 'D4');
    await submission('S-5', status: 'cancelled', documentUuid: 'D5');

    expect(
        await db.findSubmissionsAwaitingStatus(
            limit: 50, notCheckedSince: now.subtract(gap)),
        isEmpty,
        reason: 'استطلاعُ ما حُسم إرهاقٌ لبوّابةٍ محدودةِ المعدّل');
  });

  test('🔴 والمعلَّقُ بلا معرّفِ مستندٍ لا يُستطلَع — لا شيءَ يُسأل عنه',
      () async {
    await submission('S-6', status: 'pending');
    await submission('S-7', status: 'submitted'); // أُرسل ولم يعد بمعرّف

    expect(
        await db.findSubmissionsAwaitingStatus(
            limit: 50, notCheckedSince: now.subtract(gap)),
        isEmpty,
        reason: 'نداءٌ بمعرّفٍ فارغٍ يرجع خطأً يُسجَّل على مستندٍ سليم');
  });

  // 🔴 التباعُد: نبضةٌ كلَّ دقيقتين على مئات المستندات تُغرق البوّابة.
  test('🔴 ما استُطلع حديثاً يُترك لدورةٍ لاحقة', () async {
    final fresh = await submission('S-8',
        status: 'submitted',
        documentUuid: 'D8',
        lastCheckedAt: now.subtract(const Duration(minutes: 1)));
    final stale = await submission('S-9',
        status: 'submitted',
        documentUuid: 'D9',
        lastCheckedAt: now.subtract(const Duration(hours: 3)));

    final due = await db.findSubmissionsAwaitingStatus(
        limit: 50, notCheckedSince: now.subtract(gap));
    final ids = due.map((e) => e.submissionId);

    expect(ids, contains(stale));
    expect(ids, isNot(contains(fresh)),
        reason: 'استطلاعٌ كلَّ دقيقةٍ لكلّ مستندٍ يُغرق بوّابةً حكوميّة');
  });

  // 🔴 استُطلع فلم يُحسَم: يجب أن يُسجَّل **وقتُ** الاستطلاع وإلّا استُطلع
  //    في كلّ دورةٍ أبداً — فيتحوّل التباعُدُ إلى لا شيء.
  test('🔴 وسمُ الاستطلاع يُباعد المستندَ الذي لم يُحسَم', () async {
    final id = await submission('S-T',
        status: 'submitted', documentUuid: 'DT');

    // قبل الوسم: مستحقّ.
    expect(
        (await db.findSubmissionsAwaitingStatus(
                limit: 50, notCheckedSince: now.subtract(gap)))
            .map((e) => e.submissionId),
        contains(id));

    await db.touchSubmissionChecked(id, at: now);

    // بعده: يُترك لدورةٍ لاحقة — وحالتُه لم تتغيّر.
    expect(
        await db.findSubmissionsAwaitingStatus(
            limit: 50, notCheckedSince: now.subtract(gap)),
        isEmpty,
        reason: 'بلا وسمٍ يُستطلَع نفسُ المستند في كلّ دورةٍ أبداً');

    final row = await (db.select(db.eInvoiceSubmissions)
          ..where((s) => s.id.equals(id)))
        .getSingle();
    expect(row.status, 'submitted',
        reason: 'الوسمُ يسجّل وقتاً — ولا يحكم على المستند');
  });

  test('الأقدمُ استطلاعاً أوّلاً، والحدُّ يُحترَم', () async {
    for (var i = 0; i < 4; i++) {
      await submission('S-L$i',
          status: 'submitted',
          documentUuid: 'DL$i',
          lastCheckedAt: now.subtract(Duration(hours: 4 - i)));
    }

    final due = await db.findSubmissionsAwaitingStatus(
        limit: 2, notCheckedSince: now.subtract(gap));

    expect(due, hasLength(2));
    expect(due.first.documentUuid, 'DL0',
        reason: 'الأطولُ انتظاراً أولى — وإلّا جاع الأقدمُ أبداً');
  });
}
