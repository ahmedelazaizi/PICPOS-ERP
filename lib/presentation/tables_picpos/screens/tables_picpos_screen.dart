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
import '../../../data/providers/providers.dart';
import '../../../domain/models/table_actions.dart';
import '../../../domain/repositories/restaurant_repository.dart';
import '../../picpos_shell/picpos_content_card.dart';
import '../../picpos_shell/picpos_screen_scaffold.dart';
import '../../screens/tables/floor_plan_designer.dart';
import '../../screens/tables/providers/tables_state_provider.dart';
import '../../screens/tables/widgets/table_card.dart';
import '../../screens/tables_screen.dart' show TableActionsHost, TableActionsRunner;
import '../../widgets/permission_guard.dart';
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
      title: 'إدارة الطاولات',
      subtitle: _scopeLabel(sections, scopeId),
      icon: PhosphorIconsBold.circlesThree,
      headerActions: [
        PermissionGuard(
          permission: PermissionCodes.tablesManage,
          allowManagerOverride: true,
          actionName: 'إضافة طاولة',
          onGranted: () => widget.actions.addTable(sectionId: scopeId),
          child: OutlinedButton.icon(
            onPressed: () => widget.actions.addTable(sectionId: scopeId),
            icon: const Icon(PhosphorIconsBold.plus, size: 18),
            label: const Text('إضافة طاولة'),
            style: OutlinedButton.styleFrom(foregroundColor: AppColors.success),
          ),
        ),
        const SizedBox(width: Spacing.sm),
        // في الرأس لا في «مزيد»: `PermissionGuard` يُعطّل الأزرارَ المعروفةَ
        // تعطيلاً حقيقيّاً، أمّا مدخلُ قائمةٍ منبثقةٍ فيبقى قابلاً للاختيار
        // مهما لُفّ نصُّه — فتكون الحراسةُ زينةً لا ضابطاً.
        PermissionGuard(
          permission: PermissionCodes.tablesManage,
          allowManagerOverride: true,
          actionName: 'إدارة أقسام الطاولات',
          onGranted: widget.actions.manageSections,
          child: OutlinedButton.icon(
            onPressed: widget.actions.manageSections,
            icon: const Icon(PhosphorIconsBold.mapPinArea, size: 18),
            label: const Text('إدارة الأقسام'),
            style: OutlinedButton.styleFrom(foregroundColor: AppColors.primary),
          ),
        ),
        const SizedBox(width: Spacing.sm),
        OutlinedButton.icon(
          onPressed: () => _toggleView(sections),
          icon: Icon(
            uiState.isVisualView
                ? PhosphorIconsBold.gridFour
                : PhosphorIconsBold.mapTrifold,
            size: 18,
          ),
          label: Text(uiState.isVisualView ? 'عرض الشبكة' : 'عرض الخريطة'),
          style: OutlinedButton.styleFrom(foregroundColor: AppColors.primary),
        ),
        const SizedBox(width: Spacing.sm),
        _buildScopeMenu(sections, scopeId, uiState.isVisualView),
        const SizedBox(width: Spacing.sm),
        _buildMoreMenu(selectedTable),
      ],
      body: sections.isEmpty
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
                  child: _buildMapOrGrid(repo, uiState, tables, scopeId),
                ),
                const SizedBox(width: Spacing.md),
                SizedBox(
                  width: 220,
                  child: SingleChildScrollView(
                    child: TablesActionRail(
                      tableStatus: selectedTable?.status,
                      onAction: (action) {
                        final table = selectedTable;
                        if (table == null) return;
                        widget.actions.run(table, action);
                      },
                    ),
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
          isEditMode: false,
          onTap: _openTable,
        ),
      );
    }

    final shown = uiState.statusFilter == 'all'
        ? tables
        : [for (final t in tables) if (t.status == uiState.statusFilter) t];

    if (shown.isEmpty) {
      return const PicPosContentCard(
        child: Center(
          child: Text(
            'لا توجد طاولاتٌ في هذا النطاق',
            style: TextStyle(color: AppColors.textMuted),
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

  void _toggleView(List<TableSection> sections) {
    final goingVisual = !ref.read(tablesUIProvider).isVisualView;
    if (goingVisual && _sectionId == null && sections.isNotEmpty) {
      setState(() => _sectionId = sections.first.id);
    }
    ref.read(tablesUIProvider.notifier).toggleView();
  }

  Widget _buildScopeMenu(
    List<TableSection> sections,
    int? scopeId,
    bool isVisualView,
  ) {
    return PopupMenuButton<int?>(
      tooltip: 'المنطقة',
      onSelected: (id) => setState(() => _sectionId = id),
      itemBuilder: (context) => [
        if (!isVisualView)
          const PopupMenuItem<int?>(value: null, child: Text('كل المناطق')),
        for (final section in sections)
          PopupMenuItem<int?>(value: section.id, child: Text(section.name)),
      ],
      // `IgnorePointer` لا زرٌّ معطَّل: زرٌّ بـ`onPressed: null` يبتلع الضغطةَ
      // ولا ينفّذها، فلا تصل إلى `PopupMenuButton` فوقه ولا تُفتَح القائمة.
      child: IgnorePointer(
        child: OutlinedButton.icon(
          onPressed: () {},
          icon: const Icon(PhosphorIconsBold.mapPin, size: 18),
          label: Text(_scopeLabel(sections, scopeId)),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.textSecondary,
          ),
        ),
      ),
    );
  }

  /// «مزيد من الخيارات» — الفعلان اللذان تركهما `railActions` عمداً خارج
  /// الشريط، وكلاهما يمرّ بالمنفِّذ نفسِه.
  ///
  /// ولا `PermissionGuard` هنا ولا يلزم: `log` بلا صلاحيّةٍ بتصميمه
  /// (`permissionForAction` تُرجع `null` — قراءةُ سجلٍّ لا تغيّر شيئاً)،
  /// و`cancelOrder` يفحص `tables_cancel` صراحةً في معالجه قبل أن يمسّ
  /// الخدمة. وحراسةُ مدخلِ قائمةٍ منبثقةٍ بلفّ نصِّه لا تمنع اختيارَه.
  Widget _buildMoreMenu(RestaurantTable? selectedTable) {
    return PopupMenuButton<String>(
      tooltip: 'مزيد من الخيارات',
      icon: const Icon(PhosphorIconsBold.dotsThreeOutline, size: 20),
      onSelected: (value) {
        final table = selectedTable;
        if (table == null) return;
        switch (value) {
          case 'log':
            widget.actions.run(table, TableAction.log);
          case 'cancel':
            widget.actions.run(table, TableAction.cancelOrder);
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem<String>(
          value: 'log',
          enabled: selectedTable != null,
          child: const Text('سجل الطاولة'),
        ),
        PopupMenuItem<String>(
          value: 'cancel',
          enabled: selectedTable != null,
          child: const Text('إلغاء الطلب'),
        ),
      ],
    );
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
            const Text(
              'لا توجد أقسام — أضف قسماً قبل الطاولات',
              style: TextStyle(color: AppColors.textMuted),
            ),
            const SizedBox(height: Spacing.md),
            PermissionGuard(
              permission: PermissionCodes.tablesManage,
              allowManagerOverride: true,
              actionName: 'إدارة أقسام الطاولات',
              onGranted: widget.actions.manageSections,
              child: ElevatedButton.icon(
                onPressed: widget.actions.manageSections,
                icon: const Icon(PhosphorIconsBold.plus, size: 18),
                label: const Text('إدارة الأقسام'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _scopeLabel(List<TableSection> sections, int? scopeId) {
    if (scopeId == null) return 'كل المناطق';
    for (final section in sections) {
      if (section.id == scopeId) return section.name;
    }
    return 'كل المناطق';
  }

  RestaurantTable? _byId(List<RestaurantTable> tables, int? id) {
    if (id == null) return null;
    for (final table in tables) {
      if (table.id == id) return table;
    }
    return null;
  }
}
