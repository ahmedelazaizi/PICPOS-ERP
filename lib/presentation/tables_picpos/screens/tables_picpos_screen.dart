import 'package:ural_erp/core/i18n/tr.dart';
// شاشةُ الطاولات بهوية PicPos — تخطيطٌ ثلاثيّ: عمودُ حالاتٍ · خريطةٌ أو
// شبكة · شريطُ أفعال.
//
// ── لا نسخَ منطق ───────────────────────────────────────────────────────────
// كلُّ فعلٍ هنا يمرّ بـ`TableActionsRunner` (‏`screens/tables/table_operations
// .dart`) وهو نفسُ مسار `_handleTableAction` الذي تستعمله القائمةُ المنبثقةُ
// في الشاشة القديمة. محرّكا أفعالٍ يتباعدان هما علّةُ هذا المستودع المعروفة،
// فلا ثانيَ هنا.
//
// ── لا استيرادَ `data/database` ───────────────────────────────────────────
// البياناتُ كلُّها عبر `IRestaurantRepository`، وأنواعُ الصفوف تصل من برميل
// `data/providers/providers.dart` كما في كلِّ توأمِ PicPos آخر.
//
// ── ولا مجرًى يُنشَأ في `build` ─────────────────────────────────────────────
// مجاري drift تعيش في مزوّدَين اثنين أسفلَ هذا التعليق، فيخبّئهما Riverpod
// بمفتاحهما ولا يُعاد إنشاؤهما مع كلِّ إعادة بناء. الشاشةُ نفسُها تُعيد البناءَ
// مع كلِّ نقرةِ حالةٍ أو طاولة، وإنشاءُ المجرى في `build` كان يعني فسخَ
// اشتراكٍ وإعادتَه ⇒ ١+N استعلاماً (عطبُ شاشة المطبخ في 3970bde9).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/design_system/spacing.dart';
import '../../../core/permissions/permission_codes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/navigation/screen_id.dart';
import '../../../data/providers/providers.dart';
import '../../../data/providers/screen_navigation_provider.dart';
import '../../../domain/models/table_actions.dart';
import '../../../domain/repositories/restaurant_repository.dart';
import '../../picpos_shell/picpos_content_card.dart';
import '../../picpos_shell/picpos_header_actions.dart';
import '../../picpos_shell/picpos_screen_scaffold.dart';
import '../../screens/tables/floor_plan_designer.dart';
import '../../screens/tables/providers/tables_state_provider.dart';
import '../../screens/tables/widgets/table_card.dart';
import '../../screens/tables_screen.dart' show TableActionsHost, TableActionsRunner;
import '../../widgets/permission_guard.dart';
import '../logic/tables_grid_model.dart';
import '../widgets/guest_requests_banner.dart';
import '../widgets/table_session_pin_card.dart';
import '../widgets/tables_action_rail.dart';
import '../widgets/tables_status_rail.dart';

/// أقسامُ الطاولات — مجرًى واحدٌ للتطبيق كلِّه.
final _sectionsProvider = StreamProvider.autoDispose<List<TableSection>>((ref) {
  return ref.watch(restaurantRepositoryProvider).watchAllSections();
});

/// طاولاتُ قسمٍ واحد — مجرًى لكلِّ قسمٍ يُخبّئه Riverpod بمفتاحه.
final _tablesInSectionProvider = StreamProvider.autoDispose
    .family<List<RestaurantTable>, int>((ref, sectionId) {
  return ref
      .watch(restaurantRepositoryProvider)
      .watchTablesInSection(sectionId);
});

