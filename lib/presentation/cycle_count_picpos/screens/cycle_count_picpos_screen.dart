import 'package:picpos_erp/core/i18n/tr.dart';
import 'package:picpos_erp/core/theme/app_colors.dart';
// شاشة الجرد الميداني بهوية PicPos — semi-modular fork.
//
// الأصل: lib/presentation/screens/cycle_count_screen.dart (613 سطر).
// الكنترولر (`cycleCountControllerProvider` وتوابعه `CycleCountState`/
// `CycleCountController`) مفصول في cycle_count/cycle_count_controller.dart
// ومُعاد استخدامه هنا (import، بلا نسخ منطقه). أما طبقة الـ UI (دوال البناء
// داخل الـ State + الحوارات) فمكتوبة inline في ملف الشاشة الأصل بلا `part
// of`، فبينُسخ جسمها هنا حرفياً بلا أي تعديل منطقي (مصيدة النسخ §٥.٨) —
// أي إصلاح منطقي (بما فيه أي تعليق Spec 147 / BUG-B / BUG-C) يروح للأصل
// (cycle_count_screen.dart) أولاً ثم يتنقل بـ patch. يتغيّر هنا فقط اسم
// الكلاس/الـ State وطبقة العرض العلوية (`PicPosScreenScaffold` بدل
// Scaffold خام + FloatingActionButton؛ الـ TabBar بتنقل subHeader والـ
// TabBarView بتنقل body وزر الإضافة الحساس للتبويب بينقل toolbar).
//
// الفورك بيستورد data/database/database.dart زي الأصل المسموح له بالفعل في
// guard الاستيراد (D4-001) — لأن دوال البناء المنسوخة بتاخد db.* كباراميترات
// مباشرة (db.CycleCountPlanData / db.CycleCountTaskData /
// db.CycleCountItemView). ده أضاف مسار الفورك لنفس allowlist في
// test/unit/presentation_db_import_guard_test.dart (خيار (2) المصرّح به من
// الـ guard نفسه، بجانب مدخل الأصل).
//
// راجع lib/presentation/screens/cycle_count_screen.dart (الأصل) و
// lib/presentation/screens/cycle_count/cycle_count_controller.dart (الكنترولر
// المُعاد استخدامه).
//
// التقسيم حسب المسؤولية (حد حجم الملف 30KB) عبر `part` + extension على الـ State:
//   cycle_count_picpos_plans_part.dart      — تبويب الخطط وبطاقاتها
//   cycle_count_picpos_tasks_part.dart      — تبويب المهام وبنود العدّ
//   cycle_count_picpos_analytics_part.dart  — تبويب التحليلات
//   cycle_count_picpos_dialogs_part.dart    — حوارات إنشاء الخطة/المهمة
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:intl/intl.dart';
import '../../../data/database/database.dart' as db;
import '../../../data/providers/providers.dart';
import '../../../domain/repositories/cycle_count_repository.dart';
import '../../../services/network_service.dart';
import '../../../core/widgets/app_toast.dart';
import '../../screens/cycle_count/cycle_count_controller.dart';
import '../../picpos_shell/picpos_screen_scaffold.dart';
import '../../picpos_shell/picpos_toolbar.dart';

part 'cycle_count_picpos_plans_part.dart';
part 'cycle_count_picpos_tasks_part.dart';
part 'cycle_count_picpos_analytics_part.dart';
part 'cycle_count_picpos_dialogs_part.dart';

final _fmt = NumberFormat('#,##0.00', 'ar');

/// شاشة الجرد الميداني بهوية PicPos. تُختار بالعلامة في app_main_screen
/// (`Brand.isPicPos`). FULL PARITY مع الأصل: التبويبات الثلاثة
/// (الخطط/المهام/التحليلات)، بطاقات الخطط وحوار إنشاء خطة، لوحة العدّ لكل
/// مهمة (بما فيها flush الكميات المكتوبة قبل الإكمال وحارس منع الاعتماد من
/// جهاز عميل/مرآة وحارس منع الإكمال المزدوج)، تبويب التحليلات، وزر الإضافة
/// السياقي (خطة جديدة / مهمة جديدة / بلا زر في التحليلات).
class CycleCountPicposScreen extends ConsumerStatefulWidget {
  const CycleCountPicposScreen({super.key});

  @override
  ConsumerState<CycleCountPicposScreen> createState() =>
      _CycleCountPicposScreenState();
}

