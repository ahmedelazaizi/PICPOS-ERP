// ═══════════════════════════════════════════════════════════════════════════
// PicPos — بيعة بلا وردية بتتحوّل «فائض نقدية» عند الإقفال (إعادة إنتاج)
// ═══════════════════════════════════════════════════════════════════════════
//
// ⚠️ الاختبار الأساسي هنا **أحمر عن قصد**؛ الضابط أخضر.
//
// ── إزاي بيحصل ────────────────────────────────────────────────────────────
// `picpos_pos_operations.dart:104` بيتخطّى `_ensureShiftOpen` لمدير النظام
// عن قصد (Spec 135 NOTE 2) — المدير المفروض «يلتحق» بوردية الكاشير عشان
// يقفلها. بس الشاشة **بتفضل تِلّاً كاملاً**: المدير يقدر يبيع، وبيعته بتكتب
// إيصال خزنة بـ`user_id = admin`.
//
// وقت الإقفال:
//   • `treasury_dao._settleShift` بيحسب `expectedCash` من `safe_transactions`
//     **المفلترة بـ`shift.userId`** — فبيعة المدير مش داخلة.
//   • `getShiftClosingAggregates(includeAllUsers: false)` بيفلتر
//     `sales_invoices.user_id` كمان — فالديالوج كمان مش شايفها.
//   • لكن **الدرج** فيه الفلوس فعلاً (الخزنة اتقيّدت).
//
// فالكاشير بيعدّ الدرج بأمانة، والفرق بيتقيّد قيد **فائض نقدية**: مدين نقدية
// / دائن إيراد فائض. والمبلغ ده كان **اتقيّد قبل كده** بقيد البيعة نفسها
// (مدين نقدية / دائن مبيعات). النتيجة: حساب النقدية في الأستاذ اتقيّد مرتين،
// وإيراد وهمي بحجم البيعة.
//
// المقاس: بيعة مدير ٢٠٠ + بيعة كاشير ٥٠ ⇒ الدرج ٢٥٠، الوردية متوقّعة ٥٠،
// فرق +٢٠٠ ⇒ قيد فائض ٢٠٠. حساب النقدية بقى ٤٠٠ والخزنة ٢٠٠.
//
// ── الصح ──────────────────────────────────────────────────────────────────
// إما إن التِل يرفض بيعة بلا وردية مفتوحة، أو إن تسوية الوردية تتحسب على
// **نافذة الوردية + الخزنة**، مش على `user_id`. أياً كان القرار، المطلوب إن
// فرق الإقفال ما يبقاش بحجم بيعة اتسجّلت أصلاً.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    for (final ch in const [
      'xyz.luan/audioplayers.global',
      'plugins.flutter.io/path_provider',
    ]) {
      binding.defaultBinaryMessenger
          .setMockMethodCallHandler(MethodChannel(ch), (call) async => null);
    }
  });

  late AppDatabase db;
  late int warehouseId;
  late int cashierId;
  late int productId;
  const adminId = 1; // مدير النظام المزروع

  setUp(() async {
    db = AppDatabase.forTesting();
    warehouseId = (await db.getDefaultWarehouse())!.id;
    final roleId = await db.into(db.roles).insert(
          RolesCompanion.insert(name: 'كاشير', isSystemRole: const Value(false)),
        );
    cashierId = await db.createUser(
      username: 'cashier1',
      password: 'pw',
      displayName: 'كاشير',
      roleId: roleId,
    );
    productId = await db.insertProduct(
      ProductsCompanion.insert(
        code: 'S1',
        name: 'صنف',
        salePrice: const Value(10),
        costPrice: const Value(6),
        trackInventory: const Value(true),
      ),
    );
    await db.adjustStock(
      productId: productId,
      warehouseId: warehouseId,
      quantity: 500,
      type: 'initial',
    );
  });

  tearDown(() => db.close());

  Future<void> cashSale({
    required int userId,
    required double amount,
    required int cashSafeId,
  }) async {
    await db.createSalesInvoice(
      warehouseId: warehouseId,
      userId: userId,
      subtotal: amount,
      discount: 0,
      tax: 0,
      total: amount,
      paid: amount,
      paymentMethod: 'cash',
      cashAmount: amount,
      cashSafeId: cashSafeId,
      items: [
        SalesInvoiceItemsCompanion.insert(
          invoiceId: 0,
          productId: productId,
          quantity: amount / 10,
          unitPrice: 10,
          total: amount,
        ),
      ],
    );
  }

  /// مجموع الحركة المدينة الصافية على حساب النقدية في كل القيود.
  Future<double> cashAccountNetDebit() async {
    final cashAcc = await db.getAccountByCode(
      await db.getMappedAccountCode('cash', AccountingDao.accountPurposes['cash']!),
    );
    if (cashAcc == null) return 0;
    final lines = await (db.select(db.journalEntryLines)
          ..where((l) => l.accountId.equals(cashAcc.id)))
        .get();
    return lines.fold<double>(0, (s, l) => s + l.debit - l.credit);
  }

  test('ضابط: وردية كاشير لوحدها بتقفل بفرق صفر', () async {
    final cashSafe = (await db.getDefaultSafeByType('cash'))!;
    final shiftId = await db.openShift(cashierId, 0);
    await cashSale(userId: cashierId, amount: 50, cashSafeId: cashSafe.id);

    final drawer = (await db.getDefaultSafeByType('cash'))!.balance;
    expect(drawer, 50, reason: 'تجهيزة: الخزنة اتقيّدت بالبيعة');

    await db.closeShiftWithAudit(shiftId, drawer);
    final closed =
        await (db.select(db.shifts)..where((s) => s.id.equals(shiftId)))
            .getSingle();
    expect(closed.expectedCash, 50);
    expect(closed.variance, 0);
    expect(await cashAccountNetDebit(), 50,
        reason: 'حساب النقدية في الأستاذ = البيعة، مرة واحدة');
  });

  test('بيعة مدير على نفس التِل ما تتحوّلش فائض عند إقفال وردية الكاشير',
      () async {
    final cashSafe = (await db.getDefaultSafeByType('cash'))!;
    final shiftId = await db.openShift(cashierId, 0);

    // المدير بيبيع من نفس الشاشة — بلا وردية، لأن الفورك بيتخطّاها له.
    await cashSale(userId: adminId, amount: 200, cashSafeId: cashSafe.id);
    // الكاشير بيبيع في ورديته.
    await cashSale(userId: cashierId, amount: 50, cashSafeId: cashSafe.id);

    final drawer = (await db.getDefaultSafeByType('cash'))!.balance;
    expect(drawer, 250, reason: 'تجهيزة: الدرج فيه البيعتين');

    // الكاشير بيعدّ الدرج زي ما هو — ٢٥٠ فعلاً موجودين.
    await db.closeShiftWithAudit(shiftId, drawer);
    final closed =
        await (db.select(db.shifts)..where((s) => s.id.equals(shiftId)))
            .getSingle();

    expect(
      closed.variance,
      0,
      reason: 'اتقاس +٢٠٠ — الفرق بالظبط بحجم بيعة المدير. الوردية بتحاسب '
          'الكاشير على فلوس مسجّلة أصلاً في النظام '
          '(treasury_dao.dart:_settleShift بيفلتر safe_transactions بـ'
          'shift.userId).',
    );

    expect(
      await cashAccountNetDebit(),
      250,
      reason: 'اتقاس ٤٥٠ — قيد «فائض نقدية» ضاف ٢٠٠ تانية على حساب النقدية '
          'فوق قيد البيعة، وقيّد ٢٠٠ إيراد فائض وهمي.',
    );

    final varianceJes = await (db.select(db.journalEntries)
          ..where((j) => j.referenceType.equals('shift_close')))
        .get();
    expect(varianceJes, isEmpty,
        reason: 'مفيش فرق حقيقي، فما ينفعش يتقيّد قيد فرق أصلاً.');
  });
}