// ────────────────────────────────────────
// زرُّ «مصمّم القاعة»
//
// 🔴 **كان زرُّ «تصميم» يقلب هذه الشاشةَ نفسَها إلى محرّر.** وقسمُ ٧
// أخرجَ المحرّرَ إلى شاشةٍ مستقلّة، وصارت **خريطةُ النادل للقراءة
// فقط** (القرارُ ٦)، فلا تنزلق طاولةٌ تحتَ إصبعٍ يريد أن ينقرَها.
//
// والزرُّ يبقى لا يُحذَف: من تعلّم أنّ الترتيبَ هنا يُدلَّ على مكانِه
// الجديد، لا يجد الزرَّ غاب بلا كلمة.
//
// والحراسةُ زرٌّ يُعطَّل فعلاً (`allowManagerOverride` مع `onGranted` صريح)
// لا `PopupMenuItem` ملفوفٌ بحارسٍ يبقى قابلاً للاختيار مهما لُفَّ نصُّه.
@visibleForTesting
Widget buildTablesOpenDesignerButton({required VoidCallback onOpen}) {
  return PermissionGuard(
    permission: PermissionCodes.tablesManage,
    allowManagerOverride: true,
    actionName: tr('مصمم القاعة'),
    onGranted: onOpen,
    child: OutlinedButton.icon(
      key: const Key('tables_open_designer'),
      onPressed: onOpen,
      icon: const Icon(PhosphorIconsBold.squaresFour, size: 18),
      label:  Text(tr('مصمم القاعة')),
      style: OutlinedButton.styleFrom(foregroundColor: AppColors.warning),
    ),
  );
}

/// شاشةُ الطاولات بهوية PicPos — توأمُ [TablesScreen]، تُختار بالعلامة في
/// `app_main_screen`.
class TablesPicposScreen extends StatelessWidget {
  const TablesPicposScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // المضيفُ فوق الجسم لا داخله: أزرارُ الرأس (إضافةُ طاولةٍ وإدارةُ الأقسام)
    // تحتاج المنفِّذَ نفسَه الذي يحتاجه شريطُ الأفعال.
    return TableActionsHost(
      builder: (context, actions) => _TablesPicposBody(actions: actions),
    );
  }
}

class _TablesPicposBody extends ConsumerStatefulWidget {
  const _TablesPicposBody({required this.actions});

  final TableActionsRunner actions;

  @override
  ConsumerState<_TablesPicposBody> createState() => _TablesPicposBodyState();
}

class _TablesPicposBodyState extends ConsumerState<_TablesPicposBody> {
  /// القسمُ المعروض — `null` تعني «كل المناطق».
  int? _sectionId;

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(restaurantRepositoryProvider);
    final uiState = ref.watch(tablesUIProvider);
    final sections =
        ref.watch(_sectionsProvider).asData?.value ?? const <TableSection>[];

    // قسمٌ حُذف يعود إلى «كل المناطق» بدل شاشةٍ فارغةٍ لا تفسّر فراغَها.
    final chosen =
        sections.any((s) => s.id == _sectionId) ? _sectionId : null;

    // الخريطةُ لوحةُ **قسمٍ واحد** بتصميمها (`FloorPlanDesigner.sectionId`)،
    // فـ«كل المناطق» خيارٌ لا تستطيع تنفيذَه: يُخفى من المنسدلة في وضع
    // الخريطة، ويقع النطاقُ على أوّل قسم — لا يُعرَض ثم يُتجاهَل صامتاً.
    final int? scopeId = uiState.isVisualView
        ? (chosen ?? (sections.isEmpty ? null : sections.first.id))
        : chosen;

    final tables = <RestaurantTable>[
      if (scopeId != null)
        ...?ref.watch(_tablesInSectionProvider(scopeId)).asData?.value
      else
        for (final section in sections)
          ...?ref.watch(_tablesInSectionProvider(section.id)).asData?.value,
    ];

    final selectedTable = _byId(tables, uiState.selectedTableId);