class _CycleCountPicposScreenState extends ConsumerState<CycleCountPicposScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Spec 147 (S-COUNT): R2 double-submission guard for the atomic finalize.
  // State field (survives rebuilds) — a double-tap on «إكمال» must not
  // apply/post the count twice.
  bool _finalizing = false;

  // BUG-C: hold the per-item count controllers in State (keyed by item id) so a
  // typed-but-not-Enter value survives rebuilds and can be flushed to the DB
  // before finalize. Recreating them each build (the old code) meant clicking
  // «إكمال» without pressing Enter first silently dropped the count → finalize
  // adjusted nothing while still toasting success.
  final Map<int, TextEditingController> _countCtrls = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    // Context-sensitive add action (toolbar) must rebuild its label/handler
    // when the active tab changes — PicPosScreenScaffold has no FAB slot, so
    // this replaces the original's per-tab FloatingActionButton.extended.
    _tabController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _tabController.dispose();
    for (final c in _countCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final repo = ref.watch(cycleCountRepositoryProvider);
    final state = ref.watch(cycleCountControllerProvider);
    final notifier = ref.read(cycleCountControllerProvider.notifier);

    return PicPosScreenScaffold(
      title: tr('الجرد الميداني'),
      subtitle: tr('خطط ومهام جرد المخزون'),
      icon: PhosphorIconsBold.clipboardText,
      subHeader: Container(
        color: theme.colorScheme.surfaceContainerLow,
        child: TabBar(
          controller: _tabController,
          tabs:  [
            Tab(icon: const Icon(PhosphorIconsBold.listChecks), text: tr('الخطط')),
            Tab(icon: const Icon(PhosphorIconsBold.clipboardText), text: tr('المهام')),
            Tab(icon: const Icon(PhosphorIconsBold.chartBar), text: tr('التحليلات')),
          ],
        ),
      ),
      toolbar: _tabController.index == 2
          ? null
          : PicPosToolbar(
              children: [
                ElevatedButton.icon(
                  onPressed: () {
                    if (_tabController.index == 0) {
                      _showCreatePlanDialog(repo, notifier);
                    } else if (_tabController.index == 1) {
                      _showGenerateTaskDialog(repo, state, notifier);
                    }
                  },
                  icon: const Icon(Icons.add),
                  label: Text(
                      _tabController.index == 0 ? tr('خطة جديدة') : tr('مهمة جديدة')),
                ),
              ],
            ),
      body: state.isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildPlansTab(theme, repo, state, notifier),
                _buildTasksTab(theme, repo, state, notifier),
                _buildAnalyticsTab(theme, repo, state),
              ],
            ),
    );
  }

  Widget _buildCountingPanel(ThemeData theme, ICycleCountRepository repo, CycleCountState state, CycleCountController notifier) {
    final task = state.selectedTask!;
    return Column(children: [
      Container(
        padding: const EdgeInsets.all(16),
        color: theme.colorScheme.surfaceContainerLow,
        child: Row(children: [
          Text(tr('مهمة {p0}', {'p0': DateFormat('yyyy/MM/dd').format(task.taskDate)}),
              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
          const Spacer(),
          if (task.status == 'pending')
            FilledButton.icon(
              onPressed: () async { await repo.startCycleCountTask(task.id); notifier.refresh(); },
              icon: const Icon(Icons.play_arrow, size: 18),
              label:  Text(tr('بدء')),
            ),
          if (task.status == 'in_progress')
            FilledButton.icon(
              // Spec 147 (S-COUNT): ONE atomic finalize (complete + apply @
              // costPrice + one settlement JE) in the DAO — replaces the old
              // three non-atomic calls + the UI-level JE hop. R2 guard blocks a
              // double-tap double-post.
              onPressed: _finalizing
                  ? null
                  : () async {
                      // Option B: block finalize on client/mirror (not sync-aware
                      // yet — would apply adjustments + JE local-only, reverted on pull).
                      //
                      // وهويّةُ الجهاز لا توجيهُ الكتابة: `isClientModeProvider`
                      // كانت تنفتح على مرآةٍ لم يكتمل تصافحُها، فيُعتمد جردٌ
                      // محلّيٌّ يمحوه أوّلُ سحب — وهو ما يمنعه هذا الحارسُ أصلاً.
                      if (NetworkService.instance.isBranchScopedDevice) {
                        AppToast.show(context,
                            tr('لا يمكن اعتماد الجرد من جهاز عميل أو مرآة — نفّذه على الخادم الرئيسي'));
                        return;
                      }
                      setState(() => _finalizing = true);
                      try {
                        // BUG-C: flush any typed-but-not-submitted counts first,
                        // so finalize sees them (otherwise countedQty stays null
                        // → applyCycleCountAdjustments skips the item → no stock
                        // change but a success toast).
                        await _flushPendingCounts(repo, state);
                        await repo.finalizeCycleCountTask(task.id, approverUserId: ref.read(authProvider).user?.id);
                        if (mounted) {
                          AppToast.show(context, tr('تم إكمال المهمة وتعديل المخزون'));
                          notifier.refresh();
                        }
                      } catch (e) {
                        if (mounted) {
                          AppToast.show(context, tr('تعذّر إكمال المهمة: {e}', {'e': e}));
                        }
                      } finally {
                        if (mounted) setState(() => _finalizing = false);
                      }
                    },
              icon: _finalizing
                  ? const SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.check, size: 18),
              label:  Text(tr('إكمال')),
              style: FilledButton.styleFrom(backgroundColor: Colors.green),
            ),
        ]),
      ),
      Expanded(
        child: ListView.builder(
          padding: const EdgeInsets.all(8),
          itemCount: state.taskItems.length,
          itemBuilder: (ctx, i) => _buildCountItem(theme, repo, state.taskItems[i], state, notifier),
        ),
      ),
    ]);
  }
}
