// test/widget/analytics_picpos_screen_test.dart
//
// تركيبُ شاشة «التحليلات» بهويّة PicPos — بعرضَين.
//
// ⚠️ **العرضان ليسا احتياطاً.** الشاشةُ تضع خمسَ بطاقاتٍ في صفٍّ واحدٍ فوق
// ٩٠٠، ثمّ جدولَ اتجاهٍ وبطاقةَ موسميّةٍ جنباً إلى جنبٍ فوق ١١٠٠. وقد انهارت
// شاشةُ التكاليف المحمَّلة كاملةً من تركيبٍ لم يُقَس عند عرضَين.
//
// ⚠️ **ومرساةُ الحساب**: الأرقامُ كلُّها من `PerformanceAnalyticsService` على
// سلسلةٍ **معلومةٍ سلفاً**، فالمتوقَّعُ محسوبٌ باليد هنا ويُقارَن. ولو نُقل
// رقمٌ من التصميم — أو حُسب بمعادلةٍ أخرى — لسقط الفحص.
//
// السلسلةُ: ثلاثةُ أشهرٍ بمبيعاتٍ ١٠٠٠ و١٢٠٠ و١٤٠٠.
//   الميلُ بالانحدار الخطّيّ على (0,1000) (1,1200) (2,1400) = **٢٠٠**
//   التغيّرُ = (1400−1000)/1000 = **٤٠٪**
//   تنبّؤُ الشهر القادم = 1400 + 200 = **١٦٠٠**
// والهامشُ: التكلفةُ ٦٠٠ من ١٠٠٠ ⇒ ٤٠٪ في الشهر الأوّل.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ural_erp/data/providers/repository_providers.dart';
import 'package:ural_erp/domain/repositories/reporting_repository.dart';
import 'package:ural_erp/presentation/analytics_picpos/screens/analytics_picpos_screen.dart';

/// ثلاثةُ أشهرٍ متتاليةٍ تنتهي بالشهر الجاري — كي تقع داخلَ نافذة القراءة.
List<Map<String, dynamic>> _series() {
  final now = DateTime.now();
  String ym(int back) {
    final d = DateTime(now.year, now.month - back, 1);
    return '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}';
  }

  return [
    {
      'ym': ym(2),
      'net_sales': 1000.0,
      'invoice_count': 10,
      'cogs': 600.0,
      'expenses': 200.0,
    },
    {
      'ym': ym(1),
      'net_sales': 1200.0,
      'invoice_count': 12,
      'cogs': 720.0,
      'expenses': 210.0,
    },
    {
      'ym': ym(0),
      'net_sales': 1400.0,
      'invoice_count': 14,
      'cogs': 840.0,
      'expenses': 220.0,
    },
  ];
}

class _FakeReportingRepo implements IReportingRepository {
  @override
  Future<List<Map<String, dynamic>>> getMonthlyPerformanceSeries({
    required DateTime from,
    required DateTime to,
    int? costCenterId,
    List<int>? warehouseIds,
    Set<int>? allowedBranchIds,
  }) async =>
      _series();

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

/// مستودعٌ يرمي — لقياسِ أنّ الإخفاقَ يُقال ولا يُبتلَع في بطاقةٍ فارغة.
class _ThrowingReportingRepo implements IReportingRepository {
  @override
  Future<List<Map<String, dynamic>>> getMonthlyPerformanceSeries({
    required DateTime from,
    required DateTime to,
    int? costCenterId,
    List<int>? warehouseIds,
    Set<int>? allowedBranchIds,
  }) async =>
      throw StateError('no such column: cost_price');

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

Future<void> _pump(
  WidgetTester tester,
  double width, {
  IReportingRepository? repo,
}) async {
  tester.view.physicalSize = Size(width, 1100);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        reportingRepositoryProvider
            .overrideWithValue(repo ?? _FakeReportingRepo()),
      ],
      child: const MaterialApp(home: AnalyticsPicposScreen()),
    ),
  );
  await tester.pump();
  await tester.pump();
}

