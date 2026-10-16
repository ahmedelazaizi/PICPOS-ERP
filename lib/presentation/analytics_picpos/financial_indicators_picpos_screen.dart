// «المؤشرات والنسب المالية» — PicPos وحدَها. يعرض مخرجاتِ محرّك التحليل
// المالي (`lib/domain/analytics`) كما هي: بطاقاتُ المؤشّرات، ملخّصُ المخاطر،
// وست مجموعات من النسب. قراءةٌ فقط، ولا يكتب شيئاً.
//
// الصلاحيةُ: `reports_view` (نفسُ القوائم المالية) — راجع `screenPermissionMap`.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n/tr.dart';
import '../../data/providers/providers.dart' show branchScopeProvider;
import '../picpos_shell/picpos_empty_state.dart';
import '../picpos_shell/picpos_screen_scaffold.dart';
import '../widgets/async_value_widget.dart';
import '../widgets/report_components.dart' show DateRangeFilter;
import 'fin_analytics_state.dart';
import 'fin_filter_bar.dart';
import 'fin_indicators_body.dart';

class FinancialIndicatorsPicPosScreen extends ConsumerStatefulWidget {
  const FinancialIndicatorsPicPosScreen({super.key});

  @override
  ConsumerState<FinancialIndicatorsPicPosScreen> createState() =>
      _FinancialIndicatorsPicPosScreenState();
}

class _FinancialIndicatorsPicPosScreenState
    extends ConsumerState<FinancialIndicatorsPicPosScreen> {
  // نفسُ افتراضيّ شاشة القوائم: أوّلُ الشهر حتى نهاية اليوم (يومٌ كاملٌ شاملٌ).
  DateTime _from = DateRangeFilter.normalizeStart(
      DateTime(DateTime.now().year, DateTime.now().month, 1));
  DateTime _to = DateRangeFilter.normalizeEnd(DateTime.now());
  int? _branchId; // null = كل الفروع المسموحة

  FinIndicatorsParams get _params =>
      (from: _from, to: _to, branchId: _branchId);

  Future<void> _pickRange() async {
    final picked = await showDateRangePicker(
      context: context,
      initialDateRange: DateTimeRange(start: _from, end: _to),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _from = DateRangeFilter.normalizeStart(picked.start);
      _to = DateRangeFilter.normalizeEnd(picked.end);
    });
  }

  void _refresh() => ref.invalidate(finIndicatorsProvider(_params));

  void _retryScope() => ref.invalidate(branchScopeProvider);

  @override
  Widget build(BuildContext context) {
    final title = tr('المؤشرات والنسب المالية');
    final subtitle =
        tr('الأداء والسيولة والربحية والكفاءة والرافعة من القيود المرحَّلة');
    // نطاقُ الفروع يُحسم **قبل** أيّ شريطٍ أو جلبِ بيانات: أثناء التحميل أو بعد
    // الخطأ لا تُعرَض أسماءُ فروعٍ ولا أرقام، ونطاقٌ محسومٌ بلا قيد يعني «الكل».
    final scopeAsync = ref.watch(branchScopeProvider);
    final scope = scopeAsync.asData?.value;
    if (scope == null || scope.isEmptyScope) {
      return PicPosScreenScaffold(
        title: title,
        subtitle: subtitle,
        icon: Icons.insights_outlined,
        body: scopeAsync.hasError
            ? AppErrorWidget(
                message: tr('تعذر تحديد الفروع المسموحة لحسابك'),
                onRetry: _retryScope,
              )
            : scope == null
                ? const AppLoadingIndicator()
                : PicPosEmptyState(
                    icon: Icons.lock_outline,
                    title: tr('لا فروعَ مُسنَدةٌ لحسابك'),
                    hint: tr('اطلب من مدير النظام إسنادَ فرعٍ واحدٍ على الأقل لحسابك ليظهر لك التحليل المالي.'),
                  ),
      );
    }
    final result = ref.watch(finIndicatorsProvider(_params));
    return PicPosScreenScaffold(
      title: title,
      subtitle: subtitle,
      icon: Icons.insights_outlined,
      toolbar: FinancialFilterBar(
        from: _from,
        to: _to,
        branchId: _branchId,
        onPickRange: _pickRange,
        onBranchChanged: (v) => setState(() => _branchId = v),
        onRefresh: _refresh,
      ),
      body: AsyncValueWidget(
        value: result,
        showPreviousOnLoading: false,
        loading: AppLoadingIndicator(message: tr('جارٍ احتساب المؤشرات...')),
        error: (_, _) => AppErrorWidget(
          message: tr('تعذر احتساب المؤشرات المالية'),
          onRetry: _refresh,
        ),
        data: (r) =>
            FinancialIndicatorsBody(result: r, onChangePeriod: _pickRange),
      ),
    );
  }
}
