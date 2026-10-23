// ═══════════════════════════════════════════════════════════════════════════
// تجميعُ تقرير الطاولات — القواعدُ الثلاثُ مقيسةً لا موصوفة.
// ═══════════════════════════════════════════════════════════════════════════
//
// الحسابُ خالصٌ في `lib/domain/models/tables_report_row.dart`، فيُختبَر بلا
// قاعدةٍ ولا ودجت ولا Riverpod. وثلاثُ القواعد هي ما يفرّق تقريراً صادقاً عن
// تقريرٍ يجمع نفسَ المال مرّتين:
//
//   ١. الطلبُ المدموج (`mergedToId != null`) لا يُنتج صفّاً ولا إيراداً —
//      إجماليُّه انتقل إلى هدفه — **وضيوفُه يُطوَون في صفّ الهدف**، لأن
//      `guestCount` لا ينتقل بالدمج فتضيع أنفسٌ جلست فعلاً.
//   ٢. الطلبُ المفتوح (`closedAt == null`) إشغالٌ لا إيراد.
//   ٣. مدّةُ الجلوس بالدقائق من `openedAt` إلى `closedAt` — للمغلقة وحدَها.

import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/domain/models/tables_report_row.dart';

/// مُنشئٌ مختصرٌ للاختبار — `id` مطلوبٌ لأن `mergedToId` يشير إلى **طلب**.
TableOrderInput order({
  required int id,
  required int tableId,
  String? tableName,
  double total = 0,
  int guestCount = 1,
  double discount = 0,
  DateTime? openedAt,
  DateTime? closedAt,
  int? mergedToId,
}) =>
    TableOrderInput(
      id: id,
      tableId: tableId,
      tableName: tableName ?? 'ط$tableId',
      total: total,
      guestCount: guestCount,
      discount: discount,
      openedAt: openedAt ?? DateTime(2026, 1, 1, 12),
      closedAt: closedAt,
      mergedToId: mergedToId,
    );

