import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/app_toast.dart';
import '../../data/providers/providers.dart';
import '../../domain/entities/product_entity.dart';
import '../../domain/repositories/scale_repository.dart';
import '../../domain/repositories/settings_repository.dart';
import '../../services/label_scale_service.dart';
import '../../services/scale_transport.dart';
import 'plu_manager_screen.dart';

// ── Part files (mixin-based extraction) ─────────────────────────────────
part 'scale_plu/scale_panels.dart';
part 'scale_plu/scale_logic.dart';

/// PLU Export / Scale Management Screen
/// Allows managing multiple scales, selecting categories, and exporting PLU items.
class ScalePluExportScreen extends ConsumerStatefulWidget {
  const ScalePluExportScreen({super.key});

  @override
  ConsumerState<ScalePluExportScreen> createState() =>
      _ScalePluExportScreenState();
}

class _ScalePluExportScreenState extends ConsumerState<ScalePluExportScreen>
    with _ScalePanelsMixin, _ScaleLogicMixin {

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
