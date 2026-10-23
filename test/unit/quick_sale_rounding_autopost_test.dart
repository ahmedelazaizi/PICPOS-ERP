// ═══════════════════════════════════════════════════════════════════════════
// تقريبُ الإجماليّ — الأثرُ المحاسبيُّ على مسار الترحيل الحقيقيّ
// ═══════════════════════════════════════════════════════════════════════════
//
// ⚠️ **قياسُ أثرٍ لا قراءةُ كود.** كلُّ اختبارٍ هنا يمرّ بـ
// `db.createSalesInvoice` ⇒ `autoPostCashSale` بقاعدةٍ حقيقيّةٍ في الذاكرة،
// ثمّ يقرأ **سطورَ القيد** من الأستاذ. الشاشةُ لا تدخل الحسبة.
//
// والنموذجُ المُثبَت: الفاتورةُ تبقى بإجماليها الحقيقيّ، والمقبوضُ وحدَه
// يُقرَّب، والفرقُ سطرٌ صريحٌ على `4319 فروق تقريب`:
//
//   Dr 111-000NN نقديةُ الدرج   114.05
//   Dr 4319 فروق تقريب          0.02
//      Cr 4121 مبيعات                   100.06   ← الإيرادُ سليم
//      Cr 2121 ض.ق.م محصلة               14.01   ← الوعاءُ سليم
//
// الأشكالُ الثلاثةُ البديلةُ كلُّها معطوبةٌ ومقيسة (‏تدقيقٌ محاسبيّ 2026-08-30):
// المقبوضُ صعوداً بلا سطرٍ مقابل ⇒ القيدُ يُرمى؛ وهبوطاً ⇒ ذمّةٌ وهميّة؛
// وتقريبُ `total` نفسِه ⇒ يتّزن ويكذب لأنّ الأطرافَ تُشتقّ منه.

import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';