void main() {
  test('الطلبُ المدموجُ لا يُحسَب مرّتين', () {
    final rows = aggregateTablesReport([
      order(
          id: 1,
          tableId: 1,
          tableName: 'ط١',
          total: 100,
          guestCount: 2,
          openedAt: DateTime(2026, 1, 1, 12),
          closedAt: DateTime(2026, 1, 1, 13)),
      // طلبٌ دُمج في الأوّل ⇒ إجماليُّه انتقل، فلا يُضاف ثانيةً.
      order(
          id: 2,
          tableId: 2,
          tableName: 'ط٢',
          total: 50,
          guestCount: 1,
          openedAt: DateTime(2026, 1, 1, 12),
          closedAt: DateTime(2026, 1, 1, 12, 30),
          mergedToId: 1),
    ]);
    final total = rows.fold<double>(0, (s, r) => s + r.revenue);
    expect(total, 100, reason: 'المدموجُ إجماليُّه انتقل إلى هدفه');
  });

  test('مدّةُ الجلوس بالدقائق من openedAt إلى closedAt', () {
    final rows = aggregateTablesReport([
      order(
          id: 1,
          tableId: 1,
          total: 100,
          guestCount: 2,
          openedAt: DateTime(2026, 1, 1, 12),
          closedAt: DateTime(2026, 1, 1, 13, 30)),
    ]);
    expect(rows.single.avgTurnMinutes, 90);
  });

  test('الطلبُ المفتوح لا يدخل الإيرادَ ولا متوسّطَ المدّة', () {
    final rows = aggregateTablesReport([
      order(id: 1, tableId: 1, total: 70, guestCount: 2, closedAt: null),
    ]);
    expect(rows.single.revenue, 0);
    expect(rows.single.avgTurnMinutes, isNull);
  });

  // ── القاعدة ١ بتمامها: المالُ لا يُعَدّ مرّتين، والأنفسُ لا تضيع ─────────
  group('المدموج — الإيرادُ ينتقل والضيوفُ يُطوَون', () {
    test('لا صفَّ للطاولة المدموجة، وضيوفُها في صفّ الهدف', () {
      final rows = aggregateTablesReport([
        order(
            id: 1,
            tableId: 1,
            tableName: 'ط١',
            total: 100,
            guestCount: 2,
            closedAt: DateTime(2026, 1, 1, 13)),
        order(
            id: 2,
            tableId: 2,
            tableName: 'ط٢',
            total: 50,
            guestCount: 3,
            closedAt: DateTime(2026, 1, 1, 12, 30),
            mergedToId: 1),
      ]);
      expect(rows.map((r) => r.tableId), [1],
          reason: 'الطاولةُ المدموجةُ ليست جلسةً مستقلّةً — صفٌّ لها يعدّ '
              'الجلسةَ الواحدةَ جلستَين');
      expect(rows.single.orderCount, 1);
      expect(rows.single.guestCount, 5,
          reason: 'ثلاثةٌ انتقلوا إلى طاولةِ اثنين — `mergeTableOrders` لا '
              'يرفع guestCount على الهدف، فبلا الطيّ يضيعون');
      expect(rows.single.revenue, 100,
          reason: 'الإيرادُ إيرادُ الهدف وحدَه — البنودُ انتقلت إليه بالفعل');
    });

    test('نصيبُ الضيف لا يتضخّم بعد الدمج', () {
      final rows = aggregateTablesReport([
        order(
            id: 1,
            tableId: 1,
            total: 100,
            guestCount: 2,
            closedAt: DateTime(2026, 1, 1, 13)),
        order(
            id: 2,
            tableId: 2,
            total: 0,
            guestCount: 3,
            closedAt: DateTime(2026, 1, 1, 13),
            mergedToId: 1),
      ]);
      expect(rows.single.revenuePerGuest, 20,
          reason: '١٠٠ ÷ ٥ لا ١٠٠ ÷ ٢');
    });

    test('سلسلةُ دمجٍ: الضيوفُ يصلون آخرَ الهدف لا وسيطَه', () {
      final rows = aggregateTablesReport([
        order(
            id: 1,
            tableId: 1,
            total: 100,
            guestCount: 2,
            closedAt: DateTime(2026, 1, 1, 13)),
        // ب دُمج في أ
        order(
            id: 2,
            tableId: 2,
            total: 0,
            guestCount: 3,
            closedAt: DateTime(2026, 1, 1, 13),
            mergedToId: 1),
        // ج دُمج في ب — والحسابُ استقرّ على أ
        order(
            id: 3,
            tableId: 3,
            total: 0,
            guestCount: 4,
            closedAt: DateTime(2026, 1, 1, 13),
            mergedToId: 2),
      ]);
      expect(rows.map((r) => r.tableId), [1]);
      expect(rows.single.guestCount, 9);
    });

    test('هدفٌ خارج مجموعة التقرير: يُسقَط ولا يُخترَع له صفّ', () {
      final rows = aggregateTablesReport([
        order(
            id: 5,
            tableId: 5,
            total: 40,
            guestCount: 3,
            closedAt: DateTime(2026, 1, 1, 13),
            mergedToId: 999), // ليس في المجموعة (خارجَ المدى أو القسم)
      ]);
      expect(rows, isEmpty,
          reason: 'صفٌّ من ضيوفٍ بلا إيرادٍ اختراعٌ لا قياس');
    });

    test('حلقةُ دمجٍ لا تُعلّق التجميع', () {
      final rows = aggregateTablesReport([
        order(
            id: 1,
            tableId: 1,
            total: 100,
            guestCount: 2,
            closedAt: DateTime(2026, 1, 1, 13)),
        order(id: 2, tableId: 2, guestCount: 3, mergedToId: 3),
        order(id: 3, tableId: 3, guestCount: 4, mergedToId: 2),
      ]);
      expect(rows.map((r) => r.tableId), [1]);
      expect(rows.single.guestCount, 2);
    });
  });

  // ── ما وراء القواعد الثلاث ───────────────────────────────────────────────
  // ما تحته يقفل الدلالاتِ التي تحتملها القواعدُ ولا تحسمها — فلا تُقرأ يوماً
  // على وجهٍ آخر بلا أن يسقط شيء.

  test('المفتوحُ يُحسَب إشغالاً: طلبٌ وضيوفٌ بلا إيراد', () {
    final rows = aggregateTablesReport([
      order(id: 1, tableId: 5, total: 40, guestCount: 4, closedAt: null),
    ]);
    expect(rows.single.orderCount, 1);
    expect(rows.single.guestCount, 4);
    expect(rows.single.discount, 0);
  });

  test('الإيرادُ صافٍ من الخصم — والخصمُ يُعرَض إلى جانبه', () {
    final rows = aggregateTablesReport([
      order(
          id: 1,
          tableId: 1,
          total: 100,
          guestCount: 2,
          discount: 30,
          closedAt: DateTime(2026, 1, 1, 13)),
    ]);
    expect(rows.single.revenue, 70,
        reason: 'المحصَّلُ هو ما بعد الخصم — لا المجملُ قبله');
    expect(rows.single.discount, 30);
  });

  test('خصمُ الطلب المفتوح لا يُحسَب — كما لا يُحسَب إيرادُه', () {
    final rows = aggregateTablesReport([
      order(
          id: 1,
          tableId: 1,
          total: 100,
          guestCount: 2,
          discount: 25,
          closedAt: null),
    ]);
    expect(rows.single.revenue, 0);
    expect(rows.single.discount, 0,
        reason: 'خصمٌ بلا إيرادٍ يقابله يجعل الثابتَ «إيراد + خصم = مجمل '
            'المغلقة» كاذباً');
  });

  test('طلباتُ طاولةٍ واحدةٍ تُجمَع في صفٍّ واحد، والمدّةُ متوسّطُها', () {
    final rows = aggregateTablesReport([
      order(
          id: 1,
          tableId: 7,
          total: 100,
          guestCount: 2,
          openedAt: DateTime(2026, 1, 1, 12),
          closedAt: DateTime(2026, 1, 1, 13)), // ٦٠ دقيقة
      order(
          id: 2,
          tableId: 7,
          total: 60,
          guestCount: 3,
          openedAt: DateTime(2026, 1, 1, 14),
          closedAt: DateTime(2026, 1, 1, 16)), // ١٢٠ دقيقة
    ]);
    expect(rows.length, 1);
    expect(rows.single.orderCount, 2);
    expect(rows.single.guestCount, 5);
    expect(rows.single.revenue, 160);
    expect(rows.single.avgTurnMinutes, 90, reason: 'متوسّطُ ٦٠ و١٢٠');
  });

  test('المفتوحُ لا يُخفّض متوسّطَ المدّة بصفرٍ مقحَم', () {
    final rows = aggregateTablesReport([
      order(
          id: 1,
          tableId: 7,
          total: 100,
          guestCount: 2,
          openedAt: DateTime(2026, 1, 1, 12),
          closedAt: DateTime(2026, 1, 1, 13)),
      order(
          id: 2,
          tableId: 7,
          guestCount: 2,
          openedAt: DateTime(2026, 1, 1, 14),
          closedAt: null),
    ]);
    expect(rows.single.avgTurnMinutes, 60,
        reason: 'المقامُ عددُ المغلقة وحدَها — لا عددُ الطلبات');
  });

  test('الصفوفُ مرتَّبةٌ بالإيراد نزولاً — الأعلى أوّلاً', () {
    final rows = aggregateTablesReport([
      order(id: 1, tableId: 1, total: 10, closedAt: DateTime(2026, 1, 1, 13)),
      order(id: 2, tableId: 2, total: 90, closedAt: DateTime(2026, 1, 1, 13)),
    ]);
    expect(rows.map((r) => r.tableId), [2, 1]);
  });

  test('قائمةٌ فارغةٌ تعطي صفوفاً فارغةً لا استثناءً', () {
    expect(aggregateTablesReport(const []), isEmpty);
  });

  group('overallAvgTurnMinutes — متوسّطُ الرأس', () {
    test('المقامُ عددُ الجلسات لا عددُ الطاولات', () {
      final avg = overallAvgTurnMinutes([
        // طاولةٌ واحدةٌ عليها جلسةٌ واحدةٌ ١٢٠ دقيقة.
        order(
            id: 1,
            tableId: 1,
            total: 100,
            openedAt: DateTime(2026, 1, 1, 12),
            closedAt: DateTime(2026, 1, 1, 14)),
        // وطاولةٌ عليها ثلاثُ جلساتٍ ٢٠ دقيقةً لكلٍّ.
        for (var i = 0; i < 3; i++)
          order(
              id: 10 + i,
              tableId: 2,
              total: 10,
              openedAt: DateTime(2026, 1, 1, 12 + i),
              closedAt: DateTime(2026, 1, 1, 12 + i, 20)),
      ]);
      // (120 + 20×3) / 4 = 45 — لا (120 + 20) / 2 = 70.
      expect(avg, 45);
    });

    test('المدموجُ والمفتوحُ خارج المتوسّط', () {
      final avg = overallAvgTurnMinutes([
        order(
            id: 1,
            tableId: 1,
            total: 100,
            openedAt: DateTime(2026, 1, 1, 12),
            closedAt: DateTime(2026, 1, 1, 13)),
        order(
            id: 2,
            tableId: 2,
            total: 50,
            openedAt: DateTime(2026, 1, 1, 12),
            closedAt: DateTime(2026, 1, 1, 15), // ١٨٠ لو حُسبت
            mergedToId: 1),
        order(id: 3, tableId: 3, openedAt: DateTime(2026, 1, 1, 12)),
      ]);
      expect(avg, 60);
    });

    test('لا جلسةَ مغلقةً ⇒ null لا صفر', () {
      expect(overallAvgTurnMinutes([order(id: 1, tableId: 1, total: 10)]),
          isNull);
    });
  });
}
