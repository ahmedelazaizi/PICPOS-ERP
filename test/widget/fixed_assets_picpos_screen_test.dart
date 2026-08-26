// test/widget/fixed_assets_picpos_screen_test.dart
//
// تركيبُ شاشة «الأصول الثابتة والإهلاك» بهويّة PicPos — خمسةُ تبويباتٍ
// بعرضَين.
//
// ⚠️ **العرضان ليسا احتياطاً.** كلُّ تبويبٍ يحمل صفَّ عدّاداتٍ (‏خمسةً في
// الأوّل وأربعةً في الثاني والرابع) فوقَ جدولٍ من ستّةِ أعمدةٍ إلى ثمانية.
// وقد فاض من قبل ٢٧٤px في `PicPosPageHeader` و١٤٣px في ربط الحسابات — ثمّ
// انهارت شاشةُ التكاليف المحمَّلة كاملةً من `IntrinsicHeight` حول
// `LayoutBuilder`. فالتبويباتُ الخمسةُ تُفتَح كلُّها عند العرضَين.
//
// ⚠️ **ومرساةُ الحساب**: القسطُ الشهريُّ منقولٌ عن `runMonthlyDepreciation`،
// والمتناقصُ فيها **مضاعفٌ** (`2/(n·12)`) لا ٢٠٪ كما يفترض نصُّ التصميم.
// فيُقاس هنا رقمُ القسط نفسُه على أصلٍ معلومِ الأرقام — لو انحرف الحسابان
// لعرضت الشاشةُ رقماً ويُقيَّد غيرُه.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ural_erp/data/database/database.dart' as db;
import 'package:ural_erp/data/providers/repository_providers.dart';
import 'package:ural_erp/domain/repositories/accounting_repository.dart';
import 'package:ural_erp/domain/repositories/fixed_assets_repository.dart';
import 'package:ural_erp/presentation/picpos_shell/picpos_report_tabs.dart';
import 'package:ural_erp/presentation/fixed_assets_picpos/screens/fixed_assets_picpos_screen.dart';

final _now = DateTime(2026, 8, 26);

db.FixedAssetData _asset({
  required int id,
  required String code,
  required String name,
  required int categoryId,
  required double cost,
  required double accumulated,
  required double life,
  String method = 'straight_line',
  String status = 'active',
  String? location,
  DateTime? disposalDate,
  double? disposalValue,
}) =>
    db.FixedAssetData(
      id: id,
      code: code,
      name: name,
      categoryId: categoryId,
      location: location,
      purchasePrice: cost,
      purchaseDate: DateTime(2020, 1, 1),
      usefulLifeYears: life,
      salvageValue: 0,
      depreciationMethod: method,
      accumulatedDepreciation: accumulated,
      status: status,
      disposalDate: disposalDate,
      disposalValue: disposalValue,
      createdAt: DateTime(2020, 1, 1),
    );

/// ٨٦٬٠٠٠ على ٧ سنواتٍ قسطاً ثابتاً ⇒ ٨٦٠٠٠ ÷ ٨٤ = **١٬٠٢٣٫٨١** شهريّاً.
/// ونسبةُ إهلاكه ٤٦٬٧١٤ ÷ ٨٦٬٠٠٠ = ٥٤٪ ⇒ «نشط».
/// و٣٤٬٠٠٠ بمجمعٍ ٣٠٬١٤٣ ⇒ ٨٩٪ ⇒ «قارب الانتهاء».
final _assets = [
  _asset(
      id: 1,
      code: 'AST-001',
      name: 'ثلاجة عرض 4م',
      categoryId: 10,
      cost: 86000,
      accumulated: 46714,
      life: 7,
      location: 'فرع المعادي'),
  _asset(
      id: 2,
      code: 'AST-004',
      name: 'تكييف 5 حصان',
      categoryId: 10,
      cost: 34000,
      accumulated: 30143,
      life: 7,
      location: 'فرع مدينة نصر'),
  _asset(
      id: 3,
      code: 'AST-007',
      name: 'ماكينة قطع لحوم',
      categoryId: 11,
      cost: 58200,
      accumulated: 49600,
      life: 8,
      status: 'sold',
      disposalDate: DateTime(2026, 6, 15),
      disposalValue: 12400),
];

