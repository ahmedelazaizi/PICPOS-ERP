// مستودعُ مسوّدات المرتجعات وسجلّهما — J2.
//
// الشاشاتُ لا تستورد `data/database` (حارسُ `presentation_db_import_guard`)،
// فتمرّ من هنا بأنواع `domain/models/return_draft.dart` وحدَها.
//
// ⚠️ **لا ترحيلَ هنا.** «مراجعة واعتماد» ينادي المسارَ القائمَ نفسَه
//    (`SalesReturnNotifier.processReturn` / `PurchaseReturnNotifier
//    .processReturn` ← المستودعات) بلا نسخةٍ ثانية؛ وهذا المستودعُ يحفظ
//    المسوّدةَ قبلَه ويختمها بعده فقط.
import '../../domain/models/document_record.dart';
import '../../domain/models/return_draft.dart';
import '../database/database.dart';

class ReturnDraftsRepository {
  ReturnDraftsRepository(this._db);

  final AppDatabase _db;

  Future<int> saveDraft(ReturnDraftInput input) => _db.saveReturnDraft(input);

  Future<ReturnDraft?> getDraft(int id) => _db.getReturnDraft(id);

  Future<void> deleteDraft(int id) => _db.deleteReturnDraft(id);

  /// الفاتورةُ الأصلُ لمسوّدة مبيعات — قد تقع خارجَ مدى منتقي الاستمارة.
  Future<SalesInvoiceData?> getSalesInvoice(int id) =>
      (_db.select(_db.salesInvoices)..where((i) => i.id.equals(id)))
          .getSingleOrNull();

  /// الفاتورةُ الأصلُ لمسوّدة مشتريات.
  Future<PurchaseInvoiceData?> getPurchaseInvoice(int id) =>
      (_db.select(_db.purchaseInvoices)..where((i) => i.id.equals(id)))
          .getSingleOrNull();

  /// يختم المسوّدةَ «معتمد» برقم السند الذي وُلِّد في معاملة الترحيل —
  /// آخرُ سندٍ كُتب على الفاتورة الأصل.
  Future<void> markPosted(ReturnDraft draft) async {
    final vouchers = await _db.returnVouchersByInvoice(
      [draft.originalInvoiceId],
      salesSide: draft.kind == ReturnDraftKind.sales,
    );
    final legs = vouchers[draft.originalInvoiceId];
    await _db.markReturnDraftPosted(
      draft.id,
      postedNumber: (legs == null || legs.isEmpty) ? null : legs.last.voucher,
    );
  }

  /// بعد إلغاء المرتجع القائم (يلغي كلَّ مرتجعات الفاتورة معاً).
  Future<void> markSalesCancelled(int originalInvoiceId) =>
      _db.markSalesReturnDraftsCancelled(originalInvoiceId);

