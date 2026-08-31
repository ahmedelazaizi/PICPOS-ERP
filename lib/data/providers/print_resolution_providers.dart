// مزوّداتُ شاشة حسم القوالب — الوصلُ بين المستودع والشاشة.
//
// ── ما تجيب عنه الشاشة ───────────────────────────────────────────────────
// «هذه الفاتورةُ خرجت بهذا الشكل — لماذا؟» سؤالٌ لا جواب له اليومَ إلّا
// بقراءة `templated_invoice_service.dart` وجدولِ الرابطات وعَلَمِ `isDefault`
// معاً. والشاشةُ تجمعها في سطرٍ لكلِّ نوعِ مستند.
//
// ── ولا سطرَ واحدٌ منها مُختلَق ──────────────────────────────────────────
// كلُّ خانةٍ تُقرأ من القاعدة وتُحسم بـ[TemplateResolver] **نفسِه** الذي
// يمشيه مسارُ الطباعة، وبنفس الزوج `(type, category)` الذي يمرّره المنادي
// (‏[TemplateResolver.documentContexts]). فشاشةٌ تحسم بغيره تشرح مطبوعاً
// آخرَ غيرَ الذي يخرج من الطابعة.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/picpos_template_card.dart';
import '../../domain/models/print_resolution_row.dart';
import '../../services/printing/paper_compatibility.dart';
import '../../services/printing/template_resolver.dart';
import 'providers.dart';
import 'template_library_providers.dart';

/// خيارُ الفرع في شريط الترشيح — `null` يعني «كل الفروع».
class ResolutionBranchNotifier extends Notifier<int?> {
  @override
  int? build() => null;
  void set(int? id) => state = id;
}

final resolutionBranchProvider =
    NotifierProvider<ResolutionBranchNotifier, int?>(
        ResolutionBranchNotifier.new);

/// لغةُ المستند المفحوصة — تدخل المفتاحَ الرباعيَّ في المستويات ١..٣.
class ResolutionLocaleNotifier extends Notifier<String> {
  @override
  String build() => 'ar';
  void set(String l) => state = l;
}

final resolutionLocaleProvider =
    NotifierProvider<ResolutionLocaleNotifier, String>(
        ResolutionLocaleNotifier.new);

/// نوعُ المستند المحدَّد — تفصّله اللوحةُ اليمنى.
class SelectedDocumentTypeNotifier extends Notifier<String?> {
  @override
  String? build() => null;
  void set(String? t) => state = t;
}

final selectedDocumentTypeProvider =
    NotifierProvider<SelectedDocumentTypeNotifier, String?>(
        SelectedDocumentTypeNotifier.new);

