// المعاينةُ والطباعةُ التجريبيّة — تصميمُ `PicPos Template Print Test.dc.html`.
//
// ── ما تحلّه ──────────────────────────────────────────────────────────────
// القالبُ يُكتب على فاتورةٍ متوسّطةٍ ثمّ يُطبع على فاتورةٍ باثنين وأربعين
// صنفاً، فيُدهَس نطاقُ المجاميع أو تُقصّ الحافّة — ولا يُكتشف ذلك إلّا على
// ورق عميل. وهذه الشاشةُ تُخرجه قبل ذلك.
//
// ── وزرُّ الطباعة **يرفض** على الفحص الأحمر ─────────────────────────────
// عقدُ الأزرار §٣: «الغرضُ من الشاشة منعُ الورق المعطوب لا إنتاجُه». والفحوصُ
// مقيسةٌ من خطّة الرسم في [probePrintout] — لا قائمةٌ مكتوبةٌ بجانب كلِّ
// حالة، فالرفضُ يقع على العطب لا على اسم الحالة.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../data/providers/print_test_providers.dart';
import '../../../domain/models/picpos_template_card.dart';
import '../../../domain/printing/print_probe.dart';
import '../../../domain/printing/print_test_scenarios.dart';
import '../../picpos_shell/picpos_content_card.dart';
import '../../picpos_shell/picpos_empty_state.dart';
import '../../picpos_shell/picpos_screen_scaffold.dart';
import '../../picpos_shell/picpos_section_header.dart';
import '../../picpos_shell/picpos_surface.dart';
import '../widgets/sheet_preview_view.dart';

/// اللوحتان تُطويان تحت هذا العرض وتبقى الورقةُ وحدَها.
const double _sidePanelWidth = 320;
const double _threePaneMinWidth = 1400;
const double _twoPaneMinWidth = 1000;

class PrintTestPicposScreen extends ConsumerStatefulWidget {
  const PrintTestPicposScreen({super.key, this.templateId});

  /// القالبُ المفتوحُ عليه — يمرّره زرُّ «طباعة تجريبية» في المكتبة.
  final int? templateId;

  @override
  ConsumerState<PrintTestPicposScreen> createState() =>
      _PrintTestPicposScreenState();
}

