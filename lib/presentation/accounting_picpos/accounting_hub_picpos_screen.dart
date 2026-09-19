import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/navigation/screen_id.dart';
import '../../core/theme/app_colors.dart';
import '../../data/providers/auth_providers.dart';
import '../picpos_shell/picpos_empty_state.dart';
import '../widgets/auth/security_gate_wrapper.dart';
import 'account_mapping_picpos_screen.dart';
import 'bank_reconciliation_picpos_screen.dart';
import 'chart_of_accounts_picpos_screen.dart';
import 'cost_centers_picpos_screen.dart';
import 'financial_statements_picpos_screen.dart';
import 'general_ledger_picpos_screen.dart';
import 'journal_entries_picpos_screen.dart';
import 'journal_templates_picpos_screen.dart';
import '../picpos_shell/picpos_surface.dart';

/// حاويةُ «الحسابات» — مدخلٌ واحدٌ في القائمة الجانبيّة يفتح تسعةَ تبويبات.
///
/// التصميمُ المرجعُ PicPos-Accounting-remote-2026-08-22.dc.html: مصفوفةُ
/// TABS فيه **سبعةٌ** (coa · cc · je · gl · tb · tpl · map)، و«الحسابات»
/// اسمُ المدخل في NAV لا تبويبٌ ثامن. والشريطُ السفليُّ (48px) يحمل
/// الاسمَ ثمّ الشرائحَ السبع.
///
/// ⚠️ «الخزينة» مدخلٌ مستقلٌّ في تصميم NAV ولا تُطوى هنا.
///
/// كلُّ تبويبٍ يحتفظ بشاشتِه كما هي — المفروكةُ بهويّة PicPos والمشتركةُ
/// بتصميمِها القديم — فلا شاشةَ تفقد بلوغَها بالطيّ. وتُستبدَل المشتركةُ
/// بفوركِها تباعاً (مهمّةُ الشاشات الباقية).
enum AccountingTab {
  coa('دليل الحسابات', PhosphorIconsBold.treeStructure, 'settings_view',
      ScreenId.chartOfAccounts),
  cc('مراكز التكلفة', PhosphorIconsBold.crosshair, 'settings_view',
      ScreenId.costCenters),
  je(journalEntriesScreenLabel, PhosphorIconsBold.notebook, 'settings_view',
      ScreenId.journalEntries),
  gl('دفتر الأستاذ', PhosphorIconsBold.book, 'settings_view',
      ScreenId.generalLedger),
  // ⚠️ `screenId` هنا `null` عن قصد: «ميزان المراجعة» لم يكن له مدخلُ
  //    قائمةٍ قطّ — كان تبويباً أوّلَ داخلَ «القوائم المالية». فالمدخلُ
  //    المطويُّ `ScreenId.financialStatements` يحمله التبويبُ `fs` أدناه،
  //    وهو ما يقيس عليه حارسُ البلوغ.
  tb('ميزان المراجعة', PhosphorIconsBold.scales, 'reports_view', null),
  tpl('قوالب القيود', PhosphorIconsBold.stack, 'settings_view', null),
  map('ربط الحسابات', PhosphorIconsBold.link, 'settings_view',
      ScreenId.accountMapping),

  /// ثامنٌ لا يعرفه التصميم — قرارُ مالك 2026-08-27.
  ///
  /// تصميمُ `TABS` سبعةٌ ولا موضعَ فيها للقوائم الخمسِ الأخرى (‏قائمةُ
  /// الدخل · الميزانيّةُ · التدفّقاتُ · تقادمُ الذمم · مطابقةُ الترحيل).
  /// وكانت مطويّةً خلفَ شريحة `tb` فتُنتج **تبويباتٍ داخلَ تبويبات**.
  /// فاختار المالكُ شريحةً ثامنةً على إخراجها إلى مدخلٍ مستقلّ: المدخلُ
  /// يبقى واحداً، والتبويبُ داخلَ التبويب يزول.
  fs('القوائم المالية', PhosphorIconsBold.chartLineUp, 'reports_view',
      ScreenId.financialStatements),

  /// تاسعٌ لا يعرفه التصميم — قرارُ مالك 2026-09-01.
  ///
  /// المحرّكُ كان جاهزاً والمستودعُ يحجبه، والشاشةُ القديمةُ محاكاةً بحوارَين
  /// كاذبَين. والبديلُ مدخلٌ جانبيٌّ عاشرٌ في مجموعةٍ فيها تسعةٌ — فاختير
  /// إبقاءُ المدخل واحداً.
  bank('المطابقة البنكية', PhosphorIconsBold.bank, 'settings_view',
      ScreenId.bankReconciliation);

  const AccountingTab(this.label, this.icon, this.permission, this.screenId);

  final String label;
  final IconData icon;

  /// كودُ الصلاحية الذي يحرس التبويب — مطابقٌ لما يربطه
  /// screenPermissionMap بشاشةِ التبويب قبل الطيّ.
  final String permission;

  /// الشاشةُ المطويّةُ التي يحملها التبويب — يقيس عليها الحارسُ أنّ كلَّ
  /// مدخلٍ طُوي ما زال مبلوغاً.
  ///
  /// `null` لـ tpl وحدَه: «قوالبُ القيود» لم يكن لها مدخلُ قائمةٍ ولا
  /// `ScreenId` قبل الحاوية — تُفتَح بدفعةٍ من دفتر اليومية (وما زالت).
  final ScreenId? screenId;

