// 🔴 **إعادةُ حسابِ المسدَّد كانت تمحو ما دُفع عند البيع.**
//
// ═══ العطب ═══
//
// `PaymentAllocationSyncStrategy` كانت تكتب:
//
//     paid = SUM(payment_allocations)     ← تستبدل ولا تجمع
//
// وهي **نائمةٌ** ما دام صفرُ كُتّابٍ لجدول التخصيصات في `lib/` — وهو حالُ
// المستودع قبل هذه الدفعة (مقيسٌ: `into(paymentAllocations)` لا يظهر إلّا
// في الاستراتيجيّة نفسِها).
//
// لكنّ `paid` يُكتَب **وقتَ البيع** من الدفعة الحاضرة: فاتورةٌ بألفٍ دُفع
// منها ٣٠٠ نقداً وبقي ٧٠٠ آجلاً **لا تحمل أيَّ تخصيص**. فأوّلُ سندِ قبضٍ
// يخصّص لها ٧٠٠ كان يجعل `paid = ٧٠٠` بدل ١٠٠٠:
//
//   • تختفي الثلاثُمئة من دفتر المبيعات
//   • ويتضخّم رصيدُ العملاء بقدرها
//   • وتعود الفاتورةُ «جزئيّةً» وهي مسدَّدة
//
// ولا شيءَ يُبلِّغ: الصفُّ صحيحٌ، والمجموعُ صحيحٌ، والمعادلةُ هي الخطأ.
//
// ═══ والعلاجُ قاعدةٌ مخزَّنة (قرارُ المالك 2026-09-19، الخيار أ) ═══
//
//     paid = paid_unallocated + Σ payment_allocations
//
// و`paid_unallocated` عمودُ v175، يُملأ بالهجرة من `paid` القائم — وذلك
// صحيحٌ حرفيّاً لأنّ التخصيصات كانت صفراً.

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/services/sync/strategies/payment_allocation_sync_strategy.dart';
import 'package:ural_erp/services/sync/strategies/sales_sync_strategy.dart';

