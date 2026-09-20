part of '../database.dart';

// ═══════════════════════════════════════════════════════════════════════════
// IMPORT PURCHASES DAO — تفاصيلُ فاتورة الاستيراد (v174، المرحلة ٨)
// ═══════════════════════════════════════════════════════════════════════════
//
// ═══ 🔴 صفُّ التفاصيل هو **الوسم** لا الزينة ═══
//
// `ImportPurchaseDetails` ١:١ مع `PurchaseInvoices`، ووجودُ الصفِّ هو
// **الفارقُ الوحيدُ** بين فاتورةِ استيرادٍ وفاتورةٍ محلّيّة. ولذلك:
//
//   • يُكتَب **ولو خلت حقولُه كلُّها** — «استيرادٌ لم تصل أوراقُه» حالةٌ
//     حقيقيّة، وعدمُ كتابته كان يُخفي الفاتورةَ عن الشاشة التي أُنشئت
//     فيها فيبحث عنها المستخدمُ في المحلّيّة.
//   • ويُكتَب **داخلَ معاملة الفاتورة نفسِها** (راجع
//     [_writeImportPurchaseDetails] ومناديَيه في `purchase_dao`): كتابتُه
//     بعدها تعني أنّ سقوطَه يترك فاتورةً بذمّةٍ ومخزونٍ وقيدٍ **بلا وسم**،
//     فتبدو محلّيّةً إلى الأبد ولا شيءَ يقول إنّ شيئاً سقط.
//
// ═══ ⚠️ والتفرّدُ فهرسٌ لا نيّة ═══
//
// لا `UNIQUE` على `purchase_invoice_id` في تعريف v174. وصفّان لفاتورةٍ
// واحدةٍ يُظهرانها مرّتين في القائمة ويجعلان قراءةَ «تفاصيلِ الفاتورة»
// اختياراً عشوائيّاً بين ورقتَي بيانٍ جمركيّ. فالفهرسُ في
// [kCreateImportPurchaseDetailsUniqueIndexSql] — يُركَّب في كلّ إقلاعٍ
// (SQLite) ومع تهيئة PG، والجدولُ فارغٌ في كلّ تنصيبةٍ قائمةٍ فلا تسويةَ
// تسبقه.

/// سطرُ قائمةِ المشتريات الخارجيّة — الفاتورةُ ووسمُها وما حُمِّل عليها.
typedef ImportPurchaseRow = ({
  ImportPurchaseDetailData details,
  PurchaseInvoiceData invoice,
  String supplierName,
  String? currencyCode,
  String? clearingAgent,
  double landedApplied,
  double landedDraft,
});

extension ImportPurchasesDao on AppDatabase {
  /// بثٌّ لإيقاظ القائمة — الصفوفُ تُقرأ بـ[getImportPurchaseRows].
  ///
  /// ⚠️ **ويبثّ على الجدولَين.** الفاتورةُ تتغيّر بلا أن يتغيّر وسمُها
  ///    (سدادٌ، إلغاء)، فبثٌّ على التفاصيل وحدَها يُجمّد أعمدةَ المبلغ
  ///    والحالة في القائمة حتى يُعاد فتحُ الشاشة.
  Stream<List<ImportPurchaseDetailData>> watchImportPurchases() {
    return (select(importPurchaseDetails)
          ..where((d) => d.deletedAt.isNull())
          ..orderBy([(d) => OrderingTerm.desc(d.id)]))
        .watch()
        .map((rows) => rows);
  }

  Future<ImportPurchaseDetailData?> getImportPurchaseDetailsFor(
    int purchaseInvoiceId,
  ) {
    return (select(importPurchaseDetails)
          ..where((d) =>
              d.purchaseInvoiceId.equals(purchaseInvoiceId) &
              d.deletedAt.isNull())
          ..limit(1))
        .getSingleOrNull();
  }

