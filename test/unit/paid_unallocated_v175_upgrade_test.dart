// ترقيةُ v175 على قاعدةٍ **قائمة** — والملءُ أهمُّ من الإضافة.
//
// ═══ 🔴 لماذا لا يكفي اختبارُ التعريف ═══
//
// كلُّ فحصٍ يبني `AppDatabase.forTesting()` يقيس `onCreate` — أي تعريفَ
// اليوم. والعمودُ الجديد يُضاف بـ`DEFAULT 0`، فيمرّ ذلك الفحصُ أخضرَ وهو
// لا يمسّ `onUpgrade` بحال.
//
// وعلى قاعدةٍ قائمةٍ يعني الصفرُ: «لم يُسدَّد من هذه الفاتورة شيءٌ خارجَ
// التخصيصات» — وهو كذبٌ على **كلّ** تاريخ التنصيبة. وأوّلُ إعادةِ حسابٍ
// بعدها تُصفِّر `paid` لكلّ فاتورةٍ مضت.
//
// وهو عينُ ما وقع لـ`approved_by`: عمودٌ أضافته الهجرةُ وحدَها فغاب عن
// التنصيبات الجديدة. هنا العكسُ: عمودٌ صحيحُ التعريف وملؤه هو الناقص.

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.forTesting();
    // قاعدةٌ عند v174: العمودُ غيرُ موجودٍ أصلاً.
    await db.customStatement(
      'ALTER TABLE sales_invoices DROP COLUMN paid_unallocated',
    );
  });

  Future<Set<String>> invoiceColumns() async {
    final rows =
        await db.customSelect('PRAGMA table_info(sales_invoices)').get();
    return rows.map((r) => r.data['name'] as String).toSet();
  }

  Future<double> baseOf(int id) async {
    final row = await db
        .customSelect('SELECT paid_unallocated FROM sales_invoices '
            'WHERE id = ?', variables: [Variable<int>(id)])
        .getSingle();
    return (row.data['paid_unallocated'] as num).toDouble();
  }

  Future<int> seedInvoice({
    required String number,
    required double total,
    required double paid,
  }) async {
    await db.customStatement(
      'INSERT INTO sales_invoices '
      '(invoice_number, warehouse_id, user_id, invoice_date, subtotal, '
      ' discount, tax, total, paid, payment_method, status) '
      "VALUES (?, 1, 1, ?, ?, 0, 0, ?, ?, 'credit', 'partial')",
      // ⚠️ **`customStatement` تأخذ قيماً خامّةً لا `Variable<>`** (خلافاً
      //    لـ`customSelect`)، والتاريخُ عددٌ صحيحٌ لأنّ العمودَ `INTEGER`.
      [
        number,
        DateTime(2026, 5, 1).millisecondsSinceEpoch ~/ 1000,
        total,
        total,
        paid,
      ],
    );
    final row = await db
        .customSelect('SELECT id FROM sales_invoices WHERE invoice_number = ?',
            variables: [Variable<String>(number)])
        .getSingle();
    return row.data['id'] as int;
  }

  test('التجهيزةُ تبدأ بلا العمود وإلّا لا تقيس شيئاً', () async {
    expect(await invoiceColumns(), isNot(contains('paid_unallocated')));
  });

  test('🔴 الترقيةُ تُضيف العمودَ **وتملؤه من المسدَّد**', () async {
    final partial = await seedInvoice(number: 'OLD-1', total: 1000, paid: 300);
    final settled = await seedInvoice(number: 'OLD-2', total: 500, paid: 500);
    final untouched = await seedInvoice(number: 'OLD-3', total: 200, paid: 0);

    await db.runOnUpgrade(Migrator(db), 174, 175);

    expect(await invoiceColumns(), contains('paid_unallocated'));
    expect(await baseOf(partial), 300,
        reason: '🔴 قاعدةُ صفرٍ على فاتورةٍ قديمة: أوّلُ تخصيصٍ يمحو '
            'الثلاثَمئة من الدفتر ومن رصيد العميل معاً');
    expect(await baseOf(settled), 500,
        reason: '🔴 وفاتورةٌ مسدَّدةٌ بالكامل تعود «غيرَ مسدَّدة»');
    expect(await baseOf(untouched), 0,
        reason: 'فاتورةٌ لم يُدفَع منها شيءٌ قاعدتُها صفرٌ حقّاً');
  });

  test('وإعادةُ تشغيل الترقية بلا أثرٍ ثانٍ', () async {
    final id = await seedInvoice(number: 'OLD-4', total: 1000, paid: 300);
    await db.runOnUpgrade(Migrator(db), 174, 175);
    // ⚠️ الترقيةُ تُعاد على قواعدَ نصفِ مُرقّاة (سقوطُ تطبيقٍ في منتصفها)،
    //    وملءٌ يُضاعف كان سيرفع القاعدةَ فوق المسدَّد.
    await db.runOnUpgrade(Migrator(db), 174, 175);
    expect(await baseOf(id), 300);
  });
}
