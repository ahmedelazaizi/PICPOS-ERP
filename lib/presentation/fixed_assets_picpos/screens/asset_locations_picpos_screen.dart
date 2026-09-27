// شاشةُ «التوزيع والمواقع» — مدخلٌ جانبيٌّ مستقلٌّ بقرار المالك 2026-09-18.
//
// ═══ 🔴 ولماذا ليست نسخةً من التبويبة التي خرجت منها ═══
//
// التبويبةُ كانت **عرضاً محضاً**: تجمّع الأصولَ على `location` وترسم
// شريطاً وجدولاً. والعمودُ **نصٌّ حرّ** يكتبه حوارُ الإنشاء بيد المستخدم —
// فـ«الفرع الرئيسي» و«الفرع الرئيسى» و«الفرع الرئيسي » ثلاثةُ صفوفٍ بثلاث
// قيمٍ دفتريّة لمكانٍ واحد. والجدولُ **صحيحٌ حرفاً بحرف** ولا شيءَ يبدو
// معطوباً، ويقرأ المديرُ توزيعاً لم يقع.
//
// ⇒ فالشاشةُ تُعيد التسمية: تكتب الاسمَ الجديدَ على **كلّ أصلٍ** يحمل
//    القديم. وهو العلاجُ الوحيدُ الممكنُ بلا جدولِ مواقعَ جديد — والتخطيطُ
//    له خالصٌ في `domain/models/asset_location_plan.dart`.
//
// ⚠️ **والدمجُ يُقال قبل وقوعه**: اسمٌ جديدٌ يطابق موقعاً قائماً يصيّر
// الموقعَين واحداً، ولا سبيلَ لفكِّهما بعدها إلّا بإعادةِ تسميةِ كلِّ أصلٍ
// على حدة. فيُعرَض عددُ ما سيُنقَل وعددُ ما هناك سلفاً.
//
// ⚠️ **ولا تطبيعَ آليّ**: «الرئيسي» و«الرئيسى» يختلفان بحرفٍ لا بمسافة،
// وأيُّ قاعدةِ تشابهٍ كانت ستدمج «مخزن ١» و«مخزن ٢». فالتوحيدُ قرارُ
// مستخدمٍ صريح.
//
// ═══ ⚠️ ولا يستوردُ هذا الملفُّ `data/database` ═══
//
// حارسُ `presentation_db_import_guard` يمنع كلَّ ملفِّ عرضٍ جديدٍ من ذلك.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/permissions/permission_codes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../data/providers/providers.dart';
import '../../../domain/models/asset_location_plan.dart';
import '../../picpos_shell/picpos_bar_list.dart';
import '../../picpos_shell/picpos_content_card.dart';
import '../../picpos_shell/picpos_data_table.dart';
import '../../picpos_shell/picpos_dialog.dart';
import '../../picpos_shell/picpos_empty_state.dart';
import '../../picpos_shell/picpos_kpi_row.dart';
import '../../picpos_shell/picpos_screen_scaffold.dart';
import '../../widgets/permission_guard.dart';

final _money0 = NumberFormat('#,##0', 'en');

const _ok = Color(0xFF22C55E);
const _warn = Color(0xFFF59E0B);
const _err = Color(0xFFEF4444);

const double _nearEndThreshold = 0.85;

String _ar(Object n) =>
    '$n'.replaceAllMapped(RegExp(r'\d'), (m) => '٠١٢٣٤٥٦٧٨٩'[int.parse(m[0]!)]);

String _pct(double v) => '${_ar(v.toStringAsFixed(0))}٪';

final _assetsProvider = StreamProvider.autoDispose<List<FixedAssetData>>(
    (ref) => ref.watch(fixedAssetsRepositoryProvider).watchFixedAssets());

double _bookValue(FixedAssetData a) =>
    a.purchasePrice - a.accumulatedDepreciation;

class AssetLocationsPicposScreen extends ConsumerStatefulWidget {
  const AssetLocationsPicposScreen({super.key});

  @override
  ConsumerState<AssetLocationsPicposScreen> createState() =>
      _AssetLocationsPicposScreenState();
}

