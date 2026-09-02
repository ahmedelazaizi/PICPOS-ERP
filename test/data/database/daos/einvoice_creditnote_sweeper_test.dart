// ═══════════════════════════════════════════════════════════════════════════
// مِكنسةُ إشعارات الائتمان — أيُّ مرتجعٍ ينتظر تقديماً، وما أصلُه؟
// ═══════════════════════════════════════════════════════════════════════════
//
// ═══ لماذا كان مؤجَّلاً ═══
//
// `SalesInvoices` لا يحمل عموداً يربط المرتجعَ بأصله — الرابطُ نصٌّ في `notes`
// بصيغة `Return for invoice #<id>|gid:<uuid>`. ومِكنسةُ الفواتير تركت
// المرتجعاتِ صراحةً لأنّ إشعارَ الائتمان بلا أصلٍ يشير إليه **مستندٌ باطل**،
// وسقفُ مبلغه لا يُشتقّ من صفِّ المرتجع وحدَه.
//
// ═══ والحلُّ يحلّ بالمعرّف العالميّ أوّلاً ═══
//
// المعرّفُ الرقميُّ لا معنى له إلّا في المخزن الذي كتبه، والسحبُ يستبدل صفَّ
// العميل بصفِّ الخادم. فمرتجعٌ جاء بالمزامنة يحمل رقمَ **الخادم** — وقراءتُه
// كرقمٍ محلّيٍّ تشير إلى فاتورةٍ أخرى تماماً، فيُقدَّم إشعارُ ائتمانٍ على
// فاتورةِ عميلٍ بريء.

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/domain/models/return_original_link.dart';

