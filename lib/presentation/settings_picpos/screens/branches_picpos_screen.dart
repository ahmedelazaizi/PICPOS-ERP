import 'package:ural_erp/core/i18n/tr.dart';
// «الفروع والمنشآت» — نسخةُ PicPos على تصميم `PicPos Branches.dc.html`.
//
// ═══ ما قِيس قبل الكتابة ═══
//
// ⚠️ **ملفّاتُ التصميم الأربعةُ ملفٌّ واحدٌ لا أربعة.** «الفروع» و«المناطق»
// و«التحليلات» و«الموظفون» تحمل نفسَ `MODULES` الأربع ونفسَ العشرين تبويبةً،
// ولا تختلف إلّا في الوحدة المفتوحة افتراضيّاً (`get mod()`) وسطرِ الشريط
// الجانبيّ — قِيس بـ`diff` لا بالنظر: ثمانيةُ أسطرِ فرقٍ بين ثلاثةٍ منها.
// و«الفروع» **أحدثُها** (‏١٦٤ سطرَ فرقٍ فيها تبويبةُ مخازنَ أغنى)، فهي المصدر.
//
// وأمرُ المالك 2026-08-25 بعد عرض القياس: **أربعُ شاشاتٍ منفصلةٌ بلغة
// التصميم** لا مركزٌ واحدٌ بمنتقي وحدات. فهذه الشاشةُ تأخذ وحدةَ `branches`
// وحدَها بتبويباتها الخمس، ولا تحمل منتقيَ الوحدات.
//
// ═══ قشرةٌ حيث يوجد جسمٌ، وبناءٌ حيث لا يوجد ═══
//
// • «نقاط البيع» و«تقويم العطلات» لهما `PosTerminalsBody` و`WorkHolidaysBody`
//   جاهزان ومستعمَلان في شاشتَيهما — فيُركَبان كما هما، ولا نسخةَ ثانيةً
//   تُصان. وهذا نفسُ نمط `PrintersPicposScreen`.
//
// • «الفروع» و«المخازن» و«صلاحيات الوصول» تُبنى هنا على لبنات التصميم
//   (`PicPosHubKpiRow` · `PicPosEntityCard` · `PicPosDataTable`) من مزوِّداتٍ
//   قائمة.
//
// ⚠️ **وكلُّ رقمٍ مشتقٌّ من الشجرة لا مكتوبٌ بجانبها**: شاراتُ التبويبات
// وعدّاداتُ المؤشّرات وشرائحُ الترشيح كلُّها تُحسَب من نفس القوائم التي
// تُرسَم. ومؤشّراتُ التصميم التي لا مصدرَ لها في البرنامج (‏«مبيعات اليوم»
// لكلّ فرعٍ · «الموظفون الموزّعون») **لم تُخترَع**، فرقمٌ يكذب أسوأُ من
// لا رقم.
//
// ⚠️ **ولا مصدرَ لـ«ساعات العمل» ولا «الوردية المفتوحة»** في `Branches` —
// فرقائقُ التصميم تلك غيرُ مرسومة. والمرسومُ ما يقرأه العمود.
//
// ⚠️ **ومصدرُ المخازن مستودعُ الفروع لا `allWarehousesProvider`.** الأخيرُ
// يعطي DTO نطاقٍ (`WarehouseData`) بلا `isActive`، و`WarehouseEditDialog`
// يستقبل صفَّ drift. فأوّلُ كتابةٍ أسقطت عمودَي «الحالة» و«إجراء» من
// التصميم لهذا السبب — ثمّ أمر المالكُ بزرّ التعديل، فقِيس أنّ
// `IBranchRepository.watchAllWarehouses()` يعطي الصفوفَ أصلاً، فعاد
// العمودان معاً.
//
// ولا مخالفةَ لحارس الاستيراد: نوعُ `Warehouse` يصل عبر
// `data/providers/providers.dart` (‏يُعيد تصدير `database_barrel.dart`) لا
// عبر `data/database/...` مباشرةً — وهذا نفسُ ما يفعله الحوارُ نفسُه.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:ural_erp/core/widgets/app_toast.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/permissions/permission_codes.dart';
import '../../../data/providers/providers.dart';
import '../../picpos_shell/picpos_body_handle.dart';
import '../../picpos_shell/picpos_data_table.dart';
import '../../picpos_shell/picpos_entity_card.dart';
import '../../picpos_shell/picpos_hub_kpi.dart';
import '../../picpos_shell/picpos_report_tabs.dart';
import '../../picpos_shell/picpos_screen_scaffold.dart';
import '../../picpos_shell/picpos_surface.dart';
import '../../screens/widgets/dialogs/branch_edit_dialog.dart';
import '../../screens/widgets/dialogs/warehouse_edit_dialog.dart';
import '../../screens/warehouse_locations_screen.dart';
import '../../widgets/permission_guard.dart';
import '../../screens/pos_terminals_screen.dart' show PosTerminalsBody;
import '../../screens/settings/work_holidays_screen.dart'
    show WorkHolidaysBody;