/// صفوفُ الجدول — مسارٌ لكلِّ نوعِ مستند.
final printResolutionRowsProvider =
    FutureProvider.autoDispose<List<PrintResolutionRow>>((ref) async {
  // نفسُ عدّاد المكتبة: تفعيلُ قالبٍ هناك يجب أن يُرى هنا فوراً، وإلّا ظنّ
  // المستخدمُ أنّ التفعيل لم يعمل.
  ref.watch(templateLibraryRefreshProvider);

  final repo = ref.watch(invoiceTemplatesRepositoryProvider);
  final db = ref.watch(databaseProvider);
  final branchId = ref.watch(resolutionBranchProvider);
  final locale = ref.watch(resolutionLocaleProvider);

  final templates = await repo.getAllTemplates();
  final bindingRows = await repo.getAllBindings();
  final printers =
      await ref.watch(printersRepositoryProvider).getPrinters();

  final byId = {for (final t in templates) t.id: t};
  final printerById = {for (final p in printers) p.id: p};

  final rules = [
    for (final r in bindingRows)
      BindingRule(
        templateId: r.templateId,
        documentType: r.documentType,
        branchId: r.branchId,
        printerId: r.printerId,
        locale: r.locale,
        copies: r.copies,
        directPrint: r.directPrint,
        priority: r.priority,
      ),
  ];

  // افتراضيُّ الفئة (المستوى السادس) لكلِّ زوجٍ — يُحسب مرّةً لا مرّةً لكلِّ
  // صفّ. و`getSingleOrNull` في الـDAO ترمي عند افتراضيَّين، فالقراءةُ هنا
  // من القائمة كاملةً: **أوّلُ** ما يطابق، وهو ما يفعله SQLite عمليّاً.
  int? categoryDefault(String type, String category) {
    for (final t in templates) {
      if (t.type == type && t.templateCategory == category && t.isDefault) {
        return t.id;
      }
    }
    return null;
  }

  // ⚠️ **المِزلاجُ يُقرأ من الـDAO نفسِه** لا يُعاد حسابُه هنا: شاشةُ الحسم
  // تدّعي أنّها تصف ما يقع على الورق، فمنطقان متوازيان يعنيان شاشةً تُطمئن
  // على قالبٍ آخر. وهو `null` لكلِّ نوعٍ سوى `sales_receipt`.
  final quickSaleIds = <String, int?>{
    for (final type in TemplateResolver.documentTypes)
      type: await db.quickSaleTemplateIdFor(type),
  };

  // القرارُ الأوّل: احسم كلَّ نوعٍ، ثمّ اقرأ التصادماتِ من الحصيلة. فتقاسمُ
  // افتراضيِّ الفئة لا يُعرَف إلّا بعد أن يُحسم الجميع.
  final resolutions = <String, TemplateResolution>{};
  for (final type in TemplateResolver.documentTypes) {
    final ctx = TemplateResolver.documentContexts[type];
    if (ctx == null) continue;
    resolutions[type] = TemplateResolver.resolve(
      documentType: type,
      category: ctx.category,
      bindings: rules,
      branchId: branchId,
      locale: locale,
      quickSaleTemplateId: quickSaleIds[type],
      categoryDefaultTemplateId: categoryDefault(ctx.type, ctx.category),
    );
  }

  // كم نوعاً يحطّ على كلِّ قالبٍ **بمستوى الفئة**؟ اثنان فأكثرُ تصادم.
  final sharedAtCategoryLevel = <int, int>{};
  for (final r in resolutions.values) {
    if (r.level == 6 && r.templateId != null) {
      sharedAtCategoryLevel[r.templateId!] =
          (sharedAtCategoryLevel[r.templateId!] ?? 0) + 1;
    }
  }

  final rows = <PrintResolutionRow>[];
  for (final type in TemplateResolver.documentTypes) {
    final ctx = TemplateResolver.documentContexts[type];
    final resolution = resolutions[type];
    if (ctx == null || resolution == null) continue;

    final template =
        resolution.templateId == null ? null : byId[resolution.templateId];

    // الرابطةُ الفائزةُ — منها تُقرأ الطابعةُ وعددُ النُّسخ. وغيابُها يعني
    // حسماً بالفئة أو بالمدمج، فالطابعةُ تُختار وقت الطباعة.
    final winning = resolution.level <= 4
        ? rules.where((b) =>
            b.documentType == type && b.templateId == resolution.templateId)
        : const <BindingRule>[];
    final printerId =
        winning.isEmpty ? null : winning.first.printerId;
    final printer = printerId == null ? null : printerById[printerId];

    // عرضُ الطابعة غيرُ مسجَّلٍ في `Printers` — فالفحصُ يقع على ما يُعرف
    // يقيناً وحدَه: طابعةٌ حراريّةٌ لا تتجاوز ٨٠مم، فقالبُ A4 عليها فقدُ
    // بيانٍ مؤكَّد. وما دون ذلك لا يُحكَم عليه بالظنّ.
    final fit = (printer != null &&
            printer.printerType == 'thermal' &&
            template != null)
        ? checkPaperFit(
            templateWidthMm: template.paperWidth,
            printerWidthMm: _thermalMaxWidthMm,
          ).fit
        : PaperFit.ok;

    rows.add(PrintResolutionRow(
      documentType: type,
      documentLabel: documentTypeLabel(type),
      category: ctx.category,
      templateId: resolution.templateId,
      templateName: template?.name ?? '—',
      paperLabel: template == null
          ? '—'
          : paperLabelFor(template.paperWidth, template.paperHeight),
      printerName: printer?.name,
      printerNote: printer == null
          ? 'تُختار وقت الطباعة'
          : [printer.port ?? printer.ipAddress ?? printer.printerType]
              .join(' · '),
      copies: resolution.copies,
      directPrint: resolution.directPrint,
      level: resolution.level,
      health: classifyResolution(
        level: resolution.level,
        wired: TemplateResolver.wiredDocumentTypes.contains(type),
        sharesCategoryDefault: resolution.level == 6 &&
            (sharedAtCategoryLevel[resolution.templateId] ?? 0) > 1,
        fit: fit,
      ),
      chain: [
        for (final s in TemplateResolver.explain(
          documentType: type,
          category: ctx.category,
          bindings: rules,
          branchId: branchId,
          locale: locale,
          quickSaleTemplateId: quickSaleIds[type],
          categoryDefaultTemplateId: categoryDefault(ctx.type, ctx.category),
        ))
          ResolutionStepView(
            level: s.level,
            label: s.label,
            key: s.key,
            state: s.state,
            result: switch (s.state) {
              ResolutionStepState.matched => s.templateId == null
                  ? '← التصميم المدمج في الكود'
                  : '← ${byId[s.templateId]?.name ?? 'قالب #${s.templateId}'}',
              ResolutionStepState.missed => 'لا قاعدة مطابقة',
              ResolutionStepState.notTried => 'لم يُجرَّب',
            },
          ),
      ],
    ));
  }

  return rows;
});

/// أعرضُ ما تطبعه طابعةٌ حراريّةٌ شائعة. ٨٠مم هو **السقف** لا المقاسُ
/// المؤكَّد: طابعةُ ٥٨مم تمرّ من هذا الفحص، فهو ينقص ولا يكذب.
const double _thermalMaxWidthMm = 80;

/// الصفُّ المحدَّد — أو أوّلُ صفٍّ حين لا اختيار.
final selectedResolutionRowProvider =
    Provider.autoDispose<PrintResolutionRow?>((ref) {
  final rows =
      ref.watch(printResolutionRowsProvider).value ?? const <PrintResolutionRow>[];
  if (rows.isEmpty) return null;
  final type = ref.watch(selectedDocumentTypeProvider);
  if (type == null) return rows.first;
  for (final r in rows) {
    if (r.documentType == type) return r;
  }
  return rows.first;
});

/// فروعُ شريط الترشيح — «كل الفروع» ثمّ ما في القاعدة.
final resolutionBranchOptionsProvider =
    Provider.autoDispose<List<({int? id, String label})>>((ref) {
  final branches = ref.watch(allBranchesProvider).value ?? const <Branche>[];
  return [
    (id: null, label: 'كل الفروع'),
    for (final b in branches) (id: b.id, label: b.name),
  ];
});
