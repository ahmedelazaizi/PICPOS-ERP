// تقادمُ الذمم يتبع **الاستحقاق** لا تاريخَ الإصدار.
//
// ═══ ما يحمي هذا الملفّ ═══
//
// كان التقادمُ يُحسب من `invoice_date` لأنّ الاستحقاقَ لا وجودَ له، فيقرأ
// المشغّلُ عمراً أقصرَ من الحقيقة لكلّ فاتورةٍ لها مهلةُ سداد: فاتورةٌ
// بمهلةِ ٣٠ يوماً مضى على إصدارها ٤٠ ليست متأخّرةً ٤٠ يوماً بل **١٠**.
//
// وفحصان متضادّان عمداً:
//
//  ‏١) **فاتورةٌ بلا استحقاق** ⇒ تقع في نفس الشريحة التي كانت تقع فيها قبل
//     v164 بالضبط. فترقيةٌ تُزحزح أرقامَ دفاترِ المالك بلا أن يطلب أسوأُ من
//     ترقيةٍ لا تفعل شيئاً — وكلُّ فواتيرِ ما قبلَ الترقية `due_date` فيها
//     فارغ.
//  ‏٢) **فاتورةٌ باستحقاقٍ صريح** ⇒ تتحرّك إلى الشريحة الصحيحة. وبدون هذا
//     الفحص يبقى العمودُ مكتوباً ولا يقرؤه أحد — وهو أسوأُ من غيابه: يوحي
//     بأنّ المهلةَ محسوبةٌ وهي مهمَلة.
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';

void main() {
  late AppDatabase db;
  late int wh;
  late int supplier;

  final asOf = DateTime(2026, 8, 26);

  setUp(() async {
    db = AppDatabase.forTesting();
    wh = await db
        .into(db.warehouses)
        .insert(WarehousesCompanion.insert(name: 'المخزن'));
    supplier = await db.into(db.parties).insert(
          PartiesCompanion.insert(
            name: 'مورّد الألبان',
            isSupplier: const Value(true),
          ),
        );
  });

  Future<void> purchase({
    required DateTime issued,
    DateTime? due,
    double total = 1000,
  }) async {
    await db.into(db.purchaseInvoices).insert(
          PurchaseInvoicesCompanion.insert(
            invoiceNumber: 'P-${issued.day}-${due?.day ?? 0}',
            supplierId: supplier,
            warehouseId: wh,
            invoiceDate: issued,
            dueDate: Value(due),
            total: Value(total),
            paid: const Value(0),
          ),
        );
    // رصيدُ الطرف شرطُ ظهوره في التقرير (`p.balance > 0.01`).
    await (db.update(db.parties)..where((p) => p.id.equals(supplier)))
        .write(PartiesCompanion(balance: Value(total)));
  }

  /// الشريحةُ التي وقع فيها المبلغ — واحدةٌ فقط تحمل قيمة.
  Future<String> bucketOf() async {
    final rows = await db.getArAgingReport(
        asOfDate: asOf, customersOnly: false);
    expect(rows, isNotEmpty, reason: 'المورّدُ لم يظهر في التقرير أصلاً');
    final r = rows.first;
    if (r.bucket0_30 > 0) return '0-30';
    if (r.bucket31_60 > 0) return '31-60';
    if (r.bucket61_90 > 0) return '61-90';
    if (r.bucket90Plus > 0) return '90+';
    return 'none';
  }

  test('بلا استحقاق ⇒ العمرُ من تاريخ الإصدار كما قبل الترقية', () async {
    // صدرت قبل ٤٥ يوماً ⇒ شريحةُ ٣١—٦٠ حسابَ الإصدار.
    await purchase(issued: asOf.subtract(const Duration(days: 45)));
    expect(await bucketOf(), '31-60',
        reason: 'أرقامُ التقادم تحرّكت لفواتيرَ بلا مهلة');
  });

  test('باستحقاقٍ صريح ⇒ العمرُ من الاستحقاق لا الإصدار', () async {
    // صدرت قبل ٤٥ يوماً بمهلةِ ٣٠ ⇒ متأخّرةٌ **١٥** يوماً فقط ⇒ شريحةُ ٠—٣٠.
    final issued = asOf.subtract(const Duration(days: 45));
    await purchase(issued: issued, due: issued.add(const Duration(days: 30)));
    expect(await bucketOf(), '0-30',
        reason: 'العمودُ مكتوبٌ ولا يقرؤه التقادم — مهلةُ السداد مهمَلة');
  });

  test('استحقاقٌ لم يحن بعدُ ⇒ أحدثُ شريحة', () async {
    final issued = asOf.subtract(const Duration(days: 10));
    await purchase(issued: issued, due: asOf.add(const Duration(days: 20)));
    expect(await bucketOf(), '0-30');
  });
}