/// صفوفُ المخازن من مستودع الفروع — **صفوفُ drift** لا DTO النطاق.
///
/// `allWarehousesProvider` القائمُ يحوّلها إلى `WarehouseData` فيُسقط
/// `isActive` و`isSystemDefault`، وهما ما يحتاجه عمودُ «الحالة» وحوارُ
/// التعديل. وتحويلٌ عكسيٌّ من الـDTO مستحيلٌ: الحقولُ غيرُ موجودةٍ فيه أصلاً.
final _warehouseRowsProvider = StreamProvider.autoDispose<List<Warehouse>>(
  (ref) => ref.watch(branchRepositoryProvider).watchAllWarehouses(),
);

/// ملاحظاتُ التبويبات — نصوصُ `TABS.branches[].note` حرفيّاً.
///
/// كلُّ واحدةٍ منها **قاعدةُ عملٍ** تشرح سلوكاً قد يبدو خطأً للمشغّل، لا
/// جملةً تزيينيّة. وقِيس أنّ ثلاثاً منها تصف الكودَ كما هو:
/// `Warehouses.branchId` قابلٌ للإفراغ، وعطلاتُ الفرع تُدمَج مع العامّة في
/// `getWorkHolidays`، وغيابُ صفوف `user_branch_access` يعني وصولاً كاملاً.
List<String> get _tabNotes => [
  tr('الفرع يملك نقاط بيع ومخازن وتقويم عطلات مستقلاً'),
  tr('كل نقطة بيع مرتبطة بفرع وطابعة وخزينة'),
  tr('المخزن يتبع فرعاً واحداً — وبلا فرع يكون عاماً على المنشأة'),
  tr('عطلات الفرع = صفوفه + الصفوف العامة (دمج تراكمي)'),
  tr('بلا صفوف = وصول لكل الفروع (توافق خلفي)'),
];

class BranchesPicposScreen extends ConsumerStatefulWidget {
  const BranchesPicposScreen({super.key});

  @override
  ConsumerState<BranchesPicposScreen> createState() =>
      _BranchesPicposScreenState();
}