    return PicPosScreenScaffold(
      title: tr('إدارة الطاولات'),
      subtitle: _scopeLabel(sections, scopeId),
      icon: PhosphorIconsBold.circlesThree,
      // 🔴 شريطُ إجراءاتٍ بأولويّات (خطة A.4): كان الصفُّ في `SingleChildScrollView`
      // مثبَّتٍ من آخره فيُقَصُّ «إضافة طاولة» بصمتٍ عند الضيق. الآن «إضافة
      // طاولة» لا تختفي أبداً، وما لا يتّسع ينتقل إلى «⋯».
      //
      // والحراسةُ (`permission`) تُطبَّق على الزرّ الظاهر **وعلى مدخل «⋯»**
      // معاً (موافقةُ مسؤولٍ عند غياب `tables_manage`) — فلا تُفلت بنقل الزرّ.
      headerActionsBar: _headerActions(sections, scopeId, uiState, selectedTable),
      // شريطُ طلبات الضيوف فوق كلِّ شيء — يظهر حين يوجد ما ينتظر، ويختفي
      // تماماً حين لا يوجد. وفوقَ الأقسام لا داخلَها: الطلبُ قد يصل من طاولةٍ
      // في قسمٍ غيرِ المعروض الآن، فإخفاؤه مع القسم يُضيع النداء.
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const GuestRequestsBanner(),
          Expanded(
            child: sections.isEmpty
                ? _buildNoSections()
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                // في RTL أوّلُ ابنٍ يقع في أوّل القراءة — عمودُ الحالات ثم
                // الخريطةُ ثم شريطُ الأفعال، كترتيب المواصفة.
                SizedBox(
                  width: 200,
                  child: SingleChildScrollView(
                    child: TablesStatusRail(
                      counts: countByStatus([
                        for (final table in tables) table.status,
                      ]),
                      selected: uiState.statusFilter == 'all'
                          ? null
                          : uiState.statusFilter,
                      onSelect: (status) => ref
                          .read(tablesUIProvider.notifier)
                          .setStatusFilter(status ?? 'all'),
                    ),
                  ),
                ),
                const SizedBox(width: Spacing.md),
                Expanded(
                  child: _buildMapOrGrid(
                    repo,
                    uiState,
                    tables,
                    scopeId,
                    {for (final s in sections) s.id: s.name},
                  ),
                ),
                const SizedBox(width: Spacing.md),
                SizedBox(
                  width: 220,
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // رقمُ الجلسة فوقَ الأفعال — يقرؤه النادلُ
                        // للطاولة المختارة، ولا يظهر إلّا في وضع
                        // الدومين العامّ حيث يُطلَب فعلاً.
                        TableSessionPinCard(
                          tableId: selectedTable?.id,
                        ),
                        TablesActionRail(
                          tableStatus: selectedTable?.status,
                          onAction: (action) {
                            final table = selectedTable;
                            if (table == null) return;
                            widget.actions.run(table, action);
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  /// الخريطةُ أو الشبكة — **هذا هو توصيلُ `isVisualView`**، المفتاحُ الذي كان
  /// يقلب حالةً لا يقرأها أحد.
  Widget _buildMapOrGrid(
    IRestaurantRepository repo,
    TablesUIState uiState,
    List<RestaurantTable> tables,
    int? scopeId,
    Map<int, String> sectionNames,
  ) {
    if (uiState.isVisualView) {
      if (scopeId == null) return _buildNoSections();
      return PicPosContentCard(
        padding: const EdgeInsets.all(Spacing.sm),
        child: FloorPlanDesigner(
          // مفتاحٌ بالقسم: تبديلُ القسم يبني حالةً جديدةً بمجراها، فلا تبقى
          // مواضعُ السحب الحيّةُ من قسمٍ سابق.
          key: ValueKey(scopeId),
          sectionId: scopeId,
          // 🔴 **القرارُ ٦: خريطةُ النادل للقراءة فقط — لا سحبَ إطلاقاً.**
          //    سحبٌ حيٌّ في شاشةِ تشغيلٍ يعني أنّ نقرةً مائلةً قليلاً تنقل
          //    طاولةً بدل أن تفتحَها — ولا يدري النادلُ أنّه حرّك شيئاً
          //    حتّى يرى الخريطةَ مبعثرةً غداً.
          isEditMode: false,
          // مرشِّحُ عمود الحالات يسري على الخريطة كما يسري على الشبكة.
          // كان يسري على فرع الشبكة وحدَه، و`isVisualView` افتراضُها `true`
          // — فالمستخدمُ يهبط على الخريطة وينقر «متاحة» فلا يتغيّر شيء.
          statusFilter:
              uiState.statusFilter == 'all' ? null : uiState.statusFilter,
          onTap: _openTable,
        ),
      );
    }

    // 🔴 **اختيارُ حالةٍ يُميِّز ولا يُخفي** (خطة A.7): كل الطاولات تُرسَم دائماً
    // وغيرُ المطابقة تُعتَّم، فيرى النادلُ الصالةَ كلَّها وحالةَ كلِّ طاولة.
    final filter = uiState.statusFilter;
    final shown = TablesGridModel.visibleTables(tables, filter);

    if (shown.isEmpty) {
      return  PicPosContentCard(
        child: Center(
          child: Text(
            tr('لا توجد طاولاتٌ في هذا النطاق'),
            style: const TextStyle(color: AppColors.textMuted),
          ),
        ),
      );
    }

    return PicPosContentCard(
      child: GridView.builder(
        padding: const EdgeInsets.all(Spacing.lg),
        gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: uiState.tableCardSize,
          mainAxisSpacing: Spacing.lg,
          crossAxisSpacing: Spacing.lg,
          childAspectRatio: 1,
        ),
        itemCount: shown.length,
        itemBuilder: (context, index) => TableCard(
          table: shown[index],
          restaurantRepo: repo,
          onInteraction: _openTable,
          sectionName: sectionNames[shown[index].sectionId],
          dimmed: TablesGridModel.isDimmed(shown[index].status, filter),
          highlighted:
              TablesGridModel.isHighlighted(shown[index].status, filter),
        ),
      ),
    );
  }

  /// نقرةُ الطاولة: تُختار **وتُفتح نافذةُ طلبها** — قرارُ المالك، لا عمودَ
  /// طلبٍ ثابتٌ كما في الشاشة القديمة. والاختيارُ يبقى بعد إغلاق النافذة
  /// فيعمل شريطُ الأفعال على الطاولة نفسِها.
  void _openTable(RestaurantTable table) {
    ref.read(tablesUIProvider.notifier).selectTable(table.id);
    widget.actions.openOrder(table);
  }

  /// إجراءاتُ الرأس بأولويّاتها: إضافةُ طاولة (1) ← تبديلُ العرض (2) ← المنطقة
  /// (3) ← الأقسام (4) ← المصمّم (5) ← «مزيد» (6). والترتيبُ المرئيُّ هو ترتيبُ
  /// القائمة لا الأولويّة.
  List<PicPosHeaderAction> _headerActions(
    List<TableSection> sections,
    int? scopeId,
    TablesUIState uiState,
    RestaurantTable? selectedTable,
  ) {
    return [
      PicPosHeaderAction(
        buttonKey: const Key('tables_add_table'),
        label: tr('إضافة طاولة'),
        icon: PhosphorIconsBold.plus,
        priority: 1,
        color: AppColors.success,
        permission: PermissionCodes.tablesManage,
        onPressed: () => widget.actions.addTable(sectionId: scopeId),
      ),
      PicPosHeaderAction(
        label: tr('إدارة الأقسام'),
        actionName: tr('إدارة أقسام الطاولات'),
        icon: PhosphorIconsBold.mapPinArea,
        priority: 4,
        color: AppColors.primary,
        permission: PermissionCodes.tablesManage,
        onPressed: widget.actions.manageSections,
      ),
      // ⚠️ **وأكوادُ حساب الطاولات انتقلت إلى الإعدادات** (قسمُ ٧، بلاغُ
      // المالك «قارئُ QR مكانُه مش شاشة الطاولات»): ورقةٌ تُطبَع مرّةً
      // عند التجهيز ثمّ تُلصَق، فلا تزاحم أفعالَ النادل اليوميّة.
      // والحراسةُ انتقلت معها بحرفها — راجع `TableBillQrLauncherRow`.
      PicPosHeaderAction(
        label: uiState.isVisualView ? tr('عرض الشبكة') : tr('عرض الخريطة'),
        icon: uiState.isVisualView
            ? PhosphorIconsBold.gridFour
            : PhosphorIconsBold.mapTrifold,
        priority: 2,
        color: AppColors.primary,
        // بلا مسٍّ لـ`_sectionId`: احتياطُ الخريطة محسوبٌ في `scopeId`، فكتابةُ
        // أوّلِ قسمٍ هنا كانت تُخرج مَن اختار «كل المناطق» منها صامتاً.
        onPressed: ref.read(tablesUIProvider.notifier).toggleView,
      ),
      // مصمّمُ القاعة — **في العرضَين كلَيهما** (يفتح شاشةً مستقلّة). الحراسةُ
      // نفسُها في `buildTablesOpenDesignerButton` المثبَتةِ باختبارها.
      PicPosHeaderAction(
        buttonKey: const Key('tables_open_designer'),
        label: tr('مصمم القاعة'),
        icon: PhosphorIconsBold.squaresFour,
        priority: 5,
        color: AppColors.warning,
        permission: PermissionCodes.tablesManage,
        onPressed: () => ref
            .read(screenNavigationProvider.notifier)
            .open(ScreenId.floorPlanDesigner.navigationIndex),
      ),
      PicPosHeaderAction(
        label: _scopeLabel(sections, scopeId),
        tooltip: tr('المنطقة'),
        icon: PhosphorIconsBold.mapPin,
        priority: 3,
        color: AppColors.textSecondary,
        choices: [
          if (!uiState.isVisualView)
            PicPosHeaderChoice(
              label: tr('كل المناطق'),
              onSelected: () => setState(() => _sectionId = null),
            ),
          for (final section in sections)
            PicPosHeaderChoice(
              label: section.name,
              onSelected: () => setState(() => _sectionId = section.id),
            ),
        ],
      ),
      // «مزيد من الخيارات» — الفعلان اللذان تركهما `railActions` عمداً خارج
      // الشريط، وكلاهما يمرّ بالمنفِّذ نفسِه. بلا `permission`: `log` بلا
      // صلاحيّةٍ بتصميمه، و`cancelOrder` يفحص `tables_cancel` في معالجه.
      PicPosHeaderAction(
        label: tr('مزيد من الخيارات'),
        icon: PhosphorIconsBold.dotsThreeOutline,
        iconOnly: true,
        priority: 6,
        choices: [
          PicPosHeaderChoice(
            label: tr('سجل الطاولة'),
            enabled: selectedTable != null,
            onSelected: () => widget.actions.run(selectedTable!, TableAction.log),
          ),
          PicPosHeaderChoice(
            label: tr('إلغاء الطلب'),
            enabled: selectedTable != null,
            onSelected: () =>
                widget.actions.run(selectedTable!, TableAction.cancelOrder),
          ),
        ],
      ),
    ];
  }

  Widget _buildNoSections() {
    return PicPosContentCard(
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              PhosphorIconsBold.mapPin,
              size: IconSizes.xxl,
              color: AppColors.textMuted,
            ),
            const SizedBox(height: Spacing.md),
             Text(
              tr('لا توجد أقسام — أضف قسماً قبل الطاولات'),
              style: const TextStyle(color: AppColors.textMuted),
            ),
            const SizedBox(height: Spacing.md),
            PermissionGuard(
              permission: PermissionCodes.tablesManage,
              allowManagerOverride: true,
              actionName: tr('إدارة أقسام الطاولات'),
              onGranted: widget.actions.manageSections,
              child: ElevatedButton.icon(
                onPressed: widget.actions.manageSections,
                icon: const Icon(PhosphorIconsBold.plus, size: 18),
                label:  Text(tr('إدارة الأقسام')),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _scopeLabel(List<TableSection> sections, int? scopeId) {
    if (scopeId == null) return tr('كل المناطق');
    for (final section in sections) {
      if (section.id == scopeId) return section.name;
    }
    return tr('كل المناطق');
  }

  RestaurantTable? _byId(List<RestaurantTable> tables, int? id) {
    if (id == null) return null;
    for (final table in tables) {
      if (table.id == id) return table;
    }
    return null;
  }
}