  /// سجلُّ مرتجعات المبيعات: المسوّداتُ والملغاةُ من `return_drafts`،
  /// والمعتمدُ من [AppDatabase.getSalesReturnHistoryEntries] (القراءةُ نفسُها
  /// التي كان يعرضها حوارُ «سجل مرتجعات المبيعات» — صفٌّ لكلّ فاتورةٍ أصل،
  /// وهو ما يعمل عليه الإلغاءُ القائم).
  Future<List<SalesReturnRecordEntry>> salesRecords({
    required DateTime from,
    required DateTime to,
    Set<int>? branchIds,
  }) async {
    final drafts = await _db.listReturnDraftRecords(
      kind: ReturnDraftKind.sales,
      statuses: const {
        ReturnRecordStatus.draft,
        ReturnRecordStatus.posted,
        ReturnRecordStatus.cancelled,
      },
      from: from,
      to: to,
      branchIds: branchIds,
    );
    final entries = await _db.getSalesReturnHistoryEntries(
      from,
      to,
      allowedBranchIds: branchIds,
    );
    final ids = [for (final e in entries) e.originalInvoiceId];
    final vouchers = await _db.returnVouchersByInvoice(ids, salesSide: true);
    final names = await _partyNames({
      for (final e in entries)
        if ((e.originalInvoice ?? e.invoice).customerId != null)
          (e.originalInvoice ?? e.invoice).customerId!,
    });

    final postedDraftTax = <int, double>{};
    for (final d in drafts) {
      if (d.status == ReturnRecordStatus.posted) {
        postedDraftTax[d.originalInvoiceId] =
            (postedDraftTax[d.originalInvoiceId] ?? 0) + d.tax;
      }
    }

    final out = <SalesReturnRecordEntry>[
      for (final d in drafts)
        if (d.status != ReturnRecordStatus.posted)
          SalesReturnRecordEntry(row: d),
    ];
    for (final e in entries) {
      final original = e.originalInvoice ?? e.invoice;
      final legs = vouchers[e.originalInvoiceId] ?? const [];
      final settlement = legs.isEmpty
          ? null
          : (legs.any((l) => l.cash) && legs.any((l) => l.balance))
              ? 'mixed'
              : (legs.any((l) => l.balance) ? 'balance' : 'cash');
      // الضريبةُ: ما سُجّل على المسوّدات المعتمدة لهذه الفاتورة، وإلا
      // قسطُها من ضريبة الفاتورة الأصل بنسبة المرتجَع.
      final tax = postedDraftTax[e.originalInvoiceId] ??
          (original.total > 0
              ? original.tax * (e.returnAmount / original.total)
              : 0.0);
      out.add(SalesReturnRecordEntry(
        row: ReturnRecordRow(
          key: 'p${e.originalInvoiceId}',
          status: ReturnRecordStatus.posted,
          number: legs.isEmpty
              ? '—'
              : (legs.length == 1
                  ? legs.last.voucher
                  : '${legs.last.voucher} (+${legs.length - 1})'),
          date: legs.isNotEmpty && legs.last.at != null
              ? legs.last.at!
              : e.invoice.invoiceDate,
          originalInvoiceId: e.originalInvoiceId,
          originalInvoiceNumber: e.originalInvoiceNumber,
          partyName: original.customerId == null
              ? null
              : names[original.customerId],
          settlement: settlement,
          tax: tax,
          total: e.returnAmount,
          isFullReturn: e.isFullReturn,
        ),
        originalInvoice: e.originalInvoice,
      ));
    }
    out.sort((a, b) => b.row.date.compareTo(a.row.date));
    return out;
  }

  /// ما يُكمّل سجلَّ مردودات المشتريات فوق مستنداته المرحَّلة.
  Future<PurchaseReturnRecordExtras> purchaseExtras({
    required DateTime from,
    required DateTime to,
    Set<int>? branchIds,
  }) async {
    final drafts = await _db.listReturnDraftRecords(
      kind: ReturnDraftKind.purchase,
      from: from,
      to: to,
      branchIds: branchIds,
    );
    final voidedDocs = await _db.listVoidedPurchaseReturnRecords(
      from: from,
      to: to,
      branchIds: branchIds,
    );
    final posted = await _db
        .watchPurchaseReturnRecords(from: from, to: to, branchIds: branchIds)
        .first;
    final ids = {
      for (final r in posted) r.originalInvoiceId,
      for (final r in voidedDocs) r.originalInvoiceId,
    }.toList();
    final vouchers = await _db.returnVouchersByInvoice(ids, salesSide: false);
    return PurchaseReturnRecordExtras(
      drafts: drafts,
      voided: [
        for (final r in voidedDocs)
          purchaseRecordRow(r, ReturnRecordStatus.cancelled),
      ],
      vouchers: vouchers,
    );
  }

  Future<Map<int, String>> _partyNames(Set<int> ids) async {
    if (ids.isEmpty) return const {};
    final rows = await (_db.select(_db.parties)
          ..where((p) => p.id.isIn(ids.toList())))
        .get();
    return {for (final p in rows) p.id: p.name};
  }
}

/// صفُّ مستند مردود مشتريات (مرحَّلٌ أو ملغى) بصيغة السجلّ.
ReturnRecordRow purchaseRecordRow(
  PurchaseReturnRecord r,
  ReturnRecordStatus status, {
  String? number,
  String? settlement,
}) =>
    ReturnRecordRow(
      key: 'p${r.id}',
      status: status,
      number: number ?? '—',
      date: r.returnDate,
      originalInvoiceId: r.originalInvoiceId,
      originalInvoiceNumber: r.originalInvoiceNumber,
      partyName: r.supplierName,
      reason: r.reason,
      settlement: settlement ?? r.refundMethod,
      tax: r.tax,
      total: r.total,
      isFullReturn: r.isFullReturn,
      documentId: r.id,
    );

/// صفُّ سجلّ مرتجعات المبيعات مع الفاتورة الأصل التي يعمل عليها الإلغاءُ
/// وإعادةُ الطباعة (لا تُعرَض؛ تُمرَّر للفعل).
class SalesReturnRecordEntry {
  const SalesReturnRecordEntry({required this.row, this.originalInvoice});
  final ReturnRecordRow row;
  final SalesInvoiceData? originalInvoice;
}