const _categories = [
  db.AssetCategory(
    id: 10,
    name: 'أجهزة تبريد',
    defaultUsefulLife: 7,
    defaultDepreciationMethod: 'straight_line',
    accountId: 100,
    depreciationAccountId: 200,
  ),
  db.AssetCategory(
    id: 11,
    name: 'آلات ومعدات',
    defaultUsefulLife: 8,
    defaultDepreciationMethod: 'declining_balance',
    accountId: 101,
    depreciationAccountId: 201,
  ),
];

/// الشاشةُ تقرأ `code` و`name` وحدَهما لبناء «١٢١١ · أجهزة»، وباقي الأعمدة
/// مطلوبةٌ في المولَّد فتُملأ بقيمٍ محايدة.
db.Account _account(int id, String code, String name) => db.Account(
      id: id,
      code: code,
      name: name,
      accountType: 'asset',
      accountNature: 'debit',
      normalBalance: 'debit',
      level: 2,
      balance: 0,
      isSystem: false,
      isActive: true,
      isHiddenFromEntries: false,
      rowVersion: 1,
    );

final _accounts = [
  _account(100, '1211', 'أجهزة'),
  _account(200, '1311', 'مجمع إهلاك أجهزة'),
  _account(101, '1214', 'آلات'),
  _account(201, '1314', 'مجمع إهلاك آلات'),
];

class _FakeAssetsRepo implements IFixedAssetsRepository {
  @override
  Stream<List<db.FixedAssetData>> watchFixedAssets() => Stream.value(_assets);

  @override
  Stream<List<db.AssetCategory>> watchAssetCategories() =>
      Stream.value(_categories);

  @override
  Stream<List<db.AssetDepreciationData>> watchAllDepreciations() =>
      Stream.value(const []);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

class _FakeAccountingRepo implements IAccountingRepository {
  @override
  Stream<List<db.Account>> watchAllAccounts() => Stream.value(_accounts);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

Future<void> _pump(WidgetTester tester, double width) async {
  tester.view.physicalSize = Size(width, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        fixedAssetsRepositoryProvider.overrideWithValue(_FakeAssetsRepo()),
        accountingRepositoryProvider.overrideWithValue(_FakeAccountingRepo()),
      ],
      child: const MaterialApp(home: FixedAssetsPicposScreen()),
    ),
  );
  await tester.pump();
  await tester.pump();
}

