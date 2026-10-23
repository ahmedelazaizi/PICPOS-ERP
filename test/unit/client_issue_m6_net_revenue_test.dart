// ═══════════════════════════════════════════════════════════════════════════
// متطلبات العميل 2026-07-25 · م6 · البند 1 — «صافي الإيراد: نواجه مشكلة في
// العملية الحسابية حيث أنه من الصعب على العميل معرفة آلية الحساب».
// ═══════════════════════════════════════════════════════════════════════════
//
// افتراض العميل («المردودات غير مخصومة») **خاطئ** — حساب مردودات المبيعات
// مُعرَّف `contra_revenue` ويُطرح فعلاً. سبب عدم التطابق أن الرقم **بدون
// ضريبة** بينما العميل يحسب يدوياً **شاملاً الضريبة**؛ الفارق = صافي ضريبة
// المخرجات.
//
// ومشكلة ثانية لم ينتبه لها: «خصم المشتريات المكتسب» و«فائض النقدية عند
// إقفال الوردية» حسابات إيراد، فتدخل ضمن «صافي الإيراد» — أي أن فائضاً
// نقدياً في الخزنة يرفع «صافي الإيراد» **بلا أي بيع**.
//
// الحل ليس تغيير الرقم بل **إظهار المعادلة** بمكوّناتها.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/domain/entities/accounting_entities.dart';

void main() {
  late AppDatabase db;
  final from = DateTime(2026, 7, 1);
  final to = DateTime(2026, 7, 31, 23, 59, 59);
  final d = DateTime(2026, 7, 10);

  setUp(() async {
    db = AppDatabase.forTesting();
    await db.syncDefaultAccounts();
  });

  tearDown(() async => db.close());

  Future<void> post(String desc, List<JournalLine> lines) =>
      db.createJournalEntry(
        description: desc,
        date: d,
        lines: lines,
        isAutoPosted: true,
      );

  Future<int> acc(String code) async => (await db.getAccountByCode(code))!.id;

  test('صافي الإيراد يعرض مكوّناته: مبيعات شاملة الضريبة − مردودات', () async {
    // بيع 1000 + ضريبة 160
    await post('بيع', [
      JournalLine(accountId: await acc('1111'), debit: 1160),
      JournalLine(accountId: await acc('4121'), credit: 1000),
      JournalLine(accountId: await acc('2121'), credit: 160),
    ]);
    // مرتجع 200 + ضريبة 32
    await post('مرتجع', [
      JournalLine(accountId: await acc('4211'), debit: 200),
      JournalLine(accountId: await acc('2121'), debit: 32),
      JournalLine(accountId: await acc('1111'), credit: 232),
    ]);

    final r = await db.getIncomeStatement(from, to);

    // الرقم القائم لا يتغيّر — إضافي فقط.
    expect(r['totalRevenue'], closeTo(800, 0.001),
        reason: 'صافي الإيراد بدون ضريبة = 1000 − 200 (كما كان)');

    // المكوّنات الجديدة التي تجعل المعادلة مرئية.
    expect(r['salesReturns'], closeTo(200, 0.001));
    expect(r['outputVatNet'], closeTo(128, 0.001),
        reason: 'ضريبة المخرجات صافية من عكس المرتجع: 160 − 32');
    // هذا هو الرقم الذي يحسبه العميل يدوياً: 1160 مقبوضات − 232 مرتجع = 928.
    expect(r['netRevenueInclVat'], closeTo(928, 0.001),
        reason: 'صافي الإيراد شاملاً الضريبة = 800 + 128');

    // الثابت الذي يجعل الشاشة قابلة للتدقيق يدوياً بلا استعلام إضافي.
    expect(
      r['netRevenueInclVat'] as double,
      closeTo((r['totalRevenue'] as double) + (r['outputVatNet'] as double),
          0.001),
    );
  });

  test('فائض النقدية عند إقفال الوردية لا يرفع صافي الإيراد', () async {
    await post('بيع', [
      JournalLine(accountId: await acc('1111'), debit: 1000),
      JournalLine(accountId: await acc('4121'), credit: 1000),
    ]);
    // فائض نقدي 50 — حساب إيراد، لكنه ليس بيعاً.
    await post('فائض نقدي', [
      JournalLine(accountId: await acc('1111'), debit: 50),
      JournalLine(accountId: await acc('4318'), credit: 50),
    ]);

    final r = await db.getIncomeStatement(from, to);

    expect(r['totalRevenue'], closeTo(1000, 0.001),
        reason: 'فائض الخزنة ليس إيراد مبيعات');
    expect(r['otherIncome'], closeTo(50, 0.001),
        reason: 'يُصنَّف دخلاً آخر لا مبيعات');
    // صافي الربح لا يتغيّر — الدخل الآخر يُطوى مجدداً.
    expect(r['netProfit'], closeTo(1050, 0.001),
        reason: 'إعادة التصنيف لا تمسّ صافي الربح');
  });

  test('خصم المشتريات المكتسب لا يُحتسب ضمن المبيعات', () async {
    await post('بيع', [
      JournalLine(accountId: await acc('1111'), debit: 500),
      JournalLine(accountId: await acc('4121'), credit: 500),
    ]);
    await post('خصم مشتريات', [
      JournalLine(accountId: await acc('1136'), debit: 100),
      JournalLine(accountId: await acc('4316'), credit: 100),
    ]);

    final r = await db.getIncomeStatement(from, to);
    expect(r['totalRevenue'], closeTo(500, 0.001));
    expect(r['otherIncome'], closeTo(100, 0.001));
  });

  test('بلا حركة ترجع أصفاراً لا null', () async {
    final r = await db.getIncomeStatement(from, to);
    expect(r['totalRevenue'], 0);
    expect(r['salesReturns'], 0);
    expect(r['outputVatNet'], 0);
    expect(r['netRevenueInclVat'], 0);
  });
}
