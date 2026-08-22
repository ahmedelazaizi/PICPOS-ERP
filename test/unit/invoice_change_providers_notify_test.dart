// إشاراتُ تغيُّرِ الفواتير — هل توقظ المستمعَ مع **كلّ** تغيير؟
//
// ── بلاغُ المالك (2026-08-23) ─────────────────────────────────────────────
// «جدولُ الفواتير لا يتحدّث بعد الحفظ» — الصفُّ لا يظهر حتى يُحدِّث المستخدمُ
// الشاشةَ بيده.
//
// ── والسببُ المقيس ────────────────────────────────────────────────────────
// كانت الإشارةُ `StreamProvider<void>` نهايتُها `.map((_) {})`، فكلُّ بثٍّ
// يحمل **نفسَ القيمة**. وRiverpod لا يُخطر إلّا حين تتبدّل الحالةُ بالمساواة،
// و`AsyncData<void>(null) == AsyncData<void>(null)`. فالبثُّ الأوّلُ يوقظ
// المستمعَ وما بعده يُبتلَع صامتاً.
//
// وهذا يفسّر ما بدا متناقضاً في السجلّ: بيعُ نقطةِ البيع كان يظهر فوراً لأنّ
// `checkout_controller` يُبطل المزوِّدَ صراحةً (‏`ref.invalidate`) فتمرّ
// الحالةُ بـ`AsyncLoading` — وهو تبدّلٌ حقيقيّ. أمّا الحفظُ من شاشة «فاتورة
// جديدة» فلا يُبطل شيئاً، فلا يستيقظ أحد.
//
// ⚠️ ولهذا لا يكفي أن تُقاس «الإشارةُ تُبثّ»: لا بدّ من قياسِ **الإيقاظ**
//    نفسِه، وعلى بثٍّ متكرّرٍ لا واحد. الاختبارُ على إدراجٍ واحدٍ كان يمرّ
//    والعطبُ قائم.
import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/providers/providers.dart';

void main() {
  late AppDatabase db;
  late ProviderContainer container;

  setUp(() {
    db = AppDatabase.forTesting();
    container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  test('كلُّ فاتورةِ مبيعاتٍ تُدرَج توقظ المستمع — لا الأولى وحدَها', () async {
    var fires = 0;
    container.listen(salesInvoicesChangeProvider, (_, _) => fires++,
        fireImmediately: false);
    await pumpEventQueue();
    final baseline = fires;

    for (var i = 0; i < 3; i++) {
      await db.into(db.salesInvoices).insert(
            SalesInvoicesCompanion.insert(
              invoiceNumber: 'SINV-$i',
              warehouseId: 1,
              userId: 1,
              invoiceDate: DateTime(2026, 8, 23),
              total: const Value(100),
            ),
          );
      await pumpEventQueue();
    }

    expect(fires - baseline, 3,
        reason: 'ثلاثُ إدراجاتٍ = ثلاثُ إيقاظات. وواحدٌ يعني أنّ المساواةَ '
            'ابتلعت البقيّةَ — وهو بالضبط «الجدولُ لا يتحدّث بعد الحفظ»');
  });

  test('كلُّ فاتورةِ مشترياتٍ تُدرَج توقظ المستمع', () async {
    var fires = 0;
    container.listen(purchaseInvoicesChangeProvider, (_, _) => fires++,
        fireImmediately: false);
    await pumpEventQueue();
    final baseline = fires;

    for (var i = 0; i < 3; i++) {
      await db.into(db.purchaseInvoices).insert(
            PurchaseInvoicesCompanion.insert(
              invoiceNumber: 'PINV-$i',
              supplierId: 1,
              warehouseId: 1,
              invoiceDate: DateTime(2026, 8, 23),
              total: const Value(100),
            ),
          );
      await pumpEventQueue();
    }

    expect(fires - baseline, 3);
  });
}
