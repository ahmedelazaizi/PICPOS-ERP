// عدّاداتُ حالةِ الفواتير في تجميع `getSalesInvoiceSummary`.
//
// شرائحُ الحالة في شريط الترشيح تعرض عدّاداً بجانب كلّ حالة. ومصدرُه لا بدّ
// أن يكون تجميعَ SQL على **كلّ** المطابق: العدُّ من القائمة المحمَّلة يتوقّف
// عند سقف الصفحة (٥٠٠ صفّ) فيعطي رقماً أقلَّ من الحقيقة بلا ما يشي بذلك —
// وهو أسوأُ من غياب العدّاد، لأنه يبدو دقيقاً.
//
// ويُقاس هنا شيئان لا واحد:
//  ١) **التقسيمُ لا يتداخل ولا يُسقط**: مجموعُ الثلاثة = العدُّ الكلّيّ.
//     حدودٌ متداخلةٌ كانت ستَعُدَّ فاتورةً مرّتين فيتجاوز المجموعُ الكلَّ.
//  ٢) **الدفعةُ الزائدة مدفوعةٌ لا جزئيّة**: `paid == total` بالمساواة
//     الصارمة كان يُسقط فاتورةً حُصِّلت بقروشٍ زائدةٍ (تقريبُ ضريبةٍ أو
//     تحصيلٌ مدوَّر) إلى «غير مدفوع» — وهي مدفوعةٌ بالكامل عمليّاً.
import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.forTesting();
  });

  // ⚠️ لا `db.close()` في tearDown — يعلّق مؤقّتَ drift في المنطقة الوهميّة
  // فيتجمّد الاختبار (درسٌ موثَّقٌ في المستودع).
  tearDown(() async {});

  final day = DateTime(2026, 8, 10);

  Future<void> seed({required double total, required double paid}) async {
    await db.into(db.salesInvoices).insert(
          SalesInvoicesCompanion.insert(
            invoiceNumber: 'INV-${total.toInt()}-${paid.toInt()}-'
                '${DateTime(2026).microsecondsSinceEpoch % 100000}'
                '${paid.hashCode}',
            invoiceDate: day,
            total: Value(total),
            paid: Value(paid),
            warehouseId: 1,
            userId: 1,
          ),
        );
  }

  Future<SalesInvoiceSummary> summarize() => db.getSalesInvoiceSummary(
        from: DateTime(2026, 8, 1),
        to: DateTime(2026, 8, 31),
      );

  test('التقسيمُ الثلاثيُّ لا يتداخل ولا يُسقط صفّاً', () async {
    await seed(total: 100, paid: 100); // مدفوع
    await seed(total: 100, paid: 40); // جزئي
    await seed(total: 100, paid: 0); // غير مدفوع

    final s = await summarize();

    expect(s.paidCount, 1);
    expect(s.partialCount, 1);
    expect(s.unpaidCount, 1);
    expect(s.paidCount + s.partialCount + s.unpaidCount, s.invoiceCount,
        reason: 'مجموعُ الحالات لا بدّ أن يساوي العدَّ الكلّيَّ بالضبط — '
            'التداخلُ يعُدُّ صفّاً مرّتين، والفجوةُ تُخفيه من الثلاثة');
  });

  test('دفعةٌ زائدةٌ بقروش ⇒ «مدفوع» لا «غير مدفوع»', () async {
    // ‏١٠٠٫٠٠١ عن ١٠٠: تقريبُ ضريبةٍ نموذجيّ. بالمساواة الصارمة كانت تسقط
    // خارجَ «مدفوع» ثمّ تقع في «غير مدفوع» لأن شرطَه كان المتمِّم.
    await seed(total: 100, paid: 100.001);

    final s = await summarize();

    expect(s.paidCount, 1);
    expect(s.unpaidCount, 0,
        reason: 'فاتورةٌ حُصِّلت بالكامل وزيادةً ليست «غير مدفوعة»');
    expect(s.partialCount, 0);
  });

  test('لا فواتيرَ ⇒ أصفارٌ لا أخطاء', () async {
    final s = await summarize();
    expect(s.invoiceCount, 0);
    expect(s.paidCount, 0);
    expect(s.partialCount, 0);
    expect(s.unpaidCount, 0);
  });
}
