// test/widget/report_builder_picpos_screen_test.dart
//
// تركيبُ شاشة «التقارير المخصّصة» بهويّة PicPos — بعرضَين.
//
// ⚠️ **العرضان ليسا احتياطاً.** الشاشةُ ثلاثةُ أعمدةٍ فوق ١٥٠٠ وعمودان دونه
// وواحدٌ متمرّرٌ دون ١٠٥٠. وقد انهارت شاشةُ التكاليف المحمَّلة كاملةً من
// تركيبٍ لم يُقَس عند عرضَين.
//
// ⚠️ **ومرساةُ العوامل**: `getFilterOperators` قائمةٌ **مغلقةٌ مربوطةٌ بنوع
// الحقل** — و«يحتوي» ممنوعٌ على الرقميّ لأنّه يقارن نصّاً (`100` تحتوي `0`).
// فيُقاس هنا أنّ المنسدلةَ تقرأ من المحرّك لا من قائمةٍ ثانيةٍ في الواجهة:
// لو كانت نسخةً لأمكن أن تعرض عاملاً يرفضه المحرّك، فيخرج التقريرُ مرفوضاً
// بالكامل — صفرَ صفوفٍ بلا رسالةِ خطأ. وهو عطلٌ لا يُرى.
//
// ⚠️ **ومرساةُ الاقتطاع**: `executeReport` يبلّغ عبر `onRowLimitReached` حين
// يتجاوز الناتجُ السقف. وقارئُ تقريرٍ مقتطعٍ يجمع أعمدتَه ويظنّها كاملة —
// فيُقاس أنّ التنبيهَ يظهر فعلاً.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:picpos_erp/data/database/database.dart' as db;
import 'package:picpos_erp/data/providers/repository_providers.dart';
import 'package:picpos_erp/domain/repositories/reporting_repository.dart';
import 'package:picpos_erp/presentation/report_builder_picpos/screens/report_builder_picpos_screen.dart';

/// نفسُ قائمةِ المحرّك: «يحتوي» للنصّ وحدَه.
const _opsByType = {
  'text': [
    {'op': '=', 'label': 'يساوي'},
    {'op': '!=', 'label': 'لا يساوي'},
    {'op': 'contains', 'label': 'يحتوي'},
  ],
  'number': [
    {'op': '=', 'label': 'يساوي'},
    {'op': '!=', 'label': 'لا يساوي'},
    {'op': '>', 'label': 'أكبر من'},
    {'op': '>=', 'label': 'أكبر من أو يساوي'},
    {'op': '<', 'label': 'أصغر من'},
    {'op': '<=', 'label': 'أصغر من أو يساوي'},
  ],
};

const _productFields = [
  {'key': 'name', 'label': 'اسم المنتج', 'type': 'text'},
  {'key': 'code', 'label': 'الكود', 'type': 'text'},
  {'key': 'price', 'label': 'سعر البيع', 'type': 'number'},
];

class _FakeReportingRepo implements IReportingRepository {
  _FakeReportingRepo({this.truncateAt});

  /// حين لا يكون `null` يُحاكي تجاوزَ السقف فيُنادى المُبلِّغ.
  final int? truncateAt;

  @override
  Future<List<db.CustomReportData>> getCustomReports() async => [
        db.CustomReportData(
          id: 7,
          name: 'أصناف تحت حد الطلب',
          description: 'أصناف رصيدها أقل من حد الطلب',
          sourceEntity: 'products',
          columns: 'name,code,price',
          isShared: true,
          createdAt: DateTime(2026, 8, 1),
        ),
      ];

  @override
  List<Map<String, String>> getAvailableFields(String entity) =>
      entity == 'products' ? _productFields : const [];

  @override
  List<Map<String, String>> getFilterOperators(String fieldType) =>
      _opsByType[fieldType] ?? const [];

  @override
  Future<List<Map<String, dynamic>>> executeReport(
    int reportId, {
    Set<int>? allowedBranchIds,
    void Function(int limit)? onRowLimitReached,
  }) async {
    if (truncateAt != null) onRowLimitReached?.call(truncateAt!);
    return [
      {'name': 'زيت عافية 1ل', 'code': 'SKU-1108', 'price': 86.0},
      {'name': 'أرز مصري 5ك', 'code': 'SKU-1190', 'price': 182.0},
    ];
  }

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
      child: const MaterialApp(home: ReportBuilderPicposScreen()),
    ),
  );
  await tester.pump();
  await tester.pump();
}

