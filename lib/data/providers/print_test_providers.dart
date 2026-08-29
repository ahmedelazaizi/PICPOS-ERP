// مزوّداتُ المعاينة التجريبيّة.
//
// ── «نفسُ الراسم الذي يطبع — لا معاينةٌ موازية» ──────────────────────────
// المعاينةُ هنا تمرّ بـ`buildDocument` ⇐ `paginate` ⇐ `planPage`، وهي عينُ
// السلسلةِ التي يمشيها `TemplateRenderPipeline.render` قبل أن يسلّم البايتاتِ
// للطابعة. فما تعرضه الشاشةُ **عاجزٌ بنيويّاً** عن أن يفترق عن الورق.
//
// والفحوصُ تُحسب من [PaintOp] نفسِها — لا قائمةَ مكتوبةٌ بجانب كلِّ حالة.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/picpos_template_card.dart';
import '../../domain/printing/print_probe.dart';
import '../../domain/printing/print_test_scenarios.dart';
import '../../services/printing/layout_engine.dart';
import '../../services/printing/paint_plan.dart';
import '../../services/printing/template_render_pipeline.dart';
import '../../services/templated_invoice_service.dart';
import '../database/database.dart';
import 'repository_providers.dart';
import 'template_library_providers.dart';

/// القالبُ الجاري فحصُه — تضبطه الشاشةُ عند الفتح.
class PrintTestTemplateNotifier extends Notifier<int?> {
  @override
  int? build() => null;
  void set(int? id) => state = id;
}

final printTestTemplateProvider =
    NotifierProvider<PrintTestTemplateNotifier, int?>(
        PrintTestTemplateNotifier.new);

/// حالةُ البيانات المختارة.
class PrintTestScenarioNotifier extends Notifier<String> {
  @override
  String build() => 'normal';
  void set(String id) => state = id;
}

final printTestScenarioProvider =
    NotifierProvider<PrintTestScenarioNotifier, String>(
        PrintTestScenarioNotifier.new);

/// الطابعةُ الوجهة — `null` يعني «حفظ PDF بلا طابعة».
class PrintTestTargetNotifier extends Notifier<int?> {
  @override
  int? build() => null;
  void set(int? id) => state = id;
}

final printTestTargetProvider =
    NotifierProvider<PrintTestTargetNotifier, int?>(
        PrintTestTargetNotifier.new);

final printScenariosProvider =
    Provider<List<PrintScenario>>((ref) => buildPrintScenarios());

/// طابعاتٌ يمكن الطبعُ عليها — تقرؤها قائمةُ الوجهة.
final printTestPrintersProvider =
    FutureProvider.autoDispose<List<Printer>>((ref) =>
        ref.watch(printersRepositoryProvider).getActivePrinters());

/// نتيجةُ المعاينة — الصفحاتُ وفحوصُها معاً.
///
/// ⚠️ **واحدةٌ لا اثنتان**: لو حُسبت الصفحاتُ في مزوِّدٍ والفحوصُ في آخرَ
/// لأمكن أن يتأخّر أحدُهما فتُعرَض فحوصُ ورقةٍ سابقةٍ فوق ورقةٍ جديدة — وهي
/// عينُ فئة العطب «المعاينة ≠ الورق» في ثوبٍ آخر.
class PrintTestResult {
  final List<ProbedPage> pages;
  final List<PrintCheck> checks;
  final double paperWidthMm;
  final String templateName;

  /// خطأُ بناءٍ حين ينهار الحساب — يُعرَض بدل ورقةٍ فارغةٍ صامتة.
  final String? error;

  const PrintTestResult({
    required this.pages,
    required this.checks,
    required this.paperWidthMm,
    required this.templateName,
    this.error,
  });

  bool get isBlocked => hasBlockingFailure(checks);

  int get failCount =>
      checks.where((c) => c.level == ProbeLevel.fail).length;
  int get warnCount =>
      checks.where((c) => c.level == ProbeLevel.warn).length;
}

final printTestResultProvider =
    FutureProvider.autoDispose<PrintTestResult?>((ref) async {
  ref.watch(templateLibraryRefreshProvider);

  final templateId = ref.watch(printTestTemplateProvider);
  if (templateId == null) return null;

  final repo = ref.watch(invoiceTemplatesRepositoryProvider);
  final data = await repo.getTemplateWithData(templateId);
  if (data == null) return null;

  final scenarioId = ref.watch(printTestScenarioProvider);
  final scenarios = ref.watch(printScenariosProvider);
  final scenario = scenarios.firstWhere((s) => s.id == scenarioId,
      orElse: () => scenarios.first);

  // عرضُ الطابعة الوجهةِ حين يُعرَف. و`Printers` لا تسجّل عرضاً، فالمعلومُ
  // يقيناً هو أنّ الحراريّةَ لا تتجاوز ٨٠مم — وما عداها لا يُحكَم عليه.
  final targetId = ref.watch(printTestTargetProvider);
  double? printerWidthMm;
  if (targetId != null) {
    final printers =
        ref.watch(printTestPrintersProvider).value ?? const <Printer>[];
    for (final p in printers) {
      if (p.id == targetId && p.printerType == 'thermal') {
        printerWidthMm = 80;
      }
    }
  }

  try {
    final ordered =
        TemplatedInvoiceService.orderElementsForPrint(data.elements);
    final document = TemplateRenderPipeline.buildDocument(
      template: data.template,
      orderedElements: ordered,
      tableSettings: data.tableSettings,
    );
    final positioned = LayoutEngine.paginate(
      document: document,
      rows: TemplateRenderPipeline.buildRows(
          scenario.items, document.table, scenario.payload.decimals),
      values: TemplateRenderPipeline.buildValues(document, scenario.payload),
    );

    final probed = [
      for (final p in positioned) ProbedPage(p, planPage(p)),
    ];

    return PrintTestResult(
      pages: probed,
      checks: probePrintout(
        pages: probed,
        document: document,
        printerWidthMm: printerWidthMm,
      ),
      paperWidthMm: data.template.paperWidth,
      templateName: data.template.name,
    );
  } catch (e) {
    // انهيارُ الحساب **فحصٌ أحمرُ لا شاشةٌ فارغة**: الغرضُ من هذه الشاشة
    // منعُ الورق المعطوب، وورقةٌ لا تُحسب أولى بالمنع من ورقةٍ تُقصّ.
    return PrintTestResult(
      pages: const [],
      checks: [
        PrintCheck(ProbeLevel.fail, 'انهار حسابُ التخطيط', '$e'),
      ],
      paperWidthMm: 0,
      templateName: '',
      error: '$e',
    );
  }
});

/// بطاقاتُ القوالب المتاحةِ للفحص — نفسُ مصدر المكتبة.
final printTestTemplatesProvider =
    Provider.autoDispose<List<TemplateCard>>((ref) =>
        ref.watch(templateCardsProvider).value ?? const <TemplateCard>[]);
