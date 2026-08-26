// هجرةُ v164 — الاستحقاقُ وشروطُ التعامل.
//
// ═══ ما يحمي هذا الملفّ ═══
//
// **فشلُ الترقية في هذا المستودع يُبتلَع.** وقع من قبلُ في v162: خطوةٌ رمت
// «no such column» فعُدَّت عديمةَ الأثر، فخُتمت القاعدةُ بالرقم الجديد **بلا
// أعمدة** — ثمّ سقط كلُّ استعلامٍ يقرؤها في التشغيل وحدَه. فالفحصُ هنا يقرأ
// `PRAGMA table_info` بعد الترقية ولا يثق برقم المخطَّط.
//
// وثلاثةُ أخطارٍ متمايزة:
//
//  ‏١) **عمودٌ لم يُضَف** — الأعمدةُ السبعةُ تُعَدُّ واحداً واحداً بأسمائها
//     في SQL لا بأسماء Dart، فالمولِّدُ هو الذي يترجم بينهما وقد يخطئ الاسم.
//  ‏٢) **الترقيةُ تكسر القديم** — قاعدةٌ فيها فواتيرُ قبلَ الترقية لا بدّ أن
//     تبقى مقروءةً بعدها بنفس أرقامها.
//  ‏٣) 🔴 **الأخطر: تحرُّكُ أرقام التقادم لحظةَ الترقية.** `due_date` يقبل
//     الفراغَ والفراغُ يعني «يستحق يومَ إصداره»، فعمرُ كلّ فاتورةٍ سابقةٍ
//     يجب أن يبقى **كما كان بالضبط**. ترقيةٌ تُبدّل أرقامَ دفاترِ المالك بلا
//     أن يطلب ذلك أسوأُ من ترقيةٍ لا تفعل شيئاً.
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting());

  Future<Set<String>> columnsOf(String table) async {
    final info = await db.customSelect('PRAGMA table_info($table)').get();
    return info.map((r) => r.data['name'] as String).toSet();
  }

  test('الأعمدةُ السبعةُ موجودةٌ بأسمائها في SQL', () async {
    // مرساة: لو انكسرت قراءةُ PRAGMA لعادت مجموعةً فارغةً ومرّ الفحصُ أعمى.
    final party = await columnsOf('parties');
    expect(party.length, greaterThan(15),
        reason: 'قراءةُ PRAGMA فشلت — الفحصُ أعمى');

    expect(party, containsAll(<String>[
      'payment_terms_days',
      'early_payment_discount_pct',
      'early_payment_discount_days',
      'supplier_rating',
    ]));
    expect(await columnsOf('sales_invoices'), contains('due_date'));
    expect(await columnsOf('purchase_invoices'), contains('due_date'));
    expect(await columnsOf('purchase_orders'), contains('received_at'));
  });

  test('الافتراضاتُ هي التي تُبقي السلوكَ كما كان', () async {
    final id = await db
        .into(db.parties)
        .insert(PartiesCompanion.insert(name: 'مطعم النيل'));
    final p = await db.getPartyById(id);

    // صفرٌ = يستحق يومَ الإصدار. ولو كان الافتراضُ ثلاثين يوماً لتغيّرت
    // أعمارُ كلّ فاتورةٍ في النظام لحظةَ الترقية.
    expect(p!.paymentTermsDays, 0);
    expect(p.earlyPaymentDiscountPct, 0);
    expect(p.earlyPaymentDiscountDays, 0);
    // `null` = لم يُقيَّم — وهي حالةٌ مختلفةٌ عن «تقييمٌ صفر».
    expect(p.supplierRating, isNull);
  });

  test('الفاتورةُ بلا استحقاقٍ صريحٍ تُقرأ بتاريخ إصدارها', () async {
    final wh = await db
        .into(db.warehouses)
        .insert(WarehousesCompanion.insert(name: 'المخزن'));
    final user = await db.into(db.users).insert(UsersCompanion.insert(
          username: 'cashier1',
          passwordHash: 'x',
          displayName: 'كاشير',
        ));
    final issued = DateTime(2026, 6, 1);
    await db.into(db.salesInvoices).insert(SalesInvoicesCompanion.insert(
          invoiceNumber: 'S-1',
          warehouseId: wh,
          userId: user,
          invoiceDate: issued,
          total: const Value(100),
        ));

    // نفسُ التعبير الذي تستعمله كلُّ قراءةٍ للتقادم.
    final row = await db.customSelect(
      'SELECT COALESCE(due_date, invoice_date) AS due_at FROM sales_invoices',
    ).getSingle();
    final dueAt = DateTime.fromMillisecondsSinceEpoch(
        ((row.data['due_at'] as num).toInt()) * 1000);

    expect(dueAt, issued,
        reason: 'فاتورةٌ بلا مهلةٍ تحرّك عمرُها — أرقامُ التقادم تبدّلت');
  });

  test('الاستحقاقُ لقطةٌ: تغييرُ مهلةِ الطرف لا يمسّ فاتورةً صدرت', () async {
    final wh = await db
        .into(db.warehouses)
        .insert(WarehousesCompanion.insert(name: 'المخزن'));
    final user = await db.into(db.users).insert(UsersCompanion.insert(
          username: 'cashier2',
          passwordHash: 'x',
          displayName: 'كاشير',
        ));
    final party = await db.into(db.parties).insert(
          PartiesCompanion.insert(
            name: 'سوبر ماركت النور',
            paymentTermsDays: const Value(30),
          ),
        );
    final issued = DateTime(2026, 6, 1);
    final due = issued.add(const Duration(days: 30));
    await db.into(db.salesInvoices).insert(SalesInvoicesCompanion.insert(
          invoiceNumber: 'S-2',
          warehouseId: wh,
          userId: user,
          customerId: Value(party),
          invoiceDate: issued,
          dueDate: Value(due),
          total: const Value(100),
        ));

    // المالكُ يشدّد المهلةَ إلى سبعةِ أيّام اليوم.
    await (db.update(db.parties)..where((p) => p.id.equals(party)))
        .write(const PartiesCompanion(paymentTermsDays: Value(7)));

    final inv = await (db.select(db.salesInvoices)
          ..where((i) => i.invoiceNumber.equals('S-2')))
        .getSingle();

    expect(inv.dueDate, due,
        reason: 'استحقاقُ فاتورةٍ صادرةٍ تحرّك بأثرٍ رجعيّ — أعمارُ الدين '
            'تبدّلت لمستنداتٍ أُغلقت');
  });

  test('رقمُ المخطَّط بلغ ١٦٤', () {
    // لو نُسي الرفعُ لما عملت الترقيةُ على قاعدةٍ قائمةٍ إطلاقاً.
    expect(db.schemaVersion, 164);
  });
}