void main() {
  late AppDatabase db;
  late int userId;
  late int warehouseId;
  late int productId;

  setUp(() async {
    db = AppDatabase.forTesting();

    final roleId = await db.into(db.roles).insert(
          RolesCompanion.insert(name: 'كاشير', isSystemRole: const Value(false)),
        );
    userId = await db.createUser(
      username: 'rounding_user',
      password: 'test',
      displayName: 'Rounding User',
      roleId: roleId,
    );

    final wh = await db.getDefaultWarehouse();
    warehouseId = wh!.id;

    productId = await db.insertProduct(
      ProductsCompanion.insert(
        code: 'ROUND-1',
        name: 'صنفُ اختبارِ التقريب',
        salePrice: const Value(100.07),
        costPrice: const Value(10.0),
        currentStock: const Value(1000.0),
        trackInventory: const Value(true),
      ),
    );
    await db.adjustStock(
      productId: productId,
      warehouseId: warehouseId,
      quantity: 1000.0,
      type: 'in',
      notes: 'seed',
    );
  });

  tearDown(() async => db.close());

  Future<List<JournalEntryLine>> saleLines(int invoiceId) async {
    final entry = await (db.select(db.journalEntries)
          ..where((e) =>
              e.referenceType.equals('sale') & e.referenceId.equals(invoiceId)))
        .getSingle();
    return (db.select(db.journalEntryLines)
          ..where((l) => l.entryId.equals(entry.id)))
        .get();
  }

  Future<double> netOn(List<JournalEntryLine> lines, String code) async {
    final acc = await db.getAccountByCode(code);
    if (acc == null) return 0;
    return lines
        .where((l) => l.accountId == acc.id)
        .fold<double>(0, (s, l) => s + l.debit - l.credit);
  }

  /// صافي النقدية على **شجرة `111` كلِّها** لا على `1111` وحدَه.
  ///
  /// ⚠️ كلُّ خزنةٍ تُمنَح حساباً فرعيّاً `111-000NN` عند الإقلاع
  /// (`linkUnlinkedSafesToSubAccountsOnce`)، و`_resolveSaleLegAccount` توجّه
  /// شقَّ النقدية إلى حساب **الخزنة التي قُبض فيها** لا إلى الغرض العامّ.
  /// فتوكيدٌ على `1111` يقرأ صفراً ويبدو عطباً وهو سلوكٌ صحيح.
  Future<double> cashNet(List<JournalEntryLine> lines) async {
    final accounts = await db.select(db.accounts).get();
    final cashIds = accounts
        .where((a) => a.code == '111' || a.code.startsWith('111'))
        .map((a) => a.id)
        .toSet();
    return lines
        .where((l) => cashIds.contains(l.accountId))
        .fold<double>(0, (s, l) => s + l.debit - l.credit);
  }

  Future<int> createSale({
    required String number,
    required double total,
    required double tax,
    required double paid,
    required double roundingAdjustment,
  }) =>
      db.createSalesInvoice(
        invoiceNumber: number,
        warehouseId: warehouseId,
        userId: userId,
        subtotal: total - tax,
        discount: 0.0,
        tax: tax,
        total: total,
        paid: paid,
        roundingAdjustment: roundingAdjustment,
        paymentMethod: 'cash',
        items: [
          SalesInvoiceItemsCompanion.insert(
            invoiceId: 0,
            productId: productId,
            quantity: 1.0,
            unitPrice: total - tax,
            total: total - tax,
            costPrice: const Value(10.0),
          ),
        ],
      );

  group('تقريبٌ هبوطاً — قُبض أقلّ', () {
    test('القيدُ يتوازن، والفرقُ على 4319، والإيرادُ والضريبةُ سليمان',
        () async {
      final id = await createSale(
        number: 'ROUND-DOWN-1',
        total: 114.07,
        tax: 14.01,
        paid: 114.05,
        roundingAdjustment: 0.02,
      );
      final lines = await saleLines(id);

      final debits = lines.fold<double>(0, (s, l) => s + l.debit);
      final credits = lines.fold<double>(0, (s, l) => s + l.credit);
      expect(debits, closeTo(credits, 0.0001),
          reason: 'قيدٌ غيرُ متوازنٍ يُرمى ويصير dead-letter دائماً');

      // ⚠️ **الإيرادُ لا يتحرّك.** هذا ما يميّز النموذجَ الصحيحَ عن تقريبِ
      // `total`: هناك تتوازن الأطرافُ بالبناء ويُبتلَع الفرقُ في المبيعات
      // بلا سطرٍ ولا تشخيص — والميزانُ يقفل والمدقّقُ لا يجد شيئاً.
      expect(await netOn(lines, '4121'), closeTo(-100.06, 0.0001),
          reason: 'المبيعاتُ دائنةٌ بصافي الأسطر لا بالمقرَّب');
      expect(await netOn(lines, '2121'), closeTo(-14.01, 0.0001),
          reason: 'الوعاءُ الضريبيُّ لا يمسُّه التقريب');

      expect(await netOn(lines, '4319'), closeTo(0.02, 0.0001),
          reason: 'الفرقُ مدينٌ على «فروق تقريب» بسطرٍ يقرؤه المدقّق');
      expect(await cashNet(lines), closeTo(114.05, 0.0001),
          reason: 'النقديةُ بما دخل الدرجَ فعلاً');
    });

    test('لا ذمّةَ مدينةً وهميّةً، والفاتورةُ تُغلَق `completed`', () async {
      final id = await createSale(
        number: 'ROUND-DOWN-2',
        total: 114.07,
        tax: 14.01,
        paid: 114.05,
        roundingAdjustment: 0.02,
      );
      expect(await netOn(await saleLines(id), '1121'), closeTo(0, 0.0001),
          reason: 'فتاتُ التقريب كان يتراكم على حساب المراقبة لزبونٍ عابرٍ '
              'بلا حسابٍ فرعيٍّ يقابله');

      final inv = await (db.select(db.salesInvoices)
            ..where((s) => s.id.equals(id)))
          .getSingle();
      expect(inv.status, 'completed',
          reason: 'بلا طرحِ الفرق تبقى الفاتورةُ `pending` إلى الأبد');
      expect(inv.total, closeTo(114.07, 0.0001),
          reason: 'الإجماليُّ المحفوظُ هو الحقيقيُّ لا المقرَّب');
    });
  });

  group('تقريبٌ صعوداً — قُبض أكثر', () {
    test('القيدُ يتوازن والفرقُ دائنٌ على 4319', () async {
      final id = await createSale(
        number: 'ROUND-UP-1',
        total: 114.03,
        tax: 0.0,
        paid: 114.05,
        roundingAdjustment: -0.02,
      );
      final lines = await saleLines(id);

      final debits = lines.fold<double>(0, (s, l) => s + l.debit);
      final credits = lines.fold<double>(0, (s, l) => s + l.credit);
      expect(debits, closeTo(credits, 0.0001));

      expect(await netOn(lines, '4319'), closeTo(-0.02, 0.0001),
          reason: 'قُبض أكثرُ ⇒ دائن');
      expect(await cashNet(lines), closeTo(114.05, 0.0001));
      expect(await netOn(lines, '4121'), closeTo(-114.03, 0.0001),
          reason: 'الإيرادُ بالإجماليِّ الحقيقيِّ لا بالمقبوض');
    });
  });

  group('مرساةٌ — الآليّةُ هي ما تغيّر فعلاً', () {
    // ⚠️ بلا هذه المرساةِ لا يُعرَف هل الاختباراتُ أعلاه تحرس شيئاً أصلاً.
    // نفسُ الأرقامِ بـ`roundingAdjustment: 0` تُعيد **السلوكَ القديم**:
    // الفرقُ يُقرأ ديناً فتُفتَح ذمّةٌ مدينةٌ وتبقى الفاتورةُ `pending`.
    test('الفرقُ صفراً ⇒ يعود العطبُ القديم: ذمّةٌ مدينةٌ وفاتورةٌ معلّقة',
        () async {
      final id = await createSale(
        number: 'ANCHOR-1',
        total: 114.07,
        tax: 14.01,
        paid: 114.05,
        roundingAdjustment: 0,
      );
      expect(await netOn(await saleLines(id), '1121'), closeTo(0.02, 0.0001),
          reason: 'هذا بعينُه العطبُ الذي جاء العمودُ ليمنعه');

      final inv = await (db.select(db.salesInvoices)
            ..where((s) => s.id.equals(id)))
          .getSingle();
      expect(inv.status, 'pending');
    });

    test('بيعةٌ بلا تقريبٍ إطلاقاً لا يتغيّر فيها شيء', () async {
      final id = await createSale(
        number: 'ANCHOR-2',
        total: 100.0,
        tax: 0.0,
        paid: 100.0,
        roundingAdjustment: 0,
      );
      final lines = await saleLines(id);
      expect(await netOn(lines, '4319'), closeTo(0, 0.0001),
          reason: 'لا سطرَ تقريبٍ على فاتورةٍ لم تُقرَّب');
      expect(await cashNet(lines), closeTo(100.0, 0.0001));
      final inv = await (db.select(db.salesInvoices)
            ..where((s) => s.id.equals(id)))
          .getSingle();
      expect(inv.status, 'completed');
      expect(inv.roundingAdjustment, 0);
    });
  });
}