class _PrintTestPicposScreenState
    extends ConsumerState<PrintTestPicposScreen> {
  @override
  void initState() {
    super.initState();
    final id = widget.templateId;
    if (id != null) {
      // بعدَ أوّلِ إطار: الكتابةُ في مزوِّدٍ أثناء `initState` تُلقي.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(printTestTemplateProvider.notifier).set(id);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final templates = ref.watch(printTestTemplatesProvider);
    final selectedId = ref.watch(printTestTemplateProvider);
    final resultAsync = ref.watch(printTestResultProvider);
    final result = resultAsync.value;

    // لا قالبَ مختاراً ⇒ أوّلُ ما في المكتبة، كي لا تُفتَح الشاشةُ فارغة.
    if (selectedId == null && templates.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (ref.read(printTestTemplateProvider) == null) {
          ref.read(printTestTemplateProvider.notifier).set(templates.first.id);
        }
      });
    }

    return PicPosScreenScaffold(
      title: 'معاينة وطباعة تجريبية',
      subtitle: 'نفس الراسم الذي يطبع — لا معاينة موازية · '
          'اختبر الحالات الحدّية قبل التفعيل',
      icon: PhosphorIconsBold.testTube,
      headerActions: [
        OutlinedButton.icon(
          onPressed: result == null ? null : () => _savePdf(result),
          icon: const Icon(PhosphorIconsBold.filePdf, size: 17),
          label: const Text('حفظ PDF'),
        ),
        const SizedBox(width: 8),
        FilledButton.icon(
          onPressed: result == null ? null : () => _print(result),
          icon: const Icon(PhosphorIconsBold.printer, size: 17),
          label: const Text('طباعة تجريبية'),
        ),
      ],
      body: LayoutBuilder(
        builder: (context, box) {
          final sheets = _Sheets(result: result, loading: resultAsync.isLoading);

          if (box.maxWidth < _twoPaneMinWidth) return sheets;

          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: _sidePanelWidth,
                child: _CasesPanel(templates: templates),
              ),
              const SizedBox(width: 12),
              Expanded(child: sheets),
              if (box.maxWidth >= _threePaneMinWidth) ...[
                const SizedBox(width: 12),
                SizedBox(
                  width: _sidePanelWidth,
                  child: _FindingsPanel(result: result),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  void _print(PrintTestResult result) {
    // ⚠️ الرفضُ على الأحمر — وهو **الغرضُ** من الشاشة لا قيدٌ عليها.
    if (result.isBlocked) {
      AppToast.show(
        context,
        'الطباعة موقوفة: ${result.failCount} فحصاً فاشلاً — '
        'الطبعُ عليها يُنتج ورقاً معطوباً',
        type: ToastType.error,
      );
      return;
    }
    AppToast.show(
      context,
      '${result.pages.length} صفحةً جاهزة'
      '${result.warnCount > 0 ? ' · ${result.warnCount} تنبيهاً يُراجَع على الورق' : ''}'
      ' — والمستند موسومٌ «تجريبي» فلا يُسجَّل ولا يُرسَل للمنظومة الضريبية',
      type: result.warnCount > 0 ? ToastType.warning : ToastType.success,
    );
  }

  void _savePdf(PrintTestResult result) {
    AppToast.show(
      context,
      '${result.templateName} — ${result.pages.length} صفحةً بمقاس '
      '${result.paperWidthMm.toStringAsFixed(0)}مم',
      type: ToastType.success,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════

class _CasesPanel extends ConsumerWidget {
  const _CasesPanel({required this.templates});

  final List<TemplateCard> templates;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scenarios = ref.watch(printScenariosProvider);
    final selectedScenario = ref.watch(printTestScenarioProvider);
    final selectedTemplate = ref.watch(printTestTemplateProvider);
    final printers = ref.watch(printTestPrintersProvider).value ?? const [];
    final target = ref.watch(printTestTargetProvider);

    return PicPosContentCard(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          const PicPosSectionHeader(
            title: 'القالب المفحوص',
            subtitle: 'الورقُ خاصّةُ القالب — فاختره لا الحالة',
            icon: PhosphorIconsBold.files,
          ),
          for (final t in templates)
            _PickRow(
              icon: PhosphorIconsBold.fileText,
              title: t.name,
              sub: '${t.paperLabel} · ${t.elementCount} عنصراً',
              selected: t.id == selectedTemplate,
              onTap: () =>
                  ref.read(printTestTemplateProvider.notifier).set(t.id),
            ),
          const PicPosSectionHeader(
            title: 'حالات الاختبار',
            subtitle: 'كل حالة تكسر افتراضاً مختلفاً في القالب',
            icon: PhosphorIconsBold.listChecks,
          ),
          for (final s in scenarios)
            _PickRow(
              icon: s.risky
                  ? PhosphorIconsBold.warning
                  : PhosphorIconsBold.checkCircle,
              iconTone: s.risky ? AppColors.warning : AppColors.success,
              title: s.name,
              sub: s.probe,
              selected: s.id == selectedScenario,
              onTap: () =>
                  ref.read(printTestScenarioProvider.notifier).set(s.id),
            ),
          const PicPosSectionHeader(
            title: 'وجهة الطباعة',
            subtitle: 'الحراريّةُ تُفحص ضدّ عرضها',
            icon: PhosphorIconsBold.printer,
          ),
          _PickRow(
            icon: PhosphorIconsBold.filePdf,
            title: 'حفظ كملف PDF',
            sub: 'بلا طابعة — للمراجعة',
            selected: target == null,
            onTap: () => ref.read(printTestTargetProvider.notifier).set(null),
          ),
          for (final p in printers)
            _PickRow(
              icon: p.printerType == 'thermal'
                  ? PhosphorIconsBold.receipt
                  : PhosphorIconsBold.printer,
              title: p.name,
              sub: [
                p.printerType,
                if (p.port != null) p.port!,
                if (p.ipAddress != null) p.ipAddress!,
              ].join(' · '),
              selected: target == p.id,
              onTap: () =>
                  ref.read(printTestTargetProvider.notifier).set(p.id),
            ),
        ],
      ),
    );
  }
}

class _PickRow extends StatelessWidget {
  const _PickRow({
    required this.icon,
    required this.title,
    required this.sub,
    required this.selected,
    required this.onTap,
    this.iconTone,
  });

  final IconData icon;
  final String title;
  final String sub;
  final bool selected;
  final VoidCallback onTap;
  final Color? iconTone;

  @override
  Widget build(BuildContext context) {
    final tone = iconTone ?? context.picposBrandInk;
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? context.picposBrandInk.withValues(alpha: 0.08)
              : Colors.transparent,
          border: BorderDirectional(
            bottom: BorderSide(color: context.picposHairline),
            start: BorderSide(
              color: selected ? context.picposBrandInk : Colors.transparent,
              width: 3,
            ),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: tone.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(icon, size: 15, color: tone),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                          color: context.picposText)),
                  Text(sub,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          height: 1.45,
                          color: context.picposMuted)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Sheets extends StatelessWidget {
  const _Sheets({required this.result, required this.loading});

  final PrintTestResult? result;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    if (loading && result == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final r = result;
    if (r == null) {
      return const PicPosEmptyState(
        icon: PhosphorIconsBold.testTube,
        title: 'اختر قالباً لمعاينته',
        hint: 'تُرسم الورقةُ بالمحرّك نفسِه الذي يطبع',
      );
    }

    if (r.pages.isEmpty) {
      return PicPosEmptyState(
        icon: PhosphorIconsBold.warningOctagon,
        title: 'لم تنتج الورقةُ صفحةً واحدة',
        hint: r.error ?? 'القالبُ بلا عناصرَ ظاهرة',
      );
    }

    return Container(
      decoration: BoxDecoration(
        // مكتبُ العرض — أغمقُ من الأرضيّة كي تنفصل الورقةُ البيضاءُ عنه.
        color: context.picposIsDark
            ? const Color(0xFF060C16)
            : const Color(0xFFE2E8F2),
        borderRadius: BorderRadius.circular(14),
      ),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (final p in r.pages) ...[
                SheetPreviewView(
                  widthMm: p.page.widthMm,
                  heightMm: p.page.heightMm,
                  ops: p.ops,
                  caption: 'صفحة ${p.page.pageNumber} من ${p.page.pageCount}'
                      ' · ${p.page.widthMm.toStringAsFixed(0)}مم',
                ),
                const SizedBox(width: 20),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _FindingsPanel extends StatelessWidget {
  const _FindingsPanel({required this.result});

  final PrintTestResult? result;

  @override
  Widget build(BuildContext context) {
    final r = result;
    if (r == null) {
      return const PicPosContentCard(
        child: PicPosEmptyState(
          icon: PhosphorIconsBold.listChecks,
          title: 'لا مطبوعَ يُفحص',
          hint: 'اختر قالباً وحالةَ بيانات',
        ),
      );
    }

    final (badge, badgeTone) = r.failCount > 0
        ? ('${r.failCount} فشل', AppColors.error)
        : r.warnCount > 0
            ? ('${r.warnCount} تنبيه', AppColors.warning)
            : ('كل الفحوص سليمة', AppColors.success);

    return PicPosContentCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PicPosSectionHeader(
            title: 'فحوص المطبوع',
            subtitle: 'مقيسةٌ من خطّة الرسم لا مكتوبةٌ بجانبها',
            icon: PhosphorIconsBold.listChecks,
            actions: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(
                  color: badgeTone.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(badge,
                    style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        color: badgeTone)),
              ),
            ],
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              itemCount: r.checks.length,
              itemBuilder: (context, i) => _CheckRow(check: r.checks[i]),
            ),
          ),
        ],
      ),
    );
  }
}

class _CheckRow extends StatelessWidget {
  const _CheckRow({required this.check});

  final PrintCheck check;

  @override
  Widget build(BuildContext context) {
    final (icon, tone) = switch (check.level) {
      ProbeLevel.pass => (PhosphorIconsBold.checkCircle, AppColors.success),
      ProbeLevel.warn => (PhosphorIconsBold.warning, AppColors.warning),
      ProbeLevel.fail => (PhosphorIconsBold.xCircle, AppColors.error),
    };

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 9),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: context.picposHairline)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icon, size: 15, color: tone),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(check.title,
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: context.picposText)),
                const SizedBox(height: 2),
                Text(check.note,
                    style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        height: 1.6,
                        color: context.picposMuted)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
