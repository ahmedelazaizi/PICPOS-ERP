// ═══════════════════════════════════════════════════════════════════════════
// تقريرُ الطاولات — نطاقُ الصلاحية في **الاستعلام**، وما هي الجلسةُ أصلاً.
// ═══════════════════════════════════════════════════════════════════════════
//
// ترشيحُ العرض وحدَه يعني أن صفوفَ الفروع كلَّها تنزل ثم تُخفى — تسريبٌ لا
// ترشيح. فهذا الاختبار يقيس ما يرجع من `getTableOrdersForReport` نفسِها، لا
// ما تعرضه شاشة.
//
// و`table_orders` لا عمودَ فرعٍ فيه: فرعُ الطلب يأتي من فاتورته
// (`table_order_payments → sales_invoices.branch_id`). فالمقياسُ هنا يقفل
// المسارَ ذاته: طلبٌ مختومٌ بفرعٍ خارج النطاق **لا يعود**، وطلبٌ لم تصدر له
// فاتورةٌ بعد (الإشغالُ الجاري) يبقى مرئياً كما يبقى كلُّ صفٍّ بلا فرع.
//
// ويقفل كذلك تقسيمَ المسؤولية: **الاستعلامُ** يقرّر ما الجلسةُ (يُسقِط
// الملغى الذي يحمل `closedAt` فيبدو مغلقاً)، و**النموذجُ الخالص** يقرّر كيف
// تُجمَع (يُسقِط المدموج).

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/domain/models/tables_report_row.dart';

