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
/// ── Layout choice ───────────────────────────────────────────────────────
/// Kept the shell's own `Directionality(rtl) + Scaffold + Padding + Column`
/// layout rather than wrapping in `PicPosScreenScaffold`. This is a dense
/// tool screen (category filter + items grid + scale-management table), not
/// a list/browse screen, and the mixins already call `buildHeader()` /
/// `buildCategoryPanel()` / `buildItemsGrid()` / `buildScalePanel()`
/// directly — wrapping would either duplicate the header or require
/// threading a title through an extra layer for no behavioural gain. The
/// screen still renders under the app's single `ThemeData`, so it picks up
/// PicPos colors automatically. `buildHeader()` already renders the title
/// text used throughout this screen ("تصدير مواد الميزان PLU"), which
/// covers the brief's header requirement.
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

    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
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
        ),
      ),
    );
  }
}