class _AssetLocationsPicposScreenState
    extends ConsumerState<AssetLocationsPicposScreen> {
  @override
  Widget build(BuildContext context) {
    final all = ref.watch(_assetsProvider).value ?? const <FixedAssetData>[];
    // الأصولُ على الدفاتر وحدَها: المستبعدُ لا يشغل موقعاً.
    final onBooks = all.where((a) => a.status == 'active').toList();

    final byLocation = <String, List<FixedAssetData>>{};
    for (final a in onBooks) {
      byLocation.putIfAbsent(assetLocationLabel(a.location), () => []).add(a);
    }
    final entries = byLocation.entries.toList()
      ..sort((x, y) => _sumBook(y.value).compareTo(_sumBook(x.value)));

    final totalBook = onBooks.fold<double>(0, (s, a) => s + _bookValue(a));
    final totalCost = onBooks.fold<double>(0, (s, a) => s + a.purchasePrice);
    final unassigned = byLocation[kUnassignedAssetLocation]?.length ?? 0;

    return PermissionGuard(
      permission: PermissionCodes.assetsView,
      child: PicPosScreenScaffold(
        title: 'التوزيع والمواقع',
        subtitle: 'الأصل يتبع موقعاً ومركزَ تكلفة — ويُستعمل ذلك في توزيع '
            'الإهلاك',
        icon: PhosphorIconsBold.mapPin,
        subHeader: PicPosKpiRow(
          kpis: [
            PicPosKpi(
              label: 'المواقع',
              value: _ar(entries.length),
              icon: PhosphorIconsBold.mapPin,
              tint: AppColors.primary,
            ),
            PicPosKpi(
              label: 'أصولٌ على الدفاتر',
              value: _ar(onBooks.length),
              icon: PhosphorIconsBold.buildings,
              tint: AppColors.info,
            ),
            PicPosKpi(
              label: 'بلا موقع',
              value: _ar(unassigned),
              icon: PhosphorIconsBold.warningCircle,
              tint: unassigned == 0 ? AppColors.success : _warn,
            ),
            PicPosKpi(
              label: 'القيمة الدفترية',
              value: _money0.format(totalBook),
              icon: PhosphorIconsBold.coins,
              tint: AppColors.success,
            ),
          ],
        ),
        body: onBooks.isEmpty
            ? const PicPosEmptyState(
                icon: PhosphorIconsBold.mapPin,
                title: 'لا أصولَ نشطةً لتوزَّع',
                hint: 'الأصل يتبع موقعاً ومركزَ تكلفة — ويُستعمل ذلك في '
                    'توزيع الإهلاك على مراكز التكلفة.',
              )
            : SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    PicPosContentCard(
                      child: PicPosBarList(
                        title: 'القيمة الدفترية حسب الموقع',
                        subtitle: 'الأصل يتبع موقعاً ومركز تكلفة · ج.م',
                        emptyHint: 'لا مواقعَ مسجَّلة',
                        items: [
                          for (final e in entries)
                            PicPosBarItem(
                              label: e.key,
                              sub: '${_ar(e.value.length)} أصول',
                              value: _sumBook(e.value),
                              display: _money0.format(_sumBook(e.value)),
                              caption: totalBook > 0
                                  ? '${_pct(_sumBook(e.value) / totalBook * 100)} من الدفترية'
                                  : '',
                              icon: PhosphorIconsBold.storefront,
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    _table(entries, onBooks, totalCost, totalBook),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _table(
    List<MapEntry<String, List<FixedAssetData>>> entries,
    List<FixedAssetData> onBooks,
    double totalCost,
    double totalBook,
  ) {
    return PicPosDataTable(
      title: 'الأصول حسب الموقع',
      subtitle: 'يُستخدم في توزيع الإهلاك على مراكز التكلفة',
      minWidth: 980,
      columns: const [
        PicPosTableColumn('الموقع', flex: 1.6),
        PicPosTableColumn('الأصول', align: PicPosCellAlign.end),
        PicPosTableColumn('التكلفة', flex: 1.3, align: PicPosCellAlign.end),
        PicPosTableColumn('الدفترية', flex: 1.3, align: PicPosCellAlign.end),
        PicPosTableColumn('نسبة الاستهلاك', flex: 1.4),
        PicPosTableColumn('', flex: 1.1),
      ],
      rows: [
        for (final e in entries)
          () {
            final cost =
                e.value.fold<double>(0, (s, a) => s + a.purchasePrice);
            final accum = e.value
                .fold<double>(0, (s, a) => s + a.accumulatedDepreciation);
            final ratio = cost > 0 ? (accum / cost).clamp(0.0, 1.0) : 0.0;
            return PicPosTableRow(cells: [
              PicPosTextCell(e.key,
                  icon: PhosphorIconsBold.storefront,
                  tint: AppColors.primary),
              PicPosTextCell(_ar(e.value.length)),
              PicPosTextCell(_money0.format(cost)),
              PicPosTextCell(_money0.format(cost - accum), bold: true),
              PicPosBarCell(
                _pct(ratio * 100),
                ratio,
                ratio >= _nearEndThreshold
                    ? _err
                    : ratio >= 0.5
                        ? _warn
                        : _ok,
              ),
              PicPosButtonCell(
                // «بلا موقع» تسميتُها **إسنادٌ** لا تصحيح — والزرُّ يقولها.
                e.key == kUnassignedAssetLocation ? 'إسناد موقع' : 'إعادة تسمية',
                icon: PhosphorIconsBold.pencilSimple,
                tint: AppColors.primary,
                onPressed: () => _rename(e.key, onBooks),
              ),
            ]);
          }(),
      ],
      totals: [
        '${_ar(entries.length)} مواقع',
        _ar(onBooks.length),
        _money0.format(totalCost),
        _money0.format(totalBook),
        '',
        '',
      ],
    );
  }

  double _sumBook(List<FixedAssetData> list) =>
      list.fold<double>(0, (s, a) => s + _bookValue(a));

  Future<void> _rename(String from, List<FixedAssetData> onBooks) async {
    final rows = <AssetLocationRow>[
      for (final a in onBooks) (id: a.id, location: a.location),
    ];
    final plan = await showDialog<AssetLocationRenamePlan>(
      context: context,
      builder: (_) => _RenameLocationDialog(from: from, rows: rows),
    );
    if (plan == null || !plan.isAllowed || !mounted) return;

    final repo = ref.read(fixedAssetsRepositoryProvider);
    var done = 0;
    try {
      for (final id in plan.assetIds) {
        await repo.updateFixedAsset(id, location: plan.target);
        done++;
      }
      if (!mounted) return;
      AppToast.show(context, 'نُقل ${_ar(done)} أصلاً إلى «${plan.target}»');
    } catch (e) {
      if (!mounted) return;
      // ⚠️ **يُقال كم وقع فعلاً**: الكتابةُ صفٌّ صفّاً، فالإخفاقُ في
      //    المنتصف يترك الموقعَ مقسوماً — و«فشل» وحدَها تُقرأ «لم يقع شيء».
      AppToast.show(
        context,
        'توقّف بعد ${_ar(done)} من ${_ar(plan.assetIds.length)}: $e',
        type: ToastType.error,
      );
    }
  }
}

class _RenameLocationDialog extends StatefulWidget {
  const _RenameLocationDialog({required this.from, required this.rows});

  final String from;
  final List<AssetLocationRow> rows;

  @override
  State<_RenameLocationDialog> createState() => _RenameLocationDialogState();
}

class _RenameLocationDialogState extends State<_RenameLocationDialog> {
  late final TextEditingController _to = TextEditingController(
    // «بلا موقع» وسمٌ معروضٌ لا اسمٌ مخزَّن، فلا يُملأ به الحقل.
    text: widget.from == kUnassignedAssetLocation ? '' : widget.from,
  );

  @override
  void dispose() {
    _to.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final plan = planAssetLocationRename(
      from: widget.from,
      to: _to.text,
      rows: widget.rows,
    );
    final moving = widget.rows
        .where((r) => assetLocationLabel(r.location) == widget.from)
        .length;

    return PicPosDialog(
      icon: PhosphorIconsBold.mapPin,
      title: widget.from == kUnassignedAssetLocation
          ? 'إسنادُ موقعٍ للأصول بلا موقع'
          : 'إعادةُ تسميةِ موقع',
      subtitle: '«${widget.from}» · ${_ar(moving)} أصلاً',
      width: 560,
      body: [
          TextField(
            controller: _to,
            autofocus: true,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'الاسم الجديد',
              isDense: true,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          if (plan.error != null)
            Text(plan.error!,
                style: const TextStyle(fontSize: 12, color: _err))
          else if (plan.isMerge)
            // 🔴 **الدمجُ يُقال قبل وقوعه** — وهو لا يُفَكّ بعدها.
            Text(
              'الاسمُ قائمٌ سلفاً: سيُدمَج ${_ar(plan.assetIds.length)} أصلاً '
              'مع ${_ar(plan.mergesInto)} هناك — ولا سبيلَ لفصلهما بعدها '
              'إلّا بإعادة تسميةِ كلِّ أصلٍ على حدة.',
              style: const TextStyle(fontSize: 12, color: _warn),
            )
          else
            Text(
              'سيُكتَب الاسمُ على ${_ar(plan.assetIds.length)} أصلاً.',
              style: const TextStyle(
                  fontSize: 12, color: AppColors.textMuted),
            ),
      ],
      primaryAction: PicPosDialogAction(
        label: plan.isMerge ? 'دمج' : 'حفظ',
        icon: PhosphorIconsBold.check,
        onPressed:
            plan.isAllowed ? () => Navigator.pop(context, plan) : null,
      ),
    );
  }
}