class _BranchesPicposScreenState extends ConsumerState<BranchesPicposScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 5, vsync: this);
  final _searchCtrl = TextEditingController();
  final _holidayHandle = PicPosBodyHandle();
  String _query = '';

  /// شريحةُ الترشيح المختارةُ في كلّ تبويبةٍ لها جدول — مفتاحُها رقمُ التبويبة.
  final Map<int, int> _chip = {};

  @override
  void initState() {
    super.initState();
    // الترويسةُ والملاحظةُ والإجراءُ كلُّها تتبع التبويبةَ النشطة.
    _tabs.addListener(_onTab);
  }

  void _onTab() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _tabs.removeListener(_onTab);
    _tabs.dispose();
    _searchCtrl.dispose();
    _holidayHandle.dispose();
    super.dispose();
  }

  bool _hit(String? s) =>
      _query.isEmpty || (s ?? '').toLowerCase().contains(_query);

  @override
  Widget build(BuildContext context) {
    final List<Branche> branches =
        ref.watch(allBranchesProvider).value ?? const [];
    // ⚠️ **صفوفُ drift لا DTO النطاق.** `allWarehousesProvider` يعطي
    //    `WarehouseData` بحقولٍ أقلَّ ولا `isActive` فيه، و`WarehouseEditDialog`
    //    يستقبل صفَّ drift. فالمصدرُ هنا مستودعُ الفروع — وبه يعود عمودا
    //    «الحالة» و«إجراء» من التصميم، وكانا ساقطَين لهذا السبب وحدَه.
    final List<Warehouse> warehouses =
        ref.watch(_warehouseRowsProvider).value ?? const [];
    final List<UserWithRole> users =
        ref.watch(allUsersProvider).value ?? const [];

    return PicPosScreenScaffold(
      title: tr('الفروع والمنشآت'),
      subtitle:
          tr('الفروع ونقاط البيع والمخازن وتقويم العطلات وصلاحيات الوصول'),
      icon: PhosphorIconsBold.buildings,
      headerSearch: TextField(
        controller: _searchCtrl,
        onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
        decoration: InputDecoration(
          isDense: true,
          hintText: tr('ابحث عن فرع أو نقطة بيع...'),
          prefixIcon: const Icon(PhosphorIconsBold.magnifyingGlass, size: 16),
          suffixIcon: _query.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(PhosphorIconsBold.x, size: 14),
                  onPressed: () {
                    _searchCtrl.clear();
                    setState(() => _query = '');
                  },
                ),
        ),
      ),
      headerActions: _actions(),
      subHeader: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PicPosReportTabs(
            controller: _tabs,
            tabs: [
              (
                label: tr('الفروع'),
                icon: PhosphorIconsBold.buildings,
                badge: '${branches.length}'
              ),
              (
                label: tr('نقاط البيع'),
                icon: PhosphorIconsBold.desktopTower,
                badge: null
              ),
              (
                label: tr('المخازن'),
                icon: PhosphorIconsBold.warehouse,
                badge: '${warehouses.length}'
              ),
              (
                label: tr('تقويم العطلات'),
                icon: PhosphorIconsBold.calendarX,
                badge: null
              ),
              (
                label: tr('صلاحيات الوصول'),
                icon: PhosphorIconsBold.lockKey,
                badge: '${users.length}'
              ),
            ],
          ),
          PicPosTabNote(note: _tabNotes[_tabs.index]),
        ],
      ),
      bodyPadding: EdgeInsets.zero,
      body: TabBarView(
        controller: _tabs,
        children: [
          _scroll(_branchesTab(context, branches, warehouses)),
          PosTerminalsBody(searchQuery: _query),
          _scroll(_warehousesTab(context, branches, warehouses)),
          WorkHolidaysBody(addHandle: _holidayHandle, searchQuery: _query),
          _scroll(_accessTab(context, branches, users)),
        ],
      ),
    );
  }

  Widget _scroll(Widget child) => SingleChildScrollView(
        padding: const EdgeInsetsDirectional.fromSTEB(20, 20, 20, 26),
        child: child,
      );

  /// إجراءُ الترويسة يتبع التبويبةَ — `action`/`dlg` لكلّ تبويبةٍ في التصميم.
  ///
  /// ⚠️ **ولا زرَّ لتبويبةٍ لا يملك جسمُها إضافةً**: «نقاط البيع» جسمُها
  /// المشتركُ لا يعرض مقبضَ إضافة، فزرٌّ هنا لا ينادي شيئاً. و«صلاحيات
  /// الوصول» تُمنَح من صفِّ المستخدم لا من الترويسة.
  List<Widget> _actions() {
    switch (_tabs.index) {
      case 0:
        return [
          ElevatedButton.icon(
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (_) => const BranchEditDialog(),
              );
              if (ok == true && mounted) setState(() {});
            },
            icon: const Icon(PhosphorIconsBold.plus, size: 15),
            label:  Text(tr('فرع جديد')),
          ),
        ];
      case 2:
        return [
          ElevatedButton.icon(
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (_) => const WarehouseEditDialog(),
              );
              if (ok == true && mounted) setState(() {});
            },
            icon: const Icon(PhosphorIconsBold.plus, size: 15),
            label:  Text(tr('مخزن جديد')),
          ),
        ];
      case 3:
        return [
          ValueListenableBuilder<bool>(
            valueListenable: _holidayHandle.isReady,
            builder: (_, ready, _) => ElevatedButton.icon(
              onPressed: ready ? _holidayHandle.invoke : null,
              icon: const Icon(PhosphorIconsBold.plus, size: 15),
              label:  Text(tr('عطلة جديدة')),
            ),
          ),
        ];
      default:
        return const [];
    }
  }

  // ── تبويبةُ الفروع ─────────────────────────────────────────────────────

  Widget _branchesTab(
    BuildContext context,
    List<Branche> branches,
    List<Warehouse> warehouses,
  ) {
    final shown = branches.where((b) => _hit(b.name) || _hit(b.code)).toList();
    final active = branches.where((b) => b.isActive == true).length;
    final linked = warehouses.where((w) => w.branchId != null).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        PicPosHubKpiRow(
          items: [
            PicPosHubKpi(
              icon: PhosphorIconsBold.buildings,
              label: tr('الفروع النشطة'),
              value: '$active',
              tint: AppColors.primary,
              vs: tr('من {p0} مسجلة', {'p0': branches.length}),
            ),
            PicPosHubKpi(
              icon: PhosphorIconsBold.warehouse,
              label: tr('المخازن'),
              value: '${warehouses.length}',
              tint: AppColors.warning,
              vs: tr('{linked} مرتبطٌ بفرع', {'linked': linked}),
            ),
            PicPosHubKpi(
              icon: PhosphorIconsBold.mapPin,
              label: tr('فروعٌ بمنطقة'),
              value: '${branches.where((b) => b.regionId != null).length}',
              tint: const Color(0xFF8B5CF6),
              vs: tr('مرتبطةٌ بمنطقةٍ جغرافيّة'),
            ),
            PicPosHubKpi(
              icon: PhosphorIconsBold.star,
              label: tr('الفرع الافتراضيّ'),
              value: branches.any((b) => b.isSystemDefault == true)
                  ? tr('مضبوط')
                  : tr('غير مضبوط'),
              tint: branches.any((b) => b.isSystemDefault == true)
                  ? AppColors.success
                  : AppColors.error,
              vs: tr('يُنشأ تلقائيّاً عند غيابه'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        // ⚠️ بلا سطرٍ خافتٍ هنا: نصُّ القاعدة يقوله شريطُ ملاحظة التبويبة
        // فوقَه، وتكرارُه يجعل نفسَ الجملة مرّتين في شاشةٍ واحدة.
         PicPosBlockHeader(title: tr('الفروع')),
        if (shown.isEmpty)
          _empty(context, tr('لا فروعَ مطابقة'))
        else
          PicPosEntityCardGrid(
            children: [
              for (final b in shown)
                PicPosEntityCard(
                  title: b.name,
                  subtitle: _branchSub(b),
                  tint: b.isActive == true
                      ? AppColors.success
                      : AppColors.textMuted,
                  icon: PhosphorIconsBold.storefront,
                  status: b.isSystemDefault == true
                      ? tr('افتراضيّ')
                      : (b.isActive == true ? tr('نشط') : tr('موقوف')),
                  statusTint: b.isSystemDefault == true
                      ? AppColors.primary
                      : (b.isActive == true
                          ? AppColors.success
                          : AppColors.textMuted),
                  stats: [
                    PicPosEntityStat(
                      tr('المخازن'),
                      '${warehouses.where((w) => w.branchId == b.id).length}',
                    ),
                    PicPosEntityStat(tr('الرمز'), b.code ?? '—'),
                    PicPosEntityStat(
                      tr('مركز التكلفة'),
                      b.costCenterId != null ? tr('مرتبط') : '—',
                    ),
                  ],
                  chips: [
                    if (b.phone?.isNotEmpty ?? false)
                      PicPosEntityChip(
                          PhosphorIconsBold.phone, b.phone!),
                    if (b.regionId != null)
                       PicPosEntityChip(
                          PhosphorIconsBold.mapTrifold, tr('ضمن منطقة')),
                  ],
                ),
            ],
          ),
      ],
    );
  }

  String? _branchSub(Branche b) {
    final addr = b.address;
    if (addr != null && addr.isNotEmpty) return addr;
    return null;
  }

  // ── تبويبةُ المخازن ────────────────────────────────────────────────────

  static Map<String, (String, Color)> get _whTypes => {
    'raw_materials': (tr('خامات'), const Color(0xFFEA580C)),
    'finished_goods': (tr('منتج تام'), AppColors.info),
    'retail': (tr('بيع'), const Color(0xFF8B5CF6)),
  };

  Widget _warehousesTab(
    BuildContext context,
    List<Branche> branches,
    List<Warehouse> warehouses,
  ) {
    final names = {for (final b in branches) b.id: b.name};

    // شرائحُ الترشيح — نفسُ شرائح التصميم، وعدّادُ كلٍّ منها **محسوب**.
    final chipDefs = <(String, bool Function(Warehouse))>[
      (tr('كل المخازن'), (w) => true),
      (tr('يُباع منه'), (w) => w.type == 'retail'),
      (tr('خامات'), (w) => w.type == 'raw_materials'),
      (tr('بلا فرع'), (w) => w.branchId == null),
    ];
    final pick = _chip[2] ?? 0;
    final shown = warehouses
        .where((w) => chipDefs[pick].$2(w) && _hit(w.name))
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        PicPosHubKpiRow(
          items: [
            PicPosHubKpi(
              icon: PhosphorIconsBold.warehouse,
              label: tr('المخازن النشطة'),
              value: '${warehouses.where((w) => w.isActive).length}',
              tint: AppColors.primary,
              vs: tr('من {p0} مسجلة', {'p0': warehouses.length}),
            ),
            PicPosHubKpi(
              icon: PhosphorIconsBold.link,
              label: tr('مربوطة بفرع'),
              value: '${warehouses.where((w) => w.branchId != null).length}',
              tint: AppColors.success,
              vs: '${warehouses.where((w) => w.branchId == null).length} عامٌّ '
                  'على المنشأة',
            ),
            PicPosHubKpi(
              icon: PhosphorIconsBold.star,
              label: tr('مخازنُ افتراضيّة'),
              value: '${warehouses.where((w) => w.isDefault == true).length}',
              tint: AppColors.warning,
              vs: tr('تُختار تلقائيّاً في العمليات'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        PicPosDataTable(
          title: tr('المخازن'),
          // النصفُ الثاني من `sub` في التصميم — أمّا نصفُه الأوّلُ فهو نصُّ
          // ملاحظة التبويبة فوقَه، وتكرارُه يعيد الجملةَ مرّتين.
          subtitle: tr('المخزن الافتراضيُّ للفرع يُختار في كلّ عمليةٍ تلقائياً'),
          columns:  [
            PicPosTableColumn(tr('المخزن'), flex: 1.9),
            PicPosTableColumn(tr('الفرع المرتبط'), flex: 1.4),
            PicPosTableColumn(tr('النوع'), flex: 1.2),
            PicPosTableColumn(tr('الحالة'), flex: 1.1),
            PicPosTableColumn(tr('مواقع التخزين'), flex: 1.5),
            PicPosTableColumn(tr('إجراء'), flex: 1.1),
          ],
          chips: [
            for (var i = 0; i < chipDefs.length; i++)
              PicPosTableChip(
                label: chipDefs[i].$1,
                count: '${warehouses.where(chipDefs[i].$2).length}',
                onTap: () => setState(() => _chip[2] = i),
              ),
          ],
          selectedChip: pick,
          emptyLabel: tr('لا مخازنَ مطابقة'),
          rows: [
            for (final w in shown)
              PicPosTableRow(
                cells: [
                  PicPosTextCell(
                    w.name,
                    sub: w.isDefault == true ? tr('افتراضيّ للفرع') : null,
                    icon: PhosphorIconsBold.warehouse,
                    tint: AppColors.primary,
                  ),
                  PicPosTextCell(
                    w.branchId == null
                        ? tr('عامٌّ على المنشأة')
                        : (names[w.branchId] ?? '—'),
                  ),
                  PicPosPillCell(
                    _whTypes[w.type]?.$1 ?? tr('عام'),
                    _whTypes[w.type]?.$2 ?? AppColors.textMuted,
                  ),
                  PicPosPillCell(
                    w.isActive ? tr('نشط') : tr('موقوف'),
                    w.isActive ? AppColors.success : AppColors.textMuted,
                  ),
                  PicPosButtonCell(
                    tr('مواقع التخزين'),
                    icon: PhosphorIconsBold.mapPin,
                    tint: AppColors.primary,
                    onPressed: () => _openWarehouseLocations(w),
                  ),
                  PicPosButtonCell(
                    tr('تعديل'),
                    icon: PhosphorIconsBold.pencilSimple,
                    tint: AppColors.primary,
                    onPressed: () => _editWarehouse(w),
                  ),
                ],
              ),
          ],
        ),
      ],
    );
  }

  Future<void> _openWarehouseLocations(Warehouse warehouse) async {
    if (!await ensurePermission(ref, context, PermissionCodes.warehousesView,
        actionName: tr('مواقع التخزين'))) return;
    if (!mounted) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => WarehouseLocationsScreen(
          warehouseId: warehouse.id,
          warehouseName: warehouse.name,
        ),
      ),
    );
  }

  /// «تعديل» في عمود الإجراء — يفتح حوارَ المخزن نفسَه الذي تفتحه شاشةُ
  /// الفروع القائمة، فلا نسخةَ ثانيةً من النموذج تُصان.
  Future<void> _editWarehouse(Warehouse w) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => WarehouseEditDialog(existing: w),
    );
    // لا `setState` بعد النجاح: المصدرُ `StreamProvider` على الجدول، فيصل
    // الصفُّ المحدَّثُ من تلقائه. واستدعاؤها كان سيُعيد بناءً بلا سبب.
    if (ok == true && mounted) {
      AppToast.show(context, tr('تم تعديل المخزن'), type: ToastType.success);
    }
  }

  // ── تبويبةُ صلاحيات الوصول ─────────────────────────────────────────────

  Widget _accessTab(
    BuildContext context,
    List<Branche> branches,
    List<UserWithRole> users,
  ) {
    final shown = users
        .where((u) => _hit(u.user.displayName) || _hit(u.user.username))
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // ⚠️ **قراءةٌ لكلّ مستخدمٍ عند فتح التبويبة** — لا واجهةَ دفعةٍ في
        //    المستودع تقرأ نطاقَ كلِّ المستخدمين معاً، وبناءُ واحدةٍ يمسّ
        //    طبقةَ البيانات. والقراءةُ تقع مرّةً لا في كلّ إطار.
        FutureBuilder<Map<int, List<int>>>(
          future: _loadAccess(shown),
          builder: (context, snap) {
            if (!snap.hasData) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            final access = snap.data!;
            final names = {
              for (final b in branches) b.id: b.name
            };
            return PicPosDataTable(
              title: tr('صلاحيات الوصول للفروع'),
              subtitle: tr('بلا صفوف = وصول لكل الفروع (توافق خلفي)'),
              columns:  [
                PicPosTableColumn(tr('المستخدم'), flex: 1.8),
                PicPosTableColumn(tr('الدور'), flex: 1.2),
                PicPosTableColumn(tr('الفروع المسموحة'), flex: 2.4),
                PicPosTableColumn(tr('النطاق'), flex: 1.2),
              ],
              emptyLabel: tr('لا مستخدمينَ مطابقين'),
              rows: [
                for (final u in shown)
                  PicPosTableRow(
                    cells: [
                      PicPosTextCell(
                        u.user.displayName,
                        sub: u.user.username,
                        icon: PhosphorIconsBold.userCircle,
                        tint: AppColors.primary,
                      ),
                      PicPosTextCell(
                        u.role?.name ?? tr('بدون دور'),
                      ),
                      PicPosTextCell(
                        (access[u.user.id] ?? const <int>[]).isEmpty
                            ? tr('كل الفروع')
                            : (access[u.user.id]!)
                                .map((id) => names[id] ?? '#$id')
                                .join(' · '),
                      ),
                      PicPosPillCell(
                        (access[u.user.id] ?? const <int>[]).isEmpty
                            ? tr('مفتوح')
                            : tr('محصور'),
                        (access[u.user.id] ?? const <int>[]).isEmpty
                            ? AppColors.warning
                            : AppColors.success,
                      ),
                    ],
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  Future<Map<int, List<int>>> _loadAccess(List<UserWithRole> users) async {
    final repo = ref.read(authRepositoryProvider);
    final out = <int, List<int>>{};
    for (final u in users) {
      out[u.user.id] =
          await repo.getUserAccessibleBranchIds(u.user.id);
    }
    return out;
  }

  Widget _empty(BuildContext context, String label) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: context.picposMuted,
            ),
          ),
        ),
      );
}