  /// صفوفُ الشاشة — الفواتيرُ الموسومةُ استيراداً وحدَها.
  Future<List<ImportPurchaseRow>> getImportPurchaseRows({int limit = 500}) async {
    final q = select(importPurchaseDetails).join([
      innerJoin(
        purchaseInvoices,
        purchaseInvoices.id.equalsExp(importPurchaseDetails.purchaseInvoiceId),
      ),
      leftOuterJoin(parties, parties.id.equalsExp(purchaseInvoices.supplierId)),
      leftOuterJoin(
        currencies,
        currencies.id.equalsExp(purchaseInvoices.currencyId),
      ),
    ])
      ..where(importPurchaseDetails.deletedAt.isNull())
      ..orderBy([OrderingTerm.desc(purchaseInvoices.invoiceDate)])
      ..limit(limit);

    final rows = await q.get();

    // وكيلُ التخليص: طرفٌ مسجَّلٌ أو نصّ — يُقرأ الاسمُ من `parties` حين
    // يكون معرِّفاً، فيتبع إعادةَ التسمية بدل لقطةٍ تتقادم.
    final agentIds = <int>{
      for (final r in rows)
        if (r.readTable(importPurchaseDetails).clearingAgentPartyId != null)
          r.readTable(importPurchaseDetails).clearingAgentPartyId!,
    };
    final agentNames = <int, String>{};
    if (agentIds.isNotEmpty) {
      final agents = await (select(parties)
            ..where((p) => p.id.isIn(agentIds)))
          .get();
      for (final a in agents) {
        agentNames[a.id] = a.name;
      }
    }

    // التكاليفُ المحمَّلة — **مفصولةً بحالتها**. مجموعٌ واحدٌ يخلط ورقةً
    // مسوّدةً لم تُقيَّد بورقةٍ طُبِّقت فعلاً، فيقرأ المستخدمُ تكلفةً
    // دخلت الدفترَ وهي لم تدخل.
    final invoiceIds = <int>{
      for (final r in rows) r.readTable(purchaseInvoices).id,
    };
    final applied = <int, double>{};
    final draft = <int, double>{};
    if (invoiceIds.isNotEmpty) {
      final sheets = await (select(landedCostSheets)
            ..where((s) => s.purchaseInvoiceId.isIn(invoiceIds)))
          .get();
      for (final s in sheets) {
        if (s.status == 'applied') {
          applied[s.purchaseInvoiceId] =
              (applied[s.purchaseInvoiceId] ?? 0) + s.totalAdditionalCost;
        } else if (s.status == 'draft') {
          draft[s.purchaseInvoiceId] =
              (draft[s.purchaseInvoiceId] ?? 0) + s.totalAdditionalCost;
        }
      }
    }

    return [
      for (final r in rows)
        (
          details: r.readTable(importPurchaseDetails),
          invoice: r.readTable(purchaseInvoices),
          supplierName: r.readTableOrNull(parties)?.name ?? 'غير معروف',
          currencyCode: r.readTableOrNull(currencies)?.code,
          clearingAgent:
              r.readTable(importPurchaseDetails).clearingAgentPartyId != null
                  ? agentNames[
                      r.readTable(importPurchaseDetails).clearingAgentPartyId!]
                  : r.readTable(importPurchaseDetails).clearingAgentName,
          landedApplied: applied[r.readTable(purchaseInvoices).id] ?? 0,
          landedDraft: draft[r.readTable(purchaseInvoices).id] ?? 0,
        ),
    ];
  }

  /// تحريرُ الحقول المستنديّة لفاتورةٍ قائمة.
  ///
  /// ⚠️ **ولا تُنشئ صفّاً إن غاب.** الوسمُ يُولَد مع الفاتورة في معاملتها
  ///    (راجع رأسَ الملفّ)، وإنشاؤه هنا كان يحوّل فاتورةً محلّيّةً إلى
  ///    خارجيّةٍ بتحريرِ حقلِ ميناء — تصنيفٌ يتغيّر من بابٍ خلفيّ.
  Future<void> updateImportPurchaseDetails({
    required int purchaseInvoiceId,
    required ImportDocumentFields fields,
  }) async {
    final bad = validateImportDocument(fields);
    if (bad != null) throw ArgumentError(bad);

    await transaction(() async {
      final existing = await getImportPurchaseDetailsFor(purchaseInvoiceId);
      if (existing == null) {
        throw StateError(
          'لا وسمَ استيرادٍ للفاتورة $purchaseInvoiceId — '
          'التفاصيلُ تُنشأ مع الفاتورة لا بعدَها',
        );
      }
      await (update(importPurchaseDetails)
            ..where((d) => d.id.equals(existing.id)))
          .write(
        ImportPurchaseDetailsCompanion(
          customsDeclarationNo: Value(fields.customsDeclarationNo),
          billOfLading: Value(fields.billOfLading),
          countryOfOrigin: Value(fields.countryOfOrigin),
          port: Value(fields.port),
          letterOfCredit: Value(fields.letterOfCredit),
          clearingAgentPartyId: Value(fields.clearingAgentPartyId),
          clearingAgentName: Value(fields.clearingAgentName),
          notes: Value(fields.notes),
          lastModifiedAt: Value(DateTime.now()),
        ),
      );
    });
  }

  /// كتابةُ الوسم — **تُنادى من داخل معاملة الفاتورة وحدَها**.
  ///
  /// راجع رأسَ الملفّ: فصلُها عن المعاملة يترك فاتورةَ استيرادٍ بلا وسم.
  Future<void> _writeImportPurchaseDetails(
    int purchaseInvoiceId,
    ImportDocumentFields fields,
  ) async {
    final bad = validateImportDocument(fields);
    if (bad != null) throw ArgumentError(bad);

    await into(importPurchaseDetails).insert(
      ImportPurchaseDetailsCompanion.insert(
        purchaseInvoiceId: purchaseInvoiceId,
        customsDeclarationNo: Value(fields.customsDeclarationNo),
        billOfLading: Value(fields.billOfLading),
        countryOfOrigin: Value(fields.countryOfOrigin),
        port: Value(fields.port),
        letterOfCredit: Value(fields.letterOfCredit),
        clearingAgentPartyId: Value(fields.clearingAgentPartyId),
        clearingAgentName: Value(fields.clearingAgentName),
        notes: Value(fields.notes),
        // هويّةٌ تسبق أوّلَ مزامنة — الصفُّ قد يُنشَأ دون اتّصالٍ ويُدفَع
        // لاحقاً، فلا بدّ أن يحمل حينها نفسَ المعرِّف.
        globalId: Value(UuidV7.generate()),
        lastModifiedAt: Value(DateTime.now()),
      ),
    );
  }
}
