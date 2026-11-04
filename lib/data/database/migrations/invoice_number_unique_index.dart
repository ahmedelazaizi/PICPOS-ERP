// فهرسا تفرّد رقم الفاتورة (sales_invoices / purchase_invoices) — بلا ترحيل
// مخطط وبلا إعادة توليد database.g.dart.
//
// ═══ لماذا فهرسٌ خام يُركَّب في مرحلة الإقلاع المؤجَّلة ═══
// قواعد العملاء قد تحمل أرقاماً مكرَّرةً قديمة؛ فترحيلٌ يرفع schemaVersion
// ويفشل عند أول تكرار كان سيُسقط الإقلاع كلَّه. هنا: نحاول التركيب، وعند
// الفشل بسبب تكرارات **لا نعدّل ولا نحذف أيَّ صف** — نسجّل تحذيراً (عدد
// المجموعات المكرَّرة + أمثلة من الأرقام) ونتخطّى، ونعيد المحاولة في كل
// إقلاع لاحق. حين ينظّف المالك التكرارات يُركَّب الفهرس تلقائياً.
//
// ═══ النطاق (مقيس من الكود لا مفترَض) ═══
// • المبيعات: `invoice_number` عالميٌّ داخل القاعدة — لكل نوعٍ عدّادٌ
//   بادئته (POS/SINV)، والخادم يسبق رقم العميل برمز الفرع. يُستثنى:
//   - المحذوف ناعماً (`is_deleted` / `deleted_at`)، فرقمه قابلٌ لإعادة الاستعمال؛
//   - المرتجعات (`sale_type = 'return'`) لأن عدّادها (SRET) مستقلّ، وبادئة
//     العرض القديمة `invoice_code_prefix` تُشارَك بين الأنواع الثلاثة، فقد
//     يتطابق رقم مرتجعٍ مع رقم بيعٍ بصورة مشروعة.
// • المشتريات: العمود يحمل **رقم فاتورة المورد** حين يُدخَل (راجع
//   client_issue_m4_duplicate_invoice_no_test: «التفرّد لكل مورد لا عام»)،
//   فالنطاق `(supplier_id, invoice_number)` وإلّا كسرنا بياناتٍ مشروعة.
//
// الصيغة `CREATE UNIQUE INDEX IF NOT EXISTS … WHERE …` تعمل على SQLite وPostgreSQL
// (المسند `NOT is_deleted` صالحٌ للـboolean في PG ولـ0/1 في SQLite).
import 'package:drift/drift.dart' show Variable;

import '../../../core/logging/diagnostic_logger.dart';
import '../database.dart';

const String kSalesInvoiceNumberUniqueIndexName =
    'uq_sales_invoices_number_live';
const String kPurchaseInvoiceNumberUniqueIndexName =
    'uq_purchase_invoices_number_supplier_live';

const String _kLive = 'NOT is_deleted AND deleted_at IS NULL';
const String _kSalesScope = "$_kLive AND sale_type <> 'return'";

const String kCreateSalesInvoiceNumberUniqueIndexSql =
    'CREATE UNIQUE INDEX IF NOT EXISTS $kSalesInvoiceNumberUniqueIndexName '
    'ON sales_invoices(invoice_number) WHERE $_kSalesScope';

// الرقم أولاً ليخدم أيضاً بحثَ «هل الرقم محجوز؟» عند توليد الأرقام.
const String kCreatePurchaseInvoiceNumberUniqueIndexSql =
    'CREATE UNIQUE INDEX IF NOT EXISTS $kPurchaseInvoiceNumberUniqueIndexName '
    'ON purchase_invoices(invoice_number, supplier_id) WHERE $_kLive';

/// نتيجة محاولة تركيب فهرس واحد.
enum InvoiceNumberIndexOutcome { ready, skippedDuplicates, failed }

class _Spec {
  const _Spec(this.label, this.indexName, this.createSql, this.table,
      this.groupCols, this.scope);
  final String label;
  final String indexName;
  final String createSql;
  final String table;
  final String groupCols;
  final String scope;
}