  /// الشاشةُ التي يعرضها التبويب.
  ///
  /// ⚠️ je و gl كانتا محروستَين بكلمة مرورٍ عبر [SecurityScreenGate] في
  /// app_main_screen.dart — والحراسةُ تُنقَل معهما هنا حرفاً بحرف، وإلّا
  /// أسقط الطيُّ ضابطَ أمانٍ قائماً بصمت.
  Widget build() => switch (this) {
        AccountingTab.coa => const ChartOfAccountsPicPosScreen(),
        AccountingTab.cc => const CostCentersPicPosScreen(),
        AccountingTab.je => const SecurityScreenGate(
            settingKey: 'accounting_access_password',
            title: journalEntriesScreenLabel,
            child: JournalEntriesPicPosScreen(),
          ),
        AccountingTab.gl => const SecurityScreenGate(
            settingKey: 'accounting_access_password',
            title: 'دفتر الأستاذ',
            child: GeneralLedgerPicPosScreen(),
          ),
        AccountingTab.tb => const FinancialStatementsPicPosScreen(
            view: FinancialStatementsView.trialBalance,
          ),
        AccountingTab.tpl => const JournalTemplatesPicPosScreen(),
        AccountingTab.map => const AccountMappingPicPosScreen(),
        AccountingTab.fs => const FinancialStatementsPicPosScreen(
            view: FinancialStatementsView.statements,
            // ‏١ = قائمةُ الدخل، وهي أوّلُ ما يُعرَض هنا. و`0` كان سيُطلَب
            //    تبويباً غيرَ معروضٍ فيرتدّ إلى الأوّل — يعمل، لكنّه يُخفي
            //    القصدَ خلف ارتداد.
            initialTabIndex: 1,
          ),
        AccountingTab.bank => const BankReconciliationPicposScreen(),
      };
}

class AccountingHubPicPosScreen extends ConsumerStatefulWidget {
  const AccountingHubPicPosScreen({super.key, this.initialTab});

  /// تبويبٌ يُفتَح ابتداءً — للبلوغ المباشر من مكانٍ آخر في التطبيق.
  final AccountingTab? initialTab;

  @override
  ConsumerState<AccountingHubPicPosScreen> createState() =>
      _AccountingHubPicPosScreenState();
}

class _AccountingHubPicPosScreenState
    extends ConsumerState<AccountingHubPicPosScreen> {
  AccountingTab? _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.initialTab;
  }

  @override
  Widget build(BuildContext context) {
    final permsAsync = ref.watch(currentUserPermissionsProvider);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: permsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          // خطأُ قراءةِ الصلاحيات لا يفتح البابَ ولا يُقفله كلَّه: الحاويةُ
          // نفسُها محروسةٌ بـ screenPermissionMap قبل الوصول إلى هنا، فنعرض
          // التبويباتِ على صلاحيةِ الحاوية وحدَها.
          error: (_, _) => _buildTabs(const {'settings_view'}),
          data: (perms) => _buildTabs(perms.toSet()),
        ),
      ),
    );
  }

  Widget _buildTabs(Set<String> perms) {
    final allowed = AccountingTab.values
        .where((t) => perms.contains(t.permission))
        .toList();

    if (allowed.isEmpty) {
      return const PicPosEmptyState(
        icon: PhosphorIconsBold.bookOpen,
        title: 'لا تبويباتِ حساباتٍ متاحة',
        hint: 'صلاحيّاتُك الحاليّةُ لا تفتح أيّاً من تبويبات الحسابات.',
      );
    }

    // التبويبُ المختارُ قد يسقط من المسموح (تغيّرُ صلاحيّةٍ أثناء الجلسة)،
    // فنرتدّ إلى أوّلِ متاحٍ بدل شاشةٍ فارغة.
    final current = (_selected != null && allowed.contains(_selected))
        ? _selected!
        : allowed.first;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _AccountingTabStrip(
          tabs: allowed,
          current: current,
          onSelect: (t) => setState(() => _selected = t),
        ),
        Expanded(
          // مفتاحٌ لكلّ تبويبٍ حتى لا تتسرّب حالةُ شاشةٍ إلى أختِها عند
          // التبديل (بحثٌ أو صفحةٌ محفوظةٌ من التبويب السابق).
          child: KeyedSubtree(
            key: ValueKey(current),
            child: current.build(),
          ),
        ),
      ],
    );
  }
}

/// شريطُ التبويبات — 48px، اسمُ الحاوية ثمّ الشرائح، على تصميم «Accounting
/// sub-nav». يمرّر أفقيّاً على الشاشات الضيّقة بدل أن يفيض.
class _AccountingTabStrip extends StatelessWidget {
  const _AccountingTabStrip({
    required this.tabs,
    required this.current,
    required this.onSelect,
  });

  final List<AccountingTab> tabs;
  final AccountingTab current;
  final ValueChanged<AccountingTab> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: context.picposCard,
        border: Border(bottom: BorderSide(color: context.picposHairline)),
      ),
      child: Row(
        children: [
          const SizedBox(width: 20),
          const Icon(PhosphorIconsBold.bookOpen,
              size: 15, color: AppColors.textMuted),
          const SizedBox(width: 7),
          Text(
            'الحسابات',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: AppColors.textMuted,
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final t in tabs) ...[
                    _TabChip(
                      tab: t,
                      selected: t == current,
                      onTap: () => onSelect(t),
                    ),
                    const SizedBox(width: 6),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(width: 20),
        ],
      ),
    );
  }
}

class _TabChip extends StatelessWidget {
  const _TabChip({
    required this.tab,
    required this.selected,
    required this.onTap,
  });

  final AccountingTab tab;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? AppColors.primary : AppColors.textSecondary;
    return Material(
      color: selected
          ? AppColors.primary.withValues(alpha: 0.10)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(9),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(9),
        child: Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(9),
            border: Border.all(
              color: selected ? AppColors.primary : context.picposHairline,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(tab.icon, size: 14, color: fg),
              const SizedBox(width: 6),
              Text(
                tab.label,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: fg,
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
