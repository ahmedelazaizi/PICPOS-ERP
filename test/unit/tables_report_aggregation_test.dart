// ═══════════════════════════════════════════════════════════════════════════
// تجميعُ تقرير الطاولات — القواعدُ الثلاثُ مقيسةً لا موصوفة.
// ═══════════════════════════════════════════════════════════════════════════
//
// الحسابُ خالصٌ في `lib/domain/models/tables_report_row.dart`، فيُختبَر بلا
// قاعدةٍ ولا ودجت ولا Riverpod. وثلاثُ القواعد هي ما يفرّق تقريراً صادقاً عن
// تقريرٍ يجمع نفسَ المال مرّتين:
//
//   ١. الطلبُ المدموج (`mergedToId != null`) لا يُحسَب — إجماليُّه انتقل
//      إلى هدفه، وضيوفُه جلسوا على الطاولة الهدف.
//   ٢. الطلبُ المفتوح (`closedAt == null`) إشغالٌ لا إيراد.
//   ٣. مدّةُ الجلوس بالدقائق من `openedAt` إلى `closedAt` — للمغلقة وحدَها.

import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/domain/models/tables_report_row.dart';

void main() {
  test('الطلبُ المدموجُ لا يُحسَب مرّتين', () {
    final rows = aggregateTablesReport([
      TableOrderInput(
          tableId: 1,
          tableName: 'ط١',
          total: 100,
          guestCount: 2,
          discount: 0,
          openedAt: DateTime(2026, 1, 1, 12),
          closedAt: DateTime(2026, 1, 1, 13),
          mergedToId: null),
      // طلبٌ دُمج في الأوّل ⇒ إجماليُّه انتقل، فلا يُضاف ثانيةً.
      TableOrderInput(
          tableId: 2,
          tableName: 'ط٢',
          total: 50,
          guestCount: 1,
          discount: 0,
          openedAt: DateTime(2026, 1, 1, 12),
          closedAt: DateTime(2026, 1, 1, 12, 30),
          mergedToId: 1),
    ]);
    final total = rows.fold<double>(0, (s, r) => s + r.revenue);
    expect(total, 100, reason: 'المدموجُ إجماليُّه انتقل إلى هدفه');
  });

  test('مدّةُ الجلوس بالدقائق من openedAt إلى closedAt', () {
    final rows = aggregateTablesReport([
      TableOrderInput(
          tableId: 1,
          tableName: 'ط١',
          total: 100,
          guestCount: 2,
          discount: 0,
          openedAt: DateTime(2026, 1, 1, 12),
          closedAt: DateTime(2026, 1, 1, 13, 30),
          mergedToId: null),
    ]);
    expect(rows.single.avgTurnMinutes, 90);
  });

  test('الطلبُ المفتوح لا يدخل الإيرادَ ولا متوسّطَ المدّة', () {
    final rows = aggregateTablesReport([
      TableOrderInput(
          tableId: 1,
          tableName: 'ط١',
          total: 70,
          guestCount: 2,
          discount: 0,
          openedAt: DateTime(2026, 1, 1, 12),
          closedAt: null,
          mergedToId: null),
    ]);
    expect(rows.single.revenue, 0);
    expect(rows.single.avgTurnMinutes, isNull);
  });

  // ── ما وراء القواعد الثلاث ───────────────────────────────────────────────
  // الاختباراتُ فوق تقفل القواعدَ الثلاثَ التي تُنتج الرقمَ الكاذب. وما تحتها
  // يقفل الدلالاتِ التي تحتملها القواعدُ ولا تحسمها — فلا تُقرأ يوماً على
  // وجهٍ آخر بلا أن يسقط شيء.

  test('المدموجُ لا يُنتج صفّاً أصلاً — لا جلسةَ له ولا ضيوف', () {
    final rows = aggregateTablesReport([
      TableOrderInput(
          tableId: 1,
          tableName: 'ط١',
          total: 100,
          guestCount: 2,
          discount: 0,
          openedAt: DateTime(2026, 1, 1, 12),
          closedAt: DateTime(2026, 1, 1, 13),
          mergedToId: null),
      TableOrderInput(
          tableId: 2,
          tableName: 'ط٢',
          total: 50,
          guestCount: 3,
          discount: 0,
          openedAt: DateTime(2026, 1, 1, 12),
          closedAt: DateTime(2026, 1, 1, 12, 30),
          mergedToId: 1),
    ]);
    expect(rows.map((r) => r.tableId), [1],
        reason: 'الطاولةُ المدموجةُ ليست جلسةً مستقلّةً — ضيوفُها جلسوا على '
            'الهدف، فصفٌّ لها يعدّهم مرّتين');
    expect(rows.single.orderCount, 1);
    expect(rows.single.guestCount, 2);
  });

  test('المفتوحُ يُحسَب إشغالاً: طلبٌ وضيوفٌ بلا إيراد', () {
    final rows = aggregateTablesReport([
      TableOrderInput(
          tableId: 5,
          tableName: 'ط٥',
          total: 40,
          guestCount: 4,
          discount: 0,
          openedAt: DateTime(2026, 1, 1, 12),
          closedAt: null,
          mergedToId: null),
    ]);
    expect(rows.single.orderCount, 1);
    expect(rows.single.guestCount, 4);
    expect(rows.single.discount, 0);
  });

  test('الإيرادُ صافٍ من الخصم — والخصمُ يُعرَض إلى جانبه', () {
    final rows = aggregateTablesReport([
      TableOrderInput(
          tableId: 1,
          tableName: 'ط١',
          total: 100,
          guestCount: 2,
          discount: 30,
          openedAt: DateTime(2026, 1, 1, 12),
          closedAt: DateTime(2026, 1, 1, 13),
          mergedToId: null),
    ]);
    expect(rows.single.revenue, 70,
        reason: 'المحصَّلُ هو ما بعد الخصم — لا المجملُ قبله');
    expect(rows.single.discount, 30);
  });

  test('خصمُ الطلب المفتوح لا يُحسَب — كما لا يُحسَب إيرادُه', () {
    final rows = aggregateTablesReport([
      TableOrderInput(
          tableId: 1,
          tableName: 'ط١',
          total: 100,
          guestCount: 2,
          discount: 25,
          openedAt: DateTime(2026, 1, 1, 12),
          closedAt: null,
          mergedToId: null),
    ]);
    expect(rows.single.revenue, 0);
    expect(rows.single.discount, 0,
        reason: 'خصمٌ بلا إيرادٍ يقابله يجعل الثابتَ «إيراد + خصم = مجمل '
            'المغلقة» كاذباً');
  });

  test('طلباتُ طاولةٍ واحدةٍ تُجمَع في صفٍّ واحد، والمدّةُ متوسّطُها', () {
    final rows = aggregateTablesReport([
      TableOrderInput(
          tableId: 7,
          tableName: 'ط٧',
          total: 100,
          guestCount: 2,
          discount: 0,
          openedAt: DateTime(2026, 1, 1, 12),
          closedAt: DateTime(2026, 1, 1, 13), // ٦٠ دقيقة
          mergedToId: null),
      TableOrderInput(
          tableId: 7,
          tableName: 'ط٧',
          total: 60,
          guestCount: 3,
          discount: 0,
          openedAt: DateTime(2026, 1, 1, 14),
          closedAt: DateTime(2026, 1, 1, 16), // ١٢٠ دقيقة
          mergedToId: null),
    ]);
    expect(rows.length, 1);
    expect(rows.single.orderCount, 2);
    expect(rows.single.guestCount, 5);
    expect(rows.single.revenue, 160);
    expect(rows.single.avgTurnMinutes, 90, reason: 'متوسّطُ ٦٠ و١٢٠');
  });

  test('المفتوحُ لا يُخفّض متوسّطَ المدّة بصفرٍ مقحَم', () {
    final rows = aggregateTablesReport([
      TableOrderInput(
          tableId: 7,
          tableName: 'ط٧',
          total: 100,
          guestCount: 2,
          discount: 0,
          openedAt: DateTime(2026, 1, 1, 12),
          closedAt: DateTime(2026, 1, 1, 13),
          mergedToId: null),
      TableOrderInput(
          tableId: 7,
          tableName: 'ط٧',
          total: 0,
          guestCount: 2,
          discount: 0,
          openedAt: DateTime(2026, 1, 1, 14),
          closedAt: null,
          mergedToId: null),
    ]);
    expect(rows.single.avgTurnMinutes, 60,
        reason: 'المقامُ عددُ المغلقة وحدَها — لا عددُ الطلبات');
  });

  test('الصفوفُ مرتَّبةٌ بالإيراد نزولاً — الأعلى أوّلاً', () {
    final rows = aggregateTablesReport([
      TableOrderInput(
          tableId: 1,
          tableName: 'ط١',
          total: 10,
          guestCount: 1,
          discount: 0,
          openedAt: DateTime(2026, 1, 1, 12),
          closedAt: DateTime(2026, 1, 1, 13),
          mergedToId: null),
      TableOrderInput(
          tableId: 2,
          tableName: 'ط٢',
          total: 90,
          guestCount: 1,
          discount: 0,
          openedAt: DateTime(2026, 1, 1, 12),
          closedAt: DateTime(2026, 1, 1, 13),
          mergedToId: null),
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
        TableOrderInput(
            tableId: 1,
            tableName: 'ط١',
            total: 100,
            guestCount: 2,
            discount: 0,
            openedAt: DateTime(2026, 1, 1, 12),
            closedAt: DateTime(2026, 1, 1, 14),
            mergedToId: null),
        // وطاولةٌ عليها ثلاثُ جلساتٍ ٢٠ دقيقةً لكلٍّ.
        for (var i = 0; i < 3; i++)
          TableOrderInput(
              tableId: 2,
              tableName: 'ط٢',
              total: 10,
              guestCount: 1,
              discount: 0,
              openedAt: DateTime(2026, 1, 1, 12 + i),
              closedAt: DateTime(2026, 1, 1, 12 + i, 20),
              mergedToId: null),
      ]);
      // (120 + 20×3) / 4 = 45 — لا (120 + 20) / 2 = 70.
      expect(avg, 45);
    });

    test('المدموجُ والمفتوحُ خارج المتوسّط', () {
      final avg = overallAvgTurnMinutes([
        TableOrderInput(
            tableId: 1,
            tableName: 'ط١',
            total: 100,
            guestCount: 2,
            discount: 0,
            openedAt: DateTime(2026, 1, 1, 12),
            closedAt: DateTime(2026, 1, 1, 13),
            mergedToId: null),
        TableOrderInput(
            tableId: 2,
            tableName: 'ط٢',
            total: 50,
            guestCount: 1,
            discount: 0,
            openedAt: DateTime(2026, 1, 1, 12),
            closedAt: DateTime(2026, 1, 1, 15), // ١٨٠ لو حُسبت
            mergedToId: 1),
        TableOrderInput(
            tableId: 3,
            tableName: 'ط٣',
            total: 0,
            guestCount: 1,
            discount: 0,
            openedAt: DateTime(2026, 1, 1, 12),
            closedAt: null,
            mergedToId: null),
      ]);
      expect(avg, 60);
    });

    test('لا جلسةَ مغلقةً ⇒ null لا صفر', () {
      expect(
        overallAvgTurnMinutes([
          TableOrderInput(
              tableId: 1,
              tableName: 'ط١',
              total: 10,
              guestCount: 1,
              discount: 0,
              openedAt: DateTime(2026, 1, 1, 12),
              closedAt: null,
              mergedToId: null),
        ]),
        isNull,
      );
    });
  });
}