void main() {
  late AppDatabase db;
  late int customerId;
  late int warehouseId;
  late int userId;
  late int safeId;

  Future<SalesInvoiceData> invoice(int id) =>
      (db.select(db.salesInvoices)..where((i) => i.id.equals(id))).getSingle();

  /// فاتورةُ آجلٍ بإجماليِّ [total] دُفع منها [paid] عند البيع.
  Future<int> makeInvoice({double total = 1000, double paid = 300}) =>
      db.createSalesInvoice(
        customerId: customerId,
        warehouseId: warehouseId,
        userId: userId,
        subtotal: total,
        discount: 0,
        tax: 0,
        total: total,
        paid: paid,
        paymentMethod: 'credit',
        items: const [],
      );

  setUp(() async {
    db = AppDatabase.forTesting();
    await db.syncDefaultAccounts();
    await db.into(db.fiscalYears).insert(
          FiscalYearsCompanion.insert(
            name: '2026',
            startDate: DateTime(2026, 1, 1),
            endDate: DateTime(2026, 12, 31),
          ),
        );
    warehouseId = await db.into(db.warehouses).insert(
          WarehousesCompanion.insert(name: 'الرئيسي'),
        );
    userId = await db.into(db.users).insert(
          UsersCompanion.insert(
            username: 'tester',
            passwordHash: '',
            passwordSalt: const Value(''),
            displayName: 'مُدخِل',
          ),
        );
    customerId = await db.into(db.parties).insert(
          PartiesCompanion.insert(name: 'شركة النور'),
        );
    safeId = await db.into(db.safes).insert(
          SafesCompanion.insert(name: 'الصندوق الرئيسي'),
        );
  });

  tearDown(() async {
    // ⚠️ لا `db.close()` — راجع وصفةَ اختبارات الودجت؛ والإغلاقُ هنا يترك
    //    مؤقّتَ drift معلَّقاً في بعض السوايا.
  });

  group('🔴 القاعدةُ تُملأ عند الميلاد', () {
    test('فاتورةٌ تُنشأ بمسدَّدٍ ٣٠٠ ⇒ القاعدةُ ٣٠٠', () async {
      final id = await makeInvoice();
      final inv = await invoice(id);
      expect(inv.paid, 300);
      expect(inv.paidUnallocated, 300,
          reason: '🔴 قاعدةٌ صفرٌ تقول «كلُّ ما دُفع كان تخصيصاً» — وأوّلُ '
              'إعادةِ حسابٍ تمحو الثلاثَمئة');
    });
  });

  group('🔴 التخصيصُ يرفع المسدَّدَ ولا يمسّ القاعدة', () {
    test('٧٠٠ تُخصَّص ⇒ المسدَّدُ ١٠٠٠ والقاعدةُ ٣٠٠', () async {
      final id = await makeInvoice();
      await db.recordVoucherAllocations(
        paymentNumber: 'REC-1',
        paymentDate: DateTime(2026, 9, 20),
        amount: 700,
        paymentMethod: 'cash',
        safeId: safeId,
        paymentType: 'receipt',
        partyId: customerId,
        allocations: [(invoiceType: 'sales', invoiceId: id, amount: 700)],
      );
      final inv = await invoice(id);
      expect(inv.paid, 1000);
      expect(inv.paidUnallocated, 300,
          reason: '🔴 التخصيصُ لو خفّض القاعدةَ لألغى أثرَ نفسِه عند إعادة '
              'الحساب');
      expect(inv.status, 'paid');
    });

    test('🔴 وإعادةُ الحساب لا تمحو ما دُفع عند البيع', () async {
      final id = await makeInvoice();
      final paymentId = await db.recordVoucherAllocations(
        paymentNumber: 'REC-2',
        paymentDate: DateTime(2026, 9, 20),
        amount: 700,
        paymentMethod: 'cash',
        safeId: safeId,
        paymentType: 'receipt',
        partyId: customerId,
        allocations: [(invoiceType: 'sales', invoiceId: id, amount: 700)],
      );
      final allocation = await (db.select(db.paymentAllocations)
            ..where((a) => a.paymentId.equals(paymentId)))
          .getSingle();

      // ‏المسارُ الحقيقيُّ: صفُّ التخصيص يعود من الخادم فتُعاد الحسبة.
      await PaymentAllocationSyncStrategy(db).syncFromJson({
        'payment_allocations': [
          {
            'id': allocation.id,
            'paymentId': paymentId,
            'invoiceType': 'sales',
            'invoiceId': id,
            'allocatedAmount': 700,
          },
        ],
      });

      final inv = await invoice(id);
      expect(inv.paid, 1000,
          reason: '🔴 `paid = Σ allocations` تجعلها ٧٠٠: تختفي الثلاثُمئة '
              'من الدفتر ويتضخّم رصيدُ العميل، وتعود الفاتورةُ «جزئيّةً» '
              'وهي مسدَّدة');
      expect(inv.paidUnallocated, 300);
    });

    test('وإلغاءُ التخصيص من الخادم يُرجع المسدَّدَ إلى قاعدته', () async {
      final id = await makeInvoice();
      final paymentId = await db.recordVoucherAllocations(
        paymentNumber: 'REC-3',
        paymentDate: DateTime(2026, 9, 20),
        amount: 700,
        paymentMethod: 'cash',
        safeId: safeId,
        paymentType: 'receipt',
        partyId: customerId,
        allocations: [(invoiceType: 'sales', invoiceId: id, amount: 700)],
      );
      final allocation = await (db.select(db.paymentAllocations)
            ..where((a) => a.paymentId.equals(paymentId)))
          .getSingle();

      // الخادمُ يُصفِّر التخصيصَ (إشعارُ خصمٍ مثلاً) — `serverWins`.
      await PaymentAllocationSyncStrategy(db).syncFromJson({
        'payment_allocations': [
          {
            'id': allocation.id,
            'paymentId': paymentId,
            'invoiceType': 'sales',
            'invoiceId': id,
            'allocatedAmount': 0,
          },
        ],
      });

      final inv = await invoice(id);
      expect(inv.paid, 300,
          reason: 'القاعدةُ تبقى والتخصيصُ وحدَه يُرفَع');
      expect(inv.paidUnallocated, 300);
    });
  });

  group('🔴 وتحصيلٌ بعد التخصيص يرفع القاعدةَ معه', () {
    // 🔴 **المشهدُ الذي نجت منه أوّلُ صياغةٍ لهذا الملفّ.** طفرةُ «الضابطُ
    //    يكفّ عن كتابة القاعدة» مرّت خضراءَ لأنّ الفحوصَ كلَّها كانت تقيس
    //    تخصيصاً **وحدَه**. والثابتُ يُكسَر في الاتّجاه الآخر: مبلغٌ يُسجَّل
    //    على فاتورةٍ **لها تخصيصٌ سلفاً** وبلا تخصيصٍ جديد.
    test('🔴 تحصيلٌ بلا تخصيصٍ بعد تخصيصٍ قائمٍ لا يُمحى', () async {
      final id = await makeInvoice(); // ١٠٠٠ إجماليّاً · ٣٠٠ قاعدةً
      final paymentId = await db.recordVoucherAllocations(
        paymentNumber: 'REC-9',
        paymentDate: DateTime(2026, 9, 20),
        amount: 400,
        paymentMethod: 'cash',
        safeId: safeId,
        paymentType: 'receipt',
        partyId: customerId,
        allocations: [(invoiceType: 'sales', invoiceId: id, amount: 400)],
      );
      expect((await invoice(id)).paid, 700);

      // تحصيلُ الباقي **بلا تخصيص** — مسارُ `recordPayment` الخفيف.
      await db.updateSalesInvoicePaidAmount(id, 1000);
      final afterCollect = await invoice(id);
      expect(afterCollect.paid, 1000);
      expect(afterCollect.paidUnallocated, 600,
          reason: '🔴 القاعدةُ لو بقيت ٣٠٠ لعاد المسدَّدُ ٧٠٠ عند أوّل '
              'إعادةِ حساب — وتختفي الثلاثُمئة الأخيرة');

      final allocation = await (db.select(db.paymentAllocations)
            ..where((a) => a.paymentId.equals(paymentId)))
          .getSingle();
      await PaymentAllocationSyncStrategy(db).syncFromJson({
        'payment_allocations': [
          {
            'id': allocation.id,
            'paymentId': paymentId,
            'invoiceType': 'sales',
            'invoiceId': id,
            'allocatedAmount': 400,
          },
        ],
      });

      expect((await invoice(id)).paid, 1000,
          reason: '🔴 عينُ العطب من الجهة الأخرى: تحصيلٌ لاحقٌ يُمحى بإعادة '
              'حسابٍ لا تعرف إلّا التخصيصات');
    });
  });

  group('🔴 وفاتورةٌ تصل بالمزامنة تحمل قاعدتَها', () {
    // 🔴 **البابُ الآخر لنفس العطب.** `SalesSyncStrategy` تكتب `paid`
    //    ولا تكتب القاعدة، فصفٌّ يصل من الخادم يهبط بقاعدةِ صفر — وأوّلُ
    //    تخصيصٍ يُصفّر مسدَّدَه.
    test('خادمٌ لا يرسل المفتاح ⇒ القاعدةُ هي المسدَّد', () async {
      await SalesSyncStrategy(db).syncFromJson({
        'sales': [
          {
            'id': 9001,
            'invoiceNumber': 'SRV-9001',
            'warehouseId': warehouseId,
            'userId': userId,
            'customerId': customerId,
            'invoiceDate': DateTime(2026, 9, 1).toIso8601String(),
            'subtotal': 1000,
            'discount': 0,
            'tax': 0,
            'total': 1000,
            'paid': 300,
            'paymentMethod': 'credit',
            'status': 'partial',
          },
        ],
      });

      final inv = await (db.select(db.salesInvoices)
            ..where((i) => i.invoiceNumber.equals('SRV-9001')))
          .getSingle();
      expect(inv.paid, 300);
      expect(inv.paidUnallocated, 300,
          reason: '🔴 قاعدةُ صفرٍ تُصفّر مسدَّدَ كلِّ فاتورةٍ وصلت '
              'بالمزامنة عند أوّل تخصيص');
    });
  });

  group('🔴 ولا حركةَ مالٍ ثانية', () {
    test('التوزيعُ لا يحرّك خزنةً ولا يكتب قيداً', () async {
      final id = await makeInvoice();
      final safeBefore =
          (await (db.select(db.safes)..where((s) => s.id.equals(safeId)))
                  .getSingle())
              .balance;
      final entriesBefore = (await db.select(db.journalEntries).get()).length;
      final partyBefore =
          (await (db.select(db.parties)..where((p) => p.id.equals(customerId)))
                  .getSingle())
              .balance;

      await db.recordVoucherAllocations(
        paymentNumber: 'REC-4',
        paymentDate: DateTime(2026, 9, 20),
        amount: 700,
        paymentMethod: 'cash',
        safeId: safeId,
        paymentType: 'receipt',
        partyId: customerId,
        allocations: [(invoiceType: 'sales', invoiceId: id, amount: 700)],
      );

      expect(
          (await (db.select(db.safes)..where((s) => s.id.equals(safeId)))
                  .getSingle())
              .balance,
          safeBefore,
          reason: '🔴 السندُ حرّك الخزنةَ سلفاً — وحركةٌ ثانيةٌ تضاعف '
              'النقديّة');
      expect((await db.select(db.journalEntries).get()).length, entriesBefore,
          reason: '🔴 قيدٌ ثانٍ **متّزنٌ** على نفس المبلغ لا يمسكه فحصُ '
              'اتّزان');
      expect(
          (await (db.select(db.parties)..where((p) => p.id.equals(customerId)))
                  .getSingle())
              .balance,
          partyBefore,
          reason: '🔴 رصيدُ العميل قُيِّد بالسند — وقيدٌ ثانٍ يُنقصه مرّتين');
    });
  });

  group('والحدودُ تُرفَض بسببٍ ظاهر', () {
    test('🔴 مجموعُ التوزيع لا يتجاوز مبلغَ السند', () async {
      final a = await makeInvoice();
      final b = await makeInvoice();
      expect(
        () => db.recordVoucherAllocations(
          paymentNumber: 'REC-5',
          paymentDate: DateTime(2026, 9, 20),
          amount: 700,
          paymentMethod: 'cash',
          safeId: safeId,
          paymentType: 'receipt',
          allocations: [
            (invoiceType: 'sales', invoiceId: a, amount: 400),
            (invoiceType: 'sales', invoiceId: b, amount: 400),
          ],
        ),
        throwsA(isA<StateError>()),
        reason: '🔴 توزيعٌ أكبرُ من المقبوض يُقفل فواتيرَ بمالٍ لم يُقبَض',
      );
    });

    test('🔴 والتخصيصُ لا يتجاوز باقيَ الفاتورة', () async {
      final id = await makeInvoice();
      expect(
        () => db.recordVoucherAllocations(
          paymentNumber: 'REC-6',
          paymentDate: DateTime(2026, 9, 20),
          amount: 900,
          paymentMethod: 'cash',
          safeId: safeId,
          paymentType: 'receipt',
          allocations: [(invoiceType: 'sales', invoiceId: id, amount: 900)],
        ),
        throwsA(isA<StateError>()),
        reason: '🔴 فاتورةٌ «مدفوعةٌ أكثرَ من قيمتها» تُقرأ رصيداً دائناً '
            'في تقريرٍ وخطأَ إدخالٍ في آخر',
      );
    });

    test('وصفرٌ أو سالبٌ يُرفَض', () async {
      final id = await makeInvoice();
      expect(
        () => db.recordVoucherAllocations(
          paymentNumber: 'REC-7',
          paymentDate: DateTime(2026, 9, 20),
          amount: 700,
          paymentMethod: 'cash',
          safeId: safeId,
          paymentType: 'receipt',
          allocations: [(invoiceType: 'sales', invoiceId: id, amount: 0)],
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('ولا تُكتَب الدفعةُ حين يسقط أحدُ تخصيصاتها', () async {
      final id = await makeInvoice();
      try {
        await db.recordVoucherAllocations(
          paymentNumber: 'REC-8',
          paymentDate: DateTime(2026, 9, 20),
          amount: 900,
          paymentMethod: 'cash',
          safeId: safeId,
          paymentType: 'receipt',
          allocations: [(invoiceType: 'sales', invoiceId: id, amount: 900)],
        );
      } catch (_) {}
      expect(await db.select(db.payments).get(), isEmpty,
          reason: 'دفعةٌ بلا تخصيصاتها تُظهر مالاً موزَّعاً لا يقابله شيء — '
              'والمعاملةُ تتراجع كاملةً');
      expect((await invoice(id)).paid, 300);
    });
  });
}
