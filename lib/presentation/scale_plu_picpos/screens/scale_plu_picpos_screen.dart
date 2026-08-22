import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../data/providers/providers.dart';
import '../../../domain/entities/product_entity.dart';
import '../../../domain/repositories/scale_repository.dart';
import '../../../domain/repositories/settings_repository.dart';
import '../../../services/label_scale_service.dart';
import '../../../services/scale_transport.dart';
import '../../picpos_shell/picpos_screen_scaffold.dart';
import '../../picpos_shell/picpos_kpi_row.dart';
import '../../../domain/models/picpos_scale_view.dart';
import '../../screens/plu_manager_screen.dart';

// ── Part files (mixin-based extraction) ─────────────────────────────────
part 'scale_panels_picpos.dart';
part 'scale_logic_picpos.dart';

/// PicPos PLU-export / scale-management screen.
///
/// ── Why this is a copy, not a shared widget ────────────────────────────
/// The UralCash screen (`scale_plu_export_screen.dart` + its two `part`
/// files `scale_plu/scale_panels.dart` and `scale_plu/scale_logic.dart`,
/// 1715 lines together) is a `ConsumerStatefulWidget` whose state mixes in
/// two PRIVATE mixins (`_ScalePanelsMixin`, `_ScaleLogicMixin`) declared as
/// `part of` that exact library file. A `part of` file cannot be reattached
/// to a different library, so the only way to reuse this logic from a
/// separate screen is either (a) rewrite the mixins as public, importable
/// mixins — a structural change to UralCash's file — or (b) copy the shell
/// and both `part` files verbatim into a new library and retarget the
/// `part`/`part of` pair. The redesign plan (owner-approved "copy-cost")
/// picked (b): this file plus `scale_panels_picpos.dart` and
/// `scale_logic_picpos.dart` are that copy. Only renamed: the widget/state
/// class names, the two mixins (`_ScalePanelsMixin` →
/// `_ScalePanelsPicposMixin`, `_ScaleLogicMixin` → `_ScaleLogicPicposMixin`),
/// the `part`/`part of` wiring, and the relative import depth (this fork
/// lives one directory deeper: `lib/presentation/scale_plu_picpos/screens/`
/// vs `lib/presentation/screens/`). Every method body, dialog
/// (`showScaleDialog`, `_showDataPreview`, the scale-add/edit dialog) and
/// panel (`buildHeader`, `buildCategoryPanel`, `buildItemsGrid`,
/// `buildScalePanel`) is byte-identical logic to the source.
///
/// **Copy-trap:** any LOGICAL bug fix belongs in the UralCash source
/// (`lib/presentation/screens/scale_plu/scale_logic.dart` /
/// `scale_panels.dart`) FIRST, then gets patched here — never the other way
/// around. In particular, the barcode-prefix fix (weight items use
/// `scale_weight_prefix`, price/count items use `scale_price_prefix`, and
/// `scaleItemIsSoldByWeight` treats `weightByPiece` as NOT sold by weight)
/// lives in `scale_logic_picpos.dart` around the same lines as the source
/// and must stay in sync with it.
///
/// Reused as-is (not forked): `PluManagerScreen` — it already picks up the
/// PicPos theme automatically since it shares the app's single `ThemeData`,
/// so there is no identity conflict to fix. Also reused as-is:
/// `scaleRepositoryProvider`, `settingsRepositoryProvider`,
/// `visibleCategoriesProvider`, `allProductsProvider`, `LabelScaleService`,
/// `ScaleTransport`, `scaleItemIsSoldByWeight`, `ProductEntity`,
/// `IScaleRepository`/`ISettingsRepository`.
///
/// ── Layout choice (corrected after review) ─────────────────────────────
/// `build()` wraps the content in `PicPosScreenScaffold` (title «ميزان
/// PLU», subtitle «تصدير الأصناف وأكواد PLU للموازين» — the exact pair the
/// brief mandates), which supplies `Directionality(rtl)` + `Scaffold` + the
/// PicPos page header. An earlier version of this file kept the shell's own
/// bare `Directionality + Scaffold + Padding` and relied on `buildHeader()`
/// to "cover" the header requirement — that was wrong: `buildHeader()`
/// (copied verbatim into `scale_panels_picpos.dart`) renders the ORIGINAL's
/// title text `'تصدير مواد الميزان PLU'`, which matches neither required
/// string, so the PicPos identity never actually surfaced. `buildHeader()`
/// is still called inside the scaffold's `body` — unchanged, verbatim — for
/// its action buttons (export, verify, select-all, preview, PLU-manager,
/// search) so nothing is dropped; its own title text is now a redundant
/// sub-heading directly under the real PicPos header, which is an accepted
/// cosmetic side effect of reusing the mixin without editing its body.
class ScalePluPicposScreen extends ConsumerStatefulWidget {
  const ScalePluPicposScreen({super.key});