void main() {
  for (final width in [1280.0, 1920.0]) {
    final w = width.toInt();

    testWidgets('لوحاتُ البانِي كلُّها تُرسَم بلا فيضان عند عرض $w',
        (tester) async {
      await _pump(tester, width);

      expect(tester.takeException(), isNull,
          reason: 'شاشةُ التقارير المخصّصة فاضت عند $w — راجعْ حدَّي '
              '١٥٠٠ و١٠٥٠.');

      for (final panel in [
        'جهة البيانات',
        'الأعمدة',
        'الشروط',
        'تجميع حسب',
        'الدوال التجميعية',
        'المعاينة',
      ]) {
        expect(find.text(panel), findsWidgets,
            reason: 'لوحةُ «$panel» غائبةٌ عند $w.');
      }

      // ⚠️ «الترتيب» آخرُ لوحةٍ في `ListView` كسول، فلا تُبنى قبل أن تُبلَغ.
      //    والمستخدمُ يصلها بالتمرير — فالفحصُ يمرّر مثله بدل أن يشكوَ من
      //    غيابٍ ليس غياباً.
      await tester.dragUntilVisible(
        find.text('الترتيب'),
        find.text('جهة البيانات'),
        const Offset(0, -220),
      );
      expect(find.text('الترتيب'), findsWidgets,
          reason: 'لوحةُ «الترتيب» لا تُبلَغ بالتمرير عند $w.');
    });
  }

  testWidgets('الكياناتُ السبعةُ معروضةٌ للاختيار', (tester) async {
    await _pump(tester, 1920);

    for (final label in [
      'الأصناف',
      'فواتير البيع',
      'فواتير الشراء',
      'العملاء والموردون',
      'أرصدة المخازن',
      'القيود المحاسبية',
      'الموظفون',
    ]) {
      expect(find.text(label), findsWidgets,
          reason: 'الكيانُ «$label» غائبٌ — والمحرّكُ يقبله.');
    }
  });

  testWidgets('الحقولُ تُقرأ من سجلّ المحرّك لا من قائمةٍ في الواجهة',
      (tester) async {
    await _pump(tester, 1920);

    // `getAvailableFields('products')` في التجهيزة تعطي ثلاثةَ حقولٍ
    // بأسمائها — فلو كانت الواجهةُ تحمل قائمتَها لظهرت أسماءٌ أخرى.
    expect(find.text('اسم المنتج'), findsWidgets,
        reason: 'الحقولُ لا تأتي من `getAvailableFields`.');
    expect(find.text('سعر البيع'), findsWidgets);
  });

  testWidgets('«الدوال التجميعية» تقول متى تُطبَّق — بلا تجميعٍ لا أثرَ لها',
      (tester) async {
    await _pump(tester, 1920);

    // ⚠️ **العقدُ انقلب في §٣‑٤(ب)** (‏2026-08-31): كانت اللوحةُ تُحفَظ ولا
    //    تُقرأ إطلاقاً، وكان وسمُها «لا تُطبَّق بعد» صادقاً. صار
    //    `_buildReportQuery` يقرأ `aggregates` ويبني `SUM(col)` — لكن **عند
    //    وجود «تجميع حسب» وحدَه**، فبلا مجموعاتٍ تبقى النتيجةُ سرداً للصفوف.
    //
    //    فالوسمُ يتبع الحالَ لا العكس: الاختبارُ يقفل أنّ اللوحةَ تصف أثرَها
    //    **الحقيقيَّ** في كلتا الحالتين، ولا تدّعي ولا تُنكِر خطأً.
    expect(find.text('تُطبَّق عند اختيار «تجميع حسب» — وبدونه سردُ صفوف'),
        findsOneWidget,
        reason: 'بلا تجميعٍ لا أثرَ للدوالّ — واللوحةُ يجب أن تقول ذلك.');

    expect(find.text('تُحفَظ مع التعريف — ولا تُطبَّق على الناتج بعد'),
        findsNothing,
        reason: 'الوسمُ القديمُ صار كاذباً — الدوالُّ تُطبَّق فعلاً الآن.');
  });

  testWidgets('تشغيلُ تقريرٍ محفوظٍ يعرض صفوفَه الحقيقيّة', (tester) async {
    await _pump(tester, 1920);

    await tester.tap(find.text('أصناف تحت حد الطلب'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'تشغيل'));
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('زيت عافية'), findsWidgets,
        reason: 'ناتجُ `executeReport` لا يصل جدولَ المعاينة.');
  });

  testWidgets('🔴 الاقتطاعُ يُقال صراحةً ولا يُبتلَع', (tester) async {
    await _pump(tester, 1920, repo: _FakeReportingRepo(truncateAt: 10000));

    await tester.tap(find.text('أصناف تحت حد الطلب'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'تشغيل'));
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('الناتجُ مقتطعٌ'), findsOneWidget,
        reason: 'المستخدمُ يقرأ تقريراً ناقصاً كأنّه كامل ويجمع أعمدته.');
  });
}