void main() {
  late AppDatabase db;
  late int whId;

  setUp(() async {
    db = AppDatabase.forTesting();
    await db.saveEInvoiceConfig(
      platform: 'eta',
      clientId: 'id',
      clientSecret: 'secret',
      registrationNumber: '100',
      isEnabled: true,
    );
    final branchId = await db.into(db.branches).insert(
        BranchesCompanion.insert(name: 'ف', globalId: const Value('br-cn')));
    whId = await db.into(db.warehouses).insert(WarehousesCompanion.insert(
        name: 'م', branchId: Value(branchId), globalId: const Value('wh-cn')));
  });

  tearDown(() => db.close());

  Future<int> invoice(String number, {String? gid, double total = 100}) =>
      db.into(db.salesInvoices).insert(SalesInvoicesCompanion.insert(
            invoiceNumber: number,
            warehouseId: whId,
            userId: 1,
            invoiceDate: DateTime(2026, 9, 1),
            total: Value(total),
            globalId: Value(gid),
          ));

  Future<int> ret(String number, {String? notes, double total = 40}) =>
      db.into(db.salesInvoices).insert(SalesInvoicesCompanion.insert(
            invoiceNumber: number,
            warehouseId: whId,
            userId: 1,
            invoiceDate: DateTime(2026, 9, 2),
            total: Value(total),
            saleType: const Value('return'),
            notes: Value(notes),
          ));

  /// يجعل أصلاً **معتمَداً لدى البوّابة**: إشعارُ الائتمان يشير إلى
  /// `documentUuid` الخاصِّ بمستند الأصل، فأصلٌ بلا اعتمادٍ يُنتج إشعاراً
  /// بمرجعٍ فارغ.
  Future<void> acceptOriginal(int originalId) async {
    final sid = await db.createSubmission(saleId: originalId, platform: 'eta');
    await db.markSubmissionSuccess(
      submissionId: sid,
      submissionUuid: 'SUB-$originalId',
      documentUuid: 'DOC-$originalId',
    );
    await db.updateSubmissionStatus(sid, 'valid');
  }

  test('مرساة: مرتجعٌ مربوطٌ برقمٍ وأصلُه معتمَدٌ يُلتقَط بأصله', () async {
    final orig = await invoice('A-1');
    await acceptOriginal(orig);
    final r = await ret('R-1', notes: buildReturnOriginalLinkNote(orig));

    final due = await db.findReturnsNeedingCreditNoteSubmission(limit: 50);

    expect(due, hasLength(1));
    expect(due.single.returnSaleId, r);
    expect(due.single.originalSaleId, orig);
  });

  // 🔴 الترتيبُ شرطٌ لا تفصيل: الإشعارُ يحمل `documentUuid` الأصلِ.
  test('🔴 أصلٌ لم يُعتمَد بعد ⇒ لا يُقدَّم إشعارُه — مرجعٌ فارغ', () async {
    final orig = await invoice('A-WAIT');
    await ret('R-WAIT', notes: buildReturnOriginalLinkNote(orig));

    expect(await db.findReturnsNeedingCreditNoteSubmission(limit: 50), isEmpty,
        reason: 'إشعارُ ائتمانٍ يشير إلى مستندٍ لم تصدر له البوّابةُ معرّفاً '
            'يخرج بمرجعٍ فارغ — ويُرفَض أو يُقبَل خطأً');
  });

  test('🔴 وأصلٌ قُدِّم ولم يُعتمَد (بلا معرّف مستند) كذلك', () async {
    final orig = await invoice('A-PEND');
    await db.createSubmission(saleId: orig, platform: 'eta'); // معلَّقٌ بلا uuid
    await ret('R-PEND', notes: buildReturnOriginalLinkNote(orig));

    expect(await db.findReturnsNeedingCreditNoteSubmission(limit: 50), isEmpty);
  });

  // 🔴 لبُّ الحالة: المعرّفُ العالميُّ يتقدّم على الرقم.
  test('🔴 يُحلّ بالمعرّف العالميّ حين يخالف الرقمُ فاتورةً أخرى', () async {
    final real = await invoice('A-REAL', gid: 'gid-real');
    final innocent = await invoice('A-INNOCENT');
    await acceptOriginal(real);
    await acceptOriginal(innocent);

    // مرتجعٌ جاء بالمزامنة: رقمُه رقمُ الخادم — يصادف فاتورةَ عميلٍ بريء.
    final r = await ret('R-2',
        notes: buildReturnOriginalLinkNote(innocent,
            originalGlobalId: 'gid-real'));

    final due = await db.findReturnsNeedingCreditNoteSubmission(limit: 50);

    expect(due.single.returnSaleId, r);
    expect(due.single.originalSaleId, real,
        reason: 'القراءةُ بالرقم كانت ستُقدّم إشعارَ ائتمانٍ على فاتورة '
            'عميلٍ بريء');
    expect(due.single.originalSaleId, isNot(innocent));
  });

  test('🔴 مرتجعٌ بلا أصلٍ يُحلّ لا يُلتقَط — لا مستندَ بلا أصل', () async {
    await ret('R-3', notes: 'مرتجع سريع بلا أصل');
    await ret('R-4', notes: null);
    await ret('R-5', notes: buildReturnOriginalLinkNote(999999));

    expect(await db.findReturnsNeedingCreditNoteSubmission(limit: 50), isEmpty,
        reason: 'إشعارُ ائتمانٍ يشير إلى فاتورةٍ لا وجودَ لها مستندٌ باطل');
  });

  test('🔴 ومرتجعٌ له تقديمٌ قائمٌ لا يُلتقَط ثانيةً', () async {
    final orig = await invoice('A-6');
    final r = await ret('R-6', notes: buildReturnOriginalLinkNote(orig));
    await db.createSubmission(saleId: r, platform: 'eta');

    expect(await db.findReturnsNeedingCreditNoteSubmission(limit: 50), isEmpty);
  });

  test('والفاتورةُ العاديّةُ ليست إشعارَ ائتمان', () async {
    await invoice('A-7');

    expect(await db.findReturnsNeedingCreditNoteSubmission(limit: 50), isEmpty);
  });

  // ═══ السقفُ الضريبيّ ═══
  //
  // `createCreditNoteSubmission` وحدَها تفرضه، و`createSubmission` لا. والمسارُ
  // القديم كان ينادي الثانية — فالسقفُ الذي يسمّيه الكودُ «مخالفةً ضريبيّة»
  // **لا يُبلَغ أبداً**. والمِكنسةُ الآن تمرّ بالأولى.
  group('السقفُ الضريبيّ', () {
    test('🔴 إشعارٌ يتجاوز الفاتورةَ الأصليّة يُرفض', () async {
      final orig = await invoice('A-CAP', total: 100);
      await acceptOriginal(orig);
      final r = await ret('R-CAP',
          notes: buildReturnOriginalLinkNote(orig), total: 150);

      expect(
        () => db.createCreditNoteSubmission(
            returnSaleId: r, originalSaleId: orig, platform: 'eta'),
        throwsA(predicate((e) => '$e'.contains('مخالفة ضريبية'))),
        reason: 'إشعارُ ائتمانٍ يتجاوز أصلَه يردُّ للعميل أكثرَ ممّا دفع '
            'ويستردُّ ضريبةً لم تُحصَّل',
      );
    });

    test('وإشعارٌ مساوٍ أو أقلُّ يمرّ — ويحمل مرجعَ الأصل', () async {
      final orig = await invoice('A-OK', total: 100);
      await acceptOriginal(orig);
      final r = await ret('R-OK',
          notes: buildReturnOriginalLinkNote(orig), total: 100);

      final id = await db.createCreditNoteSubmission(
          returnSaleId: r, originalSaleId: orig, platform: 'eta');

      final row = await db.getSubmissionBySaleId(r);
      expect(row?.id, id);
      expect(row?.documentType, 'credit_note');
      expect(row?.internalId, 'DOC-$orig',
          reason: 'الإشعارُ يشير إلى معرّف مستند الأصل — وبلا مرجعٍ يُرفَض');
    });
  });

  test('الحدُّ يُحترَم', () async {
    for (var i = 0; i < 4; i++) {
      final o = await invoice('A-L$i');
      await acceptOriginal(o);
      await ret('R-L$i', notes: buildReturnOriginalLinkNote(o));
    }

    expect(await db.findReturnsNeedingCreditNoteSubmission(limit: 2),
        hasLength(2));
  });
}
