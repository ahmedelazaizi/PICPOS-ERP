// test/widget/financial_statements_remediation_dialog_test.dart
//
// اختبارُ **توصيفٍ** لحوار «إصلاح فروقات التقارير والمراكز».
//
// ═══ لماذا مفردٌ في ملفّ ═══
//
// هذا الحوارُ رابعُ الحوارات العارية (`financial_statements_picpos_screen`
// عند السطر 1610 يوم 2026-08-27)، وهو **الوحيدُ** الذي يعرض معاينةَ
// تشغيلٍ جافّةٍ قبل عمليّةٍ تمسّ بيانات: يستدعي
// `repairBranchCostCenters(dryRun: true)` ويبني سطرَه من نتيجتها.
//
// فالنقلُ إلى `PicPosDialog` هنا ليس تبديلَ غلاف: لو ضاع سطرُ المعاينة
// أو انقلب فرعٌ من فروعه الثلاثة، صار المشغّلُ يضغط «بدء الإصلاح» بلا
// علمٍ بحجم ما سيتحرّك. وهذه الاختباراتُ تثبّت الفروعَ الثلاثةَ كلَّها
// قبل النقل، فتبقى خضراءَ بعده أو تكشفه.
//
// ⚠️ ولا يُقاس «فُتح حوار» وحدَه — يُقاس **نصُّه**.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:picpos_erp/data/providers/providers.dart';
import 'package:picpos_erp/domain/repositories/accounting_repository.dart';
import 'package:picpos_erp/domain/repositories/audit_repository_interface.dart';
import 'package:picpos_erp/domain/repositories/i_products_repository.dart';
import 'package:picpos_erp/domain/repositories/inventory_repository.dart';
import 'package:picpos_erp/domain/repositories/parties_repository.dart';
import 'package:picpos_erp/domain/repositories/settings_repository.dart';
import 'package:picpos_erp/presentation/accounting_picpos/financial_statements_picpos_screen.dart';
import 'package:picpos_erp/services/accounting_service.dart';