  @override
  ConsumerState<ScalePluPicposScreen> createState() =>
      _ScalePluPicposScreenState();
}

class _ScalePluPicposScreenState extends ConsumerState<ScalePluPicposScreen>
    with _ScalePanelsPicposMixin, _ScaleLogicPicposMixin {

  @override
  List<LabelScale> scales = [];
  @override
  int selectedScaleIndex = -1;
  @override
  final Set<int> selectedCategoryIds = {};
  @override
  final Set<int> selectedProductIds = {};
  @override
  bool isExporting = false;
  @override
  String searchQuery = '';
  @override
  final TextEditingController searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    loadScales();
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  @override
  Future<void> loadScales() async {
    final scaleRepo = ref.read(scaleRepositoryProvider);
    final rows = await scaleRepo.getAllScales();
    if (mounted) {
      setState(() {
        scales = rows;
        if (scales.isNotEmpty && selectedScaleIndex < 0) {
          selectedScaleIndex = 0;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final categoriesAsync = ref.watch(visibleCategoriesProvider);
    final productsAsync = ref.watch(allProductsProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return PicPosScreenScaffold(
      title: 'ميزان PLU',
      subtitle: 'تصدير الأصناف وأكواد PLU للموازين',
      icon: PhosphorIconsBold.scales,
      body: Column(
        children: [
          _buildScaleStats(productsAsync.value ?? const []),
          const SizedBox(height: 12),
          buildHeader(),
          const SizedBox(height: 16),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 220,
                  child: buildCategoryPanel(categoriesAsync, isDark),
                ),
                const SizedBox(width: 12),
                Expanded(child: buildItemsGrid(productsAsync, isDark)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(height: 200, child: buildScalePanel(isDark)),
        ],
      ),
    );
  }

  /// عدّاداتُ التصميم (`scaleStats`).
  ///
  /// ⚠️ **تُعدُّ بنفس شرطِ الجدول** ([picposIsScaleItem]) لا بشرطٍ مكتوبٍ
  /// هنا — وإلّا عرض العدّادُ رقماً والجدولُ صفوفاً لا تطابقه.
  ///
  /// و«محدَّد للترحيل» يُقرأ من `selectedProductIds` مباشرةً: هو ما سيُرسَل
  /// فعلاً عند الضغط على «ترحيل للميزان»، لا تقديرٌ له.
  Widget _buildScaleStats(List<ProductEntity> products) {
    final stats = PicPosScaleStats.from(
      products: products,
      selectedForExport: selectedProductIds.length,
      definedScales: scales.length,
    );

    return PicPosKpiRow(
      kpis: [
        PicPosKpi(
          label: 'أصناف الميزان',
          value: '${stats.scaleItems}',
          icon: PhosphorIconsBold.scales,
          tint: AppColors.primary,
        ),
        PicPosKpi(
          label: 'محدَّد للترحيل',
          value: '${stats.selectedForExport}',
          icon: PhosphorIconsBold.checkSquare,
          tint: AppColors.success,
        ),
        PicPosKpi(
          label: 'بلا رقم PLU',
          value: '${stats.missingPlu}',
          icon: PhosphorIconsBold.listNumbers,
          tint: stats.missingPlu > 0 ? AppColors.warning : AppColors.success,
        ),
        PicPosKpi(
          label: 'موازين معرَّفة',
          value: '${stats.definedScales}',
          icon: PhosphorIconsBold.wifiHigh,
          tint: stats.definedScales > 0 ? AppColors.info : AppColors.error,
        ),
      ],
    );
  }
}