void main() {
  late AppDatabase db;
  late int branchA;
  late int branchB;
  late int hallId;
  late int terraceId;
  late int tableHall;
  late int tableTerrace;
  late int waiterOne;
  late int waiterTwo;

  final from = DateTime(2026, 3, 1);
  final to = DateTime(2026, 3, 31, 23, 59, 59, 999);

  /// فاتورةٌ مختومةٌ بفرعٍ + دفعةٌ مسوّاةٌ تربطها بالطلب — هذا هو المسارُ
  /// الوحيدُ الذي يعرف به طلبُ الطاولة فرعَه.
  Future<void> stampBranch(int orderId, int? branchId, String number) async {
    final invoiceId = await db.into(db.salesInvoices).insert(
          SalesInvoicesCompanion.insert(
            invoiceNumber: number,
            warehouseId: 1,
            userId: 1,
            invoiceDate: DateTime(2026, 3, 10),
            branchId: Value(branchId),
            total: const Value(100),
          ),
        );
    await db.into(db.tableOrderPayments).insert(
          TableOrderPaymentsCompanion.insert(
            tableOrderId: orderId,
            invoiceId: Value(invoiceId),
            amount: 100,
          ),
        );
  }

  Future<int> insertOrder({
    required int tableId,
    required double total,
    DateTime? openedAt,
    DateTime? closedAt,
    String status = 'closed',
    int guestCount = 2,
    int? mergedToId,
    int? userId,
    String? discountType,
    double discountValue = 0,
  }) =>
      db.into(db.tableOrders).insert(TableOrdersCompanion.insert(
            tableId: tableId,
            total: Value(total),
            status: Value(status),
            guestCount: Value(guestCount),
            mergedToId: Value(mergedToId),
            userId: Value(userId),
            discountType: Value(discountType),
            discountValue: Value(discountValue),
            openedAt: Value(openedAt ?? DateTime(2026, 3, 10, 12)),
            closedAt: Value(closedAt),
          ));

  setUp(() async {
    db = AppDatabase.forTesting();
    branchA = await db.into(db.branches).insert(BranchesCompanion.insert(
        name: 'فرع أ — طاولات', globalId: const Value('gid-br-tbl-a')));
    branchB = await db.into(db.branches).insert(BranchesCompanion.insert(
        name: 'فرع ب — طاولات', globalId: const Value('gid-br-tbl-b')));
    hallId = await db.createSection('صالة');
    terraceId = await db.createSection('تراس');
    tableHall = await db.createTable(name: 'ط١', sectionId: hallId);
    tableTerrace = await db.createTable(name: 'ط٢', sectionId: terraceId);
    // المفاتيحُ الأجنبيّة **مُنفَّذةٌ** في قاعدة الاختبار هذه، فنادلٌ وهميٌّ
    // برقمٍ عارٍ يُسقط الإدراجَ بـ`FOREIGN KEY constraint failed`.
    waiterOne = await db.into(db.users).insert(UsersCompanion.insert(
        username: 'tbl_report_waiter_1',
        passwordHash: 'x',
        displayName: 'نادل ١'));
    waiterTwo = await db.into(db.users).insert(UsersCompanion.insert(
        username: 'tbl_report_waiter_2',
        passwordHash: 'x',
        displayName: 'نادل ٢'));
  });

  tearDown(() async {
    // القاعدةُ في الذاكرة وتموت مع العملية؛ الإغلاقُ هنا آمنٌ لأنه لا تدفّقَ
    // مفتوحاً (لا ودجت ولا `watch`).
    await db.close();
  });

  test('النطاقُ الآمرُ يقصّ في الاستعلام: فرعٌ خارجَه لا يعود', () async {
    final inA = await insertOrder(
        tableId: tableHall, total: 100, closedAt: DateTime(2026, 3, 10, 13));
    final inB = await insertOrder(
        tableId: tableTerrace, total: 200, closedAt: DateTime(2026, 3, 10, 14));
    await stampBranch(inA, branchA, 'SI-TBL-A');
    await stampBranch(inB, branchB, 'SI-TBL-B');

    final full = await db.getTableOrdersForReport(from: from, to: to);
    expect(full.map((o) => o.total).toSet(), {100.0, 200.0},
        reason: 'بلا نطاقٍ يعود الاثنان');

    final scoped =
        await db.getTableOrdersForReport(from: from, to: to, allowedBranchIds: {branchA});
    expect(scoped.map((o) => o.total).toList(), [100.0],
        reason: 'طلبُ الفرع ب مختومٌ بفاتورته — لا ينزل أصلاً');
  });

  test('مجموعةٌ فارغةٌ تفشل مقفولةً — لا صفَّ واحد', () async {
    final order = await insertOrder(
        tableId: tableHall, total: 100, closedAt: DateTime(2026, 3, 10, 13));
    await stampBranch(order, branchA, 'SI-TBL-EMPTY');

    final rows = await db.getTableOrdersForReport(
        from: from, to: to, allowedBranchIds: const <int>{});
    expect(rows, isEmpty);
  });

  test('الطلبُ الذي لم تصدر له فاتورةٌ بعد يبقى مرئياً تحت أيّ نطاق', () async {
    // الإشغالُ الجاري: طلبٌ مفتوحٌ بلا دفعة ⇒ بلا فرع. إخفاؤه كان سيُسقِط
    // نصفَ غرض التقرير — نفسُ اتّفاق «الصفُّ بلا فرعٍ يبقى مرئياً».
    await insertOrder(
        tableId: tableHall, total: 30, status: 'open', closedAt: null);
    final stamped = await insertOrder(
        tableId: tableTerrace, total: 200, closedAt: DateTime(2026, 3, 10, 14));
    await stampBranch(stamped, branchB, 'SI-TBL-OPEN');

    final rows =
        await db.getTableOrdersForReport(from: from, to: to, allowedBranchIds: {branchA});
    expect(rows.map((o) => o.total).toList(), [30.0]);
  });

  test('الملغى لا يدخل التقريرَ — وهو يحمل closedAt فيبدو مغلقاً', () async {
    await insertOrder(
      tableId: tableHall,
      total: 999,
      status: 'cancelled',
      closedAt: DateTime(2026, 3, 10, 13),
    );
    await insertOrder(
        tableId: tableHall, total: 100, closedAt: DateTime(2026, 3, 10, 13));

    final rows = await db.getTableOrdersForReport(from: from, to: to);
    expect(rows.map((o) => o.total).toList(), [100.0],
        reason: 'لو دخل لَأضاف ٩٩٩ ديناراً لم تُحصَّل قطُّ إلى الإيراد');
  });

  test('المدموجُ يعود من الاستعلام ويسقط في التجميع — لا في الاثنين', () async {
    final target = await insertOrder(
        tableId: tableHall,
        total: 100,
        guestCount: 2,
        closedAt: DateTime(2026, 3, 10, 13));
    await insertOrder(
      tableId: tableTerrace,
      total: 50,
      guestCount: 3,
      closedAt: DateTime(2026, 3, 10, 12, 30),
      mergedToId: target,
    );

    final orders = await db.getTableOrdersForReport(from: from, to: to);
    expect(orders.where((o) => o.mergedToId != null), hasLength(1),
        reason: 'الاستعلامُ لا يخفي المدموجَ — الإسقاطُ قرارُ التجميع، '
            'ولو أخفاه الاثنان لَسقطت القاعدةُ من الاختبار الخالص بلا أن '
            'يلاحظ أحد');
    expect(orders.map((o) => o.id).toSet(), hasLength(2),
        reason: 'معرّفُ الطلب يصل النموذجَ — بدونه لا يُعرَف أيُّ صفٍّ '
            'يستضيف ضيوفَ المدموج');

    final rows = aggregateTablesReport(orders);
    expect(rows.fold<double>(0, (s, r) => s + r.revenue), 100);
    expect(rows.single.guestCount, 5,
        reason: 'ضيوفُ المدموج جلسوا على الطاولة الهدف فعلاً — '
            'الطيُّ يعمل من طرفِ القاعدة إلى الصفّ');
  });

  test('الخصمُ يُحلّ من المحرّك الواحد — نسبةً ومبلغاً وقصّاً', () async {
    await insertOrder(
        tableId: tableHall,
        total: 200,
        closedAt: DateTime(2026, 3, 10, 13),
        discountType: 'percent',
        discountValue: 10);
    await insertOrder(
        tableId: tableTerrace,
        total: 80,
        closedAt: DateTime(2026, 3, 10, 13),
        discountType: 'amount',
        discountValue: 500); // أكبرُ من المجمل ⇒ يُقصّ عنده

    final orders = await db.getTableOrdersForReport(from: from, to: to);
    final byTotal = {for (final o in orders) o.total: o.discount};
    expect(byTotal[200.0], 20, reason: '١٠٪ من ٢٠٠');
    expect(byTotal[80.0], 80,
        reason: 'الخصمُ مقصوصٌ عند المجمل — لا إيرادَ سالب');

    final rows = aggregateTablesReport(orders);
    expect(rows.fold<double>(0, (s, r) => s + r.revenue), 180);
  });

  test('القسمُ والطاولةُ والكاشيرُ كلُّها ترشّح في SQL', () async {
    await insertOrder(
        tableId: tableHall,
        total: 100,
        userId: waiterOne,
        closedAt: DateTime(2026, 3, 10, 13));
    await insertOrder(
        tableId: tableTerrace,
        total: 200,
        userId: waiterTwo,
        closedAt: DateTime(2026, 3, 10, 13));

    expect(
      (await db.getTableOrdersForReport(from: from, to: to, sectionId: hallId))
          .map((o) => o.total),
      [100.0],
    );
    expect(
      (await db.getTableOrdersForReport(
              from: from, to: to, tableId: tableTerrace))
          .map((o) => o.total),
      [200.0],
    );
    expect(
      (await db.getTableOrdersForReport(from: from, to: to, userId: waiterTwo))
          .map((o) => o.total),
      [200.0],
    );
  });

  test('المدى الزمنيُّ يقصّ على openedAt', () async {
    await insertOrder(
      tableId: tableHall,
      total: 100,
      openedAt: DateTime(2026, 2, 20, 12), // قبل المدى
      closedAt: DateTime(2026, 2, 20, 13),
    );
    await insertOrder(
        tableId: tableHall, total: 55, closedAt: DateTime(2026, 3, 10, 13));

    final rows = await db.getTableOrdersForReport(from: from, to: to);
    expect(rows.map((o) => o.total).toList(), [55.0]);
  });

  test('اسمُ الطاولة يصل الصفَّ — لا معرّفٌ عارٍ', () async {
    await insertOrder(
        tableId: tableTerrace, total: 10, closedAt: DateTime(2026, 3, 10, 13));
    final rows = await db.getTableOrdersForReport(from: from, to: to);
    expect(rows.single.tableName, 'ط٢');
    expect(aggregateTablesReport(rows).single.tableName, 'ط٢');
  });
}