const _specs = <_Spec>[
  _Spec('sales_invoices', kSalesInvoiceNumberUniqueIndexName,
      kCreateSalesInvoiceNumberUniqueIndexSql, 'sales_invoices',
      'invoice_number', _kSalesScope),
  _Spec('purchase_invoices', kPurchaseInvoiceNumberUniqueIndexName,
      kCreatePurchaseInvoiceNumberUniqueIndexSql, 'purchase_invoices',
      'invoice_number, supplier_id', _kLive),
];

/// يركّب الفهرسين إن أمكن. **لا يرمي أبداً** ولا يغيّر بيانات.
/// يُعيد النتيجة لكل جدول (للاختبار).
Future<Map<String, InvoiceNumberIndexOutcome>> ensureInvoiceNumberUniqueIndexes(
    AppDatabase db) async {
  final out = <String, InvoiceNumberIndexOutcome>{};
  for (final s in _specs) {
    out[s.label] = await _ensureOne(db, s);
  }
  return out;
}

Future<InvoiceNumberIndexOutcome> _ensureOne(AppDatabase db, _Spec s) async {
  try {
    await db.customStatement(s.createSql);
    return InvoiceNumberIndexOutcome.ready;
  } on StateError {
    return InvoiceNumberIndexOutcome.failed; // DB closed mid-startup
  } catch (createError) {
    // الفشل المتوقَّع: تكراراتٌ قديمة. نشخّص بقراءةٍ فقط.
    try {
      final stats = await db.customSelect(
        // CAST: PG's SUM(bigint) is numeric, which drift doesn't read as int.
        'SELECT COUNT(*) AS g, CAST(COALESCE(SUM(c - 1), 0) AS BIGINT) AS extra '
        'FROM ('
        'SELECT COUNT(*) AS c FROM ${s.table} WHERE ${s.scope} '
        'GROUP BY ${s.groupCols} HAVING COUNT(*) > 1) d',
      ).getSingle();
      final groups = (stats.data['g'] as num).toInt();
      final extra = (stats.data['extra'] as num).toInt();
      if (groups > 0) {
        final ex = await db.customSelect(
          'SELECT invoice_number AS n FROM ${s.table} WHERE ${s.scope} '
          'GROUP BY ${s.groupCols} HAVING COUNT(*) > 1 '
          'ORDER BY COUNT(*) DESC, invoice_number LIMIT 5',
        ).get();
        final samples = ex.map((r) => r.data['n']).join(', ');
        await DiagnosticLogger.log(
            'INVOICE-NUMBER-UNIQUE',
            '⚠ ${s.indexName} skipped: $groups duplicated number group(s) '
                '($extra surplus row(s)) in ${s.label}; examples: $samples. '
                'No row was changed. Clean the duplicates (void/renumber '
                'manually) and the index is created on the next startup.');
        return InvoiceNumberIndexOutcome.skippedDuplicates;
      }
    } catch (_) {/* fall through to the generic failure log */}
    await DiagnosticLogger.log('INVOICE-NUMBER-UNIQUE',
        '⚠ ${s.indexName} could not be created (no duplicates found): '
        '$createError');
    return InvoiceNumberIndexOutcome.failed;
  }
}

/// هل [number] محجوزٌ فعلاً لدى مستندٍ حيٍّ من نوع [canonicalPrefix]؟
/// يُستعمل في توليد الأرقام لتخطّي ما كان سيخرق الفهرس. بادئات غير الفواتير
/// (سندات، مرتجعات…) ⇒ `false` (لا فهرس عليها فلا تخطّي ولا فجوات).
Future<bool> invoiceNumberInUse(
    AppDatabase db, String canonicalPrefix, String number) async {
  final String sql;
  switch (canonicalPrefix) {
    case AppDatabase.defaultSalesPosPrefix:
    case AppDatabase.defaultSalesManualPrefix:
      sql = 'SELECT 1 AS x FROM sales_invoices WHERE invoice_number = ? '
          'AND $_kSalesScope LIMIT 1';
    case AppDatabase.defaultPurchasePrefix:
      sql = 'SELECT 1 AS x FROM purchase_invoices WHERE invoice_number = ? '
          'AND $_kLive LIMIT 1';
    default:
      return false;
  }
  final rows = await db
      .customSelect(sql, variables: [Variable.withString(number)])
      .get();
  return rows.isNotEmpty;
}