void main() {
  for (final width in [1280.0, 1920.0]) {
    final w = width.toInt();

    testWidgets('الشاشةُ تُرسَم بمؤشّراتها الخمسة بلا فيضان عند عرض $w',
        (tester) async {
      await _pump(tester, width);

      expect(tester.takeException(), isNull,
          reason: 'شاشةُ التحليلات فاضت عند $w — راجعْ حدَّي ٩٠٠ و١١٠٠.');

      expect(find.text('التحليلات'), findsOneWidget);
      for (final label in [
        'صافي المبيعات',
        'هامش الربح الإجمالي',
        'متوسط قيمة الفاتورة',
        'عدد الفواتير',
        'المصروفات التشغيلية',
      ]) {
        expect(find.text(label), findsWidgets,
            reason: 'المؤشّرُ «$label» غائبٌ عند $w.');
      }

      expect(find.text('تحليل الاتجاه لكل مؤشر'), findsOneWidget);
      expect(find.text('مُعامل الموسمية'), findsOneWidget);
    });
  }

  testWidgets('الميلُ والتغيّرُ والتنبّؤُ من المحرّك لا من التصميم',
      (tester) async {
    await _pump(tester, 1920);

    // ميلُ المبيعات على (1000، 1200، 1400) = ٢٠٠ بالضبط.
    expect(find.text('+200'), findsWidgets,
        reason: 'ميلُ المبيعات لا يساوي ٢٠٠ — راجعْ '
            '`PerformanceAnalyticsService.analyzeTrend`.');

    // التغيّرُ من ١٠٠٠ إلى ١٤٠٠ = ٤٠٫٠٪.
    expect(find.text('+40.0٪'), findsWidgets,
        reason: 'التغيّرُ لا يساوي ٤٠٪ — راجعْ `changePercent`.');

    // تنبّؤُ الشهر القادم = ١٤٠٠ + ٢٠٠ = ١٦٠٠.
    expect(find.text('1,600'), findsWidgets,
        reason: 'التنبّؤُ لا يساوي النهايةَ زائدَ الميل.');
  });

  testWidgets('الهامشُ محسوبٌ من التكلفة لا مقروءٌ من عمود', (tester) async {
    await _pump(tester, 1920);

    // ٦٠٠ تكلفةً من ١٠٠٠ مبيعاتٍ ⇒ هامشٌ ٤٠٪ — ثابتٌ عبر الشهور الثلاثة،
    // فالميلُ صفرٌ والاتّجاهُ «مستقر». وهذا يقيس أنّ الهامشَ نسبةٌ محسوبةٌ
    // لا مبلغٌ منقول.
    expect(find.text('مستقر'), findsWidgets,
        reason: 'الهامشُ الثابتُ ٤٠٪ يجب أن يعطي اتّجاهاً مستقرّاً — '
            'فلو كان يُقرأ مبلغاً لصار صاعداً.');
  });

  testWidgets('إخفاقُ الاستعلام يُقال ولا يُبتلَع في شاشةٍ فارغة',
      (tester) async {
    await _pump(tester, 1920, repo: _ThrowingReportingRepo());

    expect(find.text('تعذّر حسابُ السلسلة الزمنيّة'), findsOneWidget,
        reason: 'رمْيُ SQL ابتُلع — فتبدو الشاشةُ عاملةً على سلسلةٍ فارغة.');
  });

  testWidgets('سلسلةٌ أقصرُ من نقطتَين لا تُرسَم اتجاهاً كاذباً',
      (tester) async {
    await _pump(tester, 1920, repo: _ShortSeriesRepo());

    expect(find.text('لا تكفي البياناتُ لرسم اتجاه'), findsOneWidget,
        reason: 'الانحدارُ على نقطةٍ واحدةٍ يعطي ميلاً صفراً يبدو حقيقةً — '
            'فالشاشةُ يجب أن تمتنع لا أن ترسم.');
  });
}

class _ShortSeriesRepo implements IReportingRepository {
  @override
  Future<List<Map<String, dynamic>>> getMonthlyPerformanceSeries({
    required DateTime from,
    required DateTime to,
    int? costCenterId,
    List<int>? warehouseIds,
    Set<int>? allowedBranchIds,
  }) async {
    final now = DateTime.now();
    return [
      {
        'ym': '${now.year}-${now.month.toString().padLeft(2, '0')}',
        'net_sales': 1000.0,
        'invoice_count': 10,
        'cogs': 600.0,
        'expenses': 200.0,
      }
    ];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}