/// يفتح التبويبَ بالضغط على عنوانه **داخلَ شريط التبويبات** — لا على أيّ
/// نصٍّ يحمل الاسم، فبعضُ العناوين تتكرّر في الجداول.
Future<void> _openTab(WidgetTester tester, String label) async {
  await tester.tap(find.descendant(
    of: find.byType(PicPosReportTabs),
    matching: find.text(label),
  ));
  // ⚠️ `PicPosReportTabs` ينادي `controller.animateTo(i)` لا `index = i` —
  //    فالانتقالُ بحركةٍ لها زمن. وضخّتان بلا مدّةٍ لا تُقدّمان الزمنَ،
  //    فيبقى محتوى التبويب القديم معروضاً ويمرّ فحصُ «لم ينهر» وهو لم يفتح
  //    شيئاً أصلاً. وهذا ما أخفى أربعةَ إخفاقاتٍ حتّى قِيس المحتوى نفسُه.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  for (final width in [1280.0, 1920.0]) {
    final w = width.toInt();

    testWidgets('التبويباتُ الخمسةُ كلُّها تُرسَم بلا فيضان عند عرض $w',
        (tester) async {
      await _pump(tester, width);

      expect(find.text('الأصول الثابتة والإهلاك'), findsOneWidget);

      for (final tab in [
        'الأصول',
        'الإهلاك الدوري',
        'الفئات',
        'الاستبعاد والبيع',
        'التوزيع والمواقع',
      ]) {
        await _openTab(tester, tab);
        expect(tester.takeException(), isNull,
            reason: 'تبويبُ «$tab» فاض أو انهار عند عرض $w.');
      }
    });

    testWidgets('تبويبُ الأصول — العدّاداتُ الخمسةُ والجدولُ عند عرض $w',
        (tester) async {
      await _pump(tester, width);

      // ⚠️ `findsWidgets` لا `findsOneWidget`: «مجمع الإهلاك» و«القيمة
      //    الدفترية» عنوانا عدّادٍ **وعمودٍ في الجدول** معاً، فالتشديدُ على
      //    واحدٍ يسقط على تكرارٍ مشروع.
      for (final label in [
        'الأصول النشطة',
        'التكلفة التاريخية',
        'مجمع الإهلاك',
        'القيمة الدفترية',
        'أصول قارب عمرها',
      ]) {
        expect(find.text(label), findsWidgets,
            reason: 'العدّادُ «$label» غائبٌ عند $w.');
      }

      expect(find.text('بطاقات الأصول'), findsOneWidget);
      expect(find.textContaining('AST-001'), findsOneWidget);
    });
  }

  testWidgets('«قارب الانتهاء» يُحسب من نسبة الإهلاك لا من التاريخ',
      (tester) async {
    await _pump(tester, 1920);

    // AST-004 مجمعُه ٣٠٬١٤٣ من ٣٤٬٠٠٠ = ٨٩٪ ⇒ فوق حدِّ ٨٥٪.
    expect(find.text('قارب الانتهاء'), findsWidgets,
        reason: 'الأصلُ الذي تجاوز إهلاكُه ٨٥٪ لم يُصنَّف «قارب الانتهاء».');

    // AST-001 مجمعُه ٥٤٪ ⇒ يبقى «نشط». والمرساةُ أنّ الشارتَين تظهران معاً،
    // فلو صُنّف الكلُّ صنفاً واحداً لسقط أحدُ الفحصَين.
    expect(find.text('نشط'), findsWidgets,
        reason: 'الأصلُ دونَ الحدِّ لم يبقَ «نشط» — التصنيفُ يقع على الكلّ.');
  });

  testWidgets('القسطُ الشهريُّ مطابقٌ لحساب الـDAO لا لنصّ التصميم',
      (tester) async {
    await _pump(tester, 1920);
    await _openTab(tester, 'الإهلاك الدوري');

    // فئةُ «أجهزة تبريد» فيها أصلان قسطاً ثابتاً:
    //   ٨٦٠٠٠ ÷ (٧×١٢) = ١٬٠٢٣٫٨١   و   ٣٤٠٠٠ ÷ (٧×١٢) =   ٤٠٤٫٧٦
    //   المجموع = ١٬٤٢٨٫٥٧
    expect(find.text('1,428.57'), findsWidgets,
        reason: 'قسطُ فئة التبريد لا يطابق `depreciable / (life * 12)` — '
            'راجعْ `_monthlyDepreciation` مقابلَ `runMonthlyDepreciation`.');

    // ولا صفَّ إهلاكٍ لهذا الشهر في التجهيزة ⇒ الحالةُ «بانتظار الترحيل».
    expect(find.text('بانتظار الترحيل'), findsWidgets,
        reason: 'الفئةُ بلا صفِّ فترةٍ يجب أن تُعرَض بانتظار الترحيل.');
  });

  testWidgets('الأصلُ المباعُ يخرج من الأصول ويظهر في الاستبعاد بربحه',
      (tester) async {
    await _pump(tester, 1920);
    await _openTab(tester, 'الاستبعاد والبيع');

    expect(find.textContaining('AST-007'), findsOneWidget,
        reason: 'الأصلُ المباعُ غائبٌ عن تبويب الاستبعاد.');

    // ٥٨٬٢٠٠ − ٤٩٬٦٠٠ = ٨٬٦٠٠ دفتريّة · ثمنُ البيع ١٢٬٤٠٠ ⇒ ربحُ ٣٬٨٠٠.
    expect(find.textContaining('3,800'), findsWidgets,
        reason: 'الربحُ لا يساوي ثمنَ البيع ناقصَ القيمة الدفترية.');
  });

  testWidgets('التوزيعُ يجمع الأصولَ النشطةَ حسب الموقع', (tester) async {
    await _pump(tester, 1920);
    await _openTab(tester, 'التوزيع والمواقع');

    expect(find.text('القيمة الدفترية حسب الموقع'), findsOneWidget);
    expect(find.textContaining('فرع المعادي'), findsWidgets);

    // ⚠️ الأصلُ المباعُ (‏بلا موقع) يجب ألّا يظهر هنا: التوزيعُ على النشط
    //    وحدَه، وإلّا نُسب للمواقع أصلٌ خرج من الدفاتر.
    expect(find.textContaining('AST-007'), findsNothing,
        reason: 'الأصلُ المستبعدُ ظهر في التوزيع — والتوزيعُ للنشط وحدَه.');
  });
}