// ⚠️ فاكٌّ لكلِّ واجهةٍ على حدة، لا صنفٌ يجمع السبعَ: `IProductRepository`
//    و`InventoryRepository` تعلنان `getExpiredBatches` بنوعَي إرجاعٍ
//    مختلفَين، و`IAuditRepository` تخالف `IProductRepository` في
//    `logActivity`. فالجمعُ خطأُ ترجمةٍ لا اختصار.
class _FakeAccounting implements IAccountingRepository {
  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeParties implements IPartiesRepository {
  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeTreasury implements ITreasuryRepository {
  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeProducts implements IProductRepository {
  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeInventory implements InventoryRepository {
  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSettings implements ISettingsRepository {
  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeAudit implements IAuditRepository {
  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// خدمةُ محاسبةٍ لا تلمس قاعدةً — تُرجع معاينةً مثبّتةً أو ترمي.
class _StubAccountingService extends AccountingService {
  _StubAccountingService(this._preview)
      : super(
          _FakeAccounting(),
          _FakeParties(),
          _FakeTreasury(),
          _FakeProducts(),
          _FakeInventory(),
          _FakeSettings(),
          _FakeAudit(),
        );

  /// `null` ⇒ ترمي، فيُقاس فرعُ «تعذّر حساب المعاينة».
  final BranchCostCenterRepairReport? _preview;

  @override
  Future<BranchCostCenterRepairReport> repairBranchCostCenters({
    bool dryRun = true,
  }) async {
    final p = _preview;
    if (p == null) throw StateError('لا اتّصالَ بالقاعدة في الاختبار');
    return p;
  }
}

void main() {
  Future<void> pump(
    WidgetTester tester,
    double width, {
    BranchCostCenterRepairReport? preview,
  }) async {
    tester.view.physicalSize = Size(width, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          // ⚠️ الشاشةُ تحجب نفسَها حتى يُحسم نطاقُ الفروع.
          branchScopeProvider
              .overrideWith((ref) async => const BranchScope.fullAccess()),
          accountingServiceProvider
              .overrideWith((ref) => _StubAccountingService(preview)),
        ],
        child: const MaterialApp(home: FinancialStatementsPicPosScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  Future<void> openRemediation(WidgetTester tester) async {
    await tester.tap(find.byIcon(PhosphorIconsBold.magicWand));
    await tester.pump();
    // المعاينةُ غيرُ متزامنة — إطارٌ للمستقبَل ثمّ إطارٌ لحركةِ الحوار.
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> teardown(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
  }

  for (final width in [1280.0, 1920.0]) {
    final w = width.toInt();

    group('عرض $w', () {
      testWidgets('الحوارُ يعرض الخطوتين والطمأنينةَ وزرَّي القرار',
          (tester) async {
        await pump(
          tester,
          width,
          preview: const BranchCostCenterRepairReport(
            affectedEntries: 0,
            affectedLines: 0,
            applied: false,
          ),
        );
        await openRemediation(tester);

        expect(
          find.text('١) تعبئة مراكز التكلفة للأسطر التاريخية من رؤوس القيود.'),
          findsOneWidget,
        );
        expect(
          find.text(
            'العملية آمنة ولا تغيّر أي مبالغ مدينة/دائنة — تعيد فقط تصنيف '
            'مركز التكلفة.',
          ),
          findsOneWidget,
        );
        expect(find.text('بدء الإصلاح'), findsOneWidget);
        expect(find.text('إلغاء'), findsOneWidget);
        expect(tester.takeException(), isNull);

        await teardown(tester);
      });

      testWidgets('ولا عملَ ⇒ يقولها صراحةً', (tester) async {
        await pump(
          tester,
          width,
          preview: const BranchCostCenterRepairReport(
            affectedEntries: 0,
            affectedLines: 0,
            applied: false,
          ),
        );
        await openRemediation(tester);

        expect(
          find.text('٢) لا توجد قيود بحاجة لإعادة التوزيع على مراكز الفروع.'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);

        await teardown(tester);
      });

      testWidgets('وعملٌ قائمٌ ⇒ يعرض العددَين قبل الضغط', (tester) async {
        await pump(
          tester,
          width,
          preview: const BranchCostCenterRepairReport(
            affectedEntries: 7,
            affectedLines: 19,
            applied: false,
          ),
        );
        await openRemediation(tester);

        // ⚠️ العددان هما كلُّ ما يعرفه المشغّلُ عن حجم ما سيتحرّك.
        expect(
          find.text(
            '٢) قيود آلية مسجّلة على «عام» وتخص فروعاً لها مركز تكلفة خاص: '
            '7 قيد / 19 سطر — ستُنقل إلى مركز تكلفة الفرع.',
          ),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);

        await teardown(tester);
      });

      testWidgets('وفشلُ المعاينةِ يُقال ولا يمنع فتحَ الحوار',
          (tester) async {
        await pump(tester, width, preview: null);
        await openRemediation(tester);

        expect(
          find.text('٢) تعذّر حساب معاينة إصلاح مراكز الفروع.'),
          findsOneWidget,
        );
        expect(find.text('بدء الإصلاح'), findsOneWidget);
        expect(tester.takeException(), isNull);

        await teardown(tester);
      });

      testWidgets('و«إلغاء» يُغلقه بلا تشغيل', (tester) async {
        await pump(
          tester,
          width,
          preview: const BranchCostCenterRepairReport(
            affectedEntries: 3,
            affectedLines: 4,
            applied: false,
          ),
        );
        await openRemediation(tester);

        await tester.tap(find.text('إلغاء'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));

        expect(find.text('بدء الإصلاح'), findsNothing);
        expect(tester.takeException(), isNull);

        await teardown(tester);
      });
    });
  }
}
