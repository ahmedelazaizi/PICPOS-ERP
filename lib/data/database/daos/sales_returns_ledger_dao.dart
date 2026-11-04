// ═══════════════════════════════════════════════════════════════════════════
// FS-16 — ما قيّده الأستاذُ فعلاً لمرتجعات فواتيرَ بعينها
// ═══════════════════════════════════════════════════════════════════════════
//
// تقريرُ المبيعات كان يقدّر تكلفةَ المرتجع تناسبياً من المبلغ المردود (شاملَ
// الضريبة)، فيخالف `5211` في الأستاذ: الربحُ ١٣٦٫٢٤١ مقابل ١٣٦٫٦٦٧ في دورة
// `fs_01`. والصحيحُ مسجَّلٌ أصلاً: قيدُ المرتجع
// (`autoPostSalesReturn`، ‏`reference_type='sales_return'`) يحمل سطرَ عكس
// التكلفة بتكلفة السطر المجمَّدة وقتَ البيع، وسطرَ عكس الضريبة.

part of '../database.dart';

/// الجزءُ المشترَك الوحيدُ الذي يربط مستندَ المرتجع (‏`sale_type='return'`)
/// بفاتورته الأصلية: `(doc_id, doc_total, orig_id)`.
///
/// ⚠️ مصدرٌ واحدٌ لا نسختان: [SalesDao.getReturnedAmountsForInvoices] يجمع منه
/// المبلغَ المردود، و[SalesReturnsLedgerDao.getReturnLedgerAmountsForInvoices]
/// يقرأ قيودَ المستندات **نفسِها**. لو افترق الربطُ لطُرح ردٌّ من فاتورةٍ
/// وتكلفتُه من أخرى. الحلُّ بالمعرّف العالميّ أوّلاً ثمّ بالرقم (انظر
/// `return_original_link.dart`)، والمحذوفُ ناعماً خارجَه.
const String _salesReturnDocLinkSql = '''
SELECT r.id AS doc_id, r.total AS doc_total,
       COALESCE(orig.id, r.legacy_id) AS orig_id
FROM (
  SELECT id, total,
    CAST(SUBSTR(notes, INSTR(notes, '#') + 1) AS INTEGER) AS legacy_id,
    CASE WHEN INSTR(notes, '|gid:') > 0
         THEN SUBSTR(notes, INSTR(notes, '|gid:') + 5) END AS orig_gid
  FROM sales_invoices
  WHERE sale_type = 'return'
    AND notes LIKE 'Return for invoice #%'
    AND is_deleted = 0
) r
LEFT JOIN sales_invoices orig ON orig.global_id = r.orig_gid
''';

extension SalesReturnsLedgerDao on AppDatabase {
  /// `{معرّفُ الفاتورة الأصلية: (cogs, vat)}` كما قيّدها قيدُ المرتجع:
  /// `cogs` = دائنُ حساب تكلفة البضاعة المربوط، و`vat` = مدينُ حساب ضريبة
  /// المخرجات المربوط.
  ///
  /// يغطّي شكلَي المرتجع كما يغطّيهما [getReturnedAmountsForInvoices]:
  ///   * الشاشةُ المستقلّة: القيدُ مربوطٌ بالأصل مباشرةً (`reference_id`).
  ///   * مستندُ `sale_type='return'`: القيدُ مربوطٌ بالمستند، والمستندُ
  ///     بالأصل عبر [_salesReturnDocLinkSql].
  ///
  /// ولا يُحسم قيدُ الإلغاء (`return_cancel`) هنا عمداً: الطرفُ المقابلُ
  /// [getReturnedAmountsForInvoices] لا يحسمه أيضاً في الشكل المستقلّ،
  /// والتقريرُ يجب أن يطرح التكلفةَ والإيرادَ **لنفس الأحداث**. فاتورةٌ رُدّ
  /// عليها ولا قيدَ لها هنا (نسخةُ العميل قبل وصول القيد) تغيب عن الخريطة،
  /// فيعلّمها التقريرُ تقديريّةً بدل اختلاق رقم.
  Future<Map<int, ({double cogs, double vat})>>
      getReturnLedgerAmountsForInvoices(List<int> invoiceIds) async {
    if (invoiceIds.isEmpty) return const {};
    final cogsCode = await accountingDao.getMappedAccountCode(
      'cogs',
      AccountingDao.accountPurposes['cogs']!,
    );
    final vatCode = await accountingDao.getMappedAccountCode(
      'output_vat',
      AccountingDao.accountPurposes['output_vat']!,
    );
    final ph = List.filled(invoiceIds.length, '?').join(',');
    final ids = [for (final id in invoiceIds) Variable.withInt(id)];
    const sums = 'COALESCE(SUM(CASE WHEN a.code = ? '
        'THEN jel.credit - jel.debit ELSE 0 END), 0) AS cogs, '
        'COALESCE(SUM(CASE WHEN a.code = ? '
        'THEN jel.debit - jel.credit ELSE 0 END), 0) AS vat';
    final lineJoin = 'JOIN journal_entry_lines jel ON jel.entry_id = je.id '
        'JOIN accounts a ON a.id = jel.account_id '
        "WHERE je.reference_type = 'sales_return' "
        'AND je.is_deleted = ${sqlBool(false)} '
        'AND je.is_posted = ${sqlBool(true)}';
    final codes = [Variable<String>(cogsCode), Variable<String>(vatCode)];

    final direct = await customSelect(
      'SELECT je.reference_id AS orig_id, $sums '
      'FROM journal_entries je $lineJoin '
      'AND je.reference_id IN ($ph) GROUP BY je.reference_id',
      variables: [...codes, ...ids],
      readsFrom: {journalEntries, journalEntryLines, accounts},
    ).get();
    final viaDocs = await customSelect(
      'SELECT link.orig_id AS orig_id, $sums '
      'FROM ($_salesReturnDocLinkSql) link '
      'JOIN journal_entries je ON je.reference_id = link.doc_id $lineJoin '
      'AND link.orig_id IN ($ph) GROUP BY link.orig_id',
      variables: [...codes, ...ids],
      readsFrom: {salesInvoices, journalEntries, journalEntryLines, accounts},
    ).get();

    final out = <int, ({double cogs, double vat})>{};
    for (final row in [...direct, ...viaDocs]) {
      final id = (row.data['orig_id'] as num?)?.toInt();
      if (id == null) continue;
      final prev = out[id] ?? (cogs: 0.0, vat: 0.0);
      out[id] = (
        cogs: prev.cogs + ((row.data['cogs'] as num?)?.toDouble() ?? 0.0),
        vat: prev.vat + ((row.data['vat'] as num?)?.toDouble() ?? 0.0),
      );
    }
    return out;
  }
}
