// منطق منسوخ من categories_screen.dart (monolith) — أي إصلاح منطقي يتصلّح في
// المصدر أولاً ثم patch (مصيدة النسخ §٥.٨).
//
// الشاشة الأصل (lib/presentation/screens/categories_screen.dart) مونوليث
// 1241 سطر بلا part/mixin files — كل الحوارات (إضافة/تعديل/حذف فارغ/نقل
// وحذف جماعي) ومنطق وضع الترتيب (`_isReorderMode`/`_buildReorderGrid`)
// ولوحة الألوان (`_buildColorPalette`) مكتوبة inline داخل
// `_CategoriesScreenState`. بما إنه مفيش `part of` نقدر نستورده، فالفورك هنا
// بينسخ جسم الدوال دي حرفياً بلا أي تعديل منطقي — يتغيّر بس اسم الكلاس
// وطبقة العرض (تستخدم picpos_shell بدل SectionHeader/Scaffold+Padding).
// `categoriesControllerProvider` و`CategoryCard` و`CategoryIconPicker`
// مُعاد استخدامهم من UralCash زي ما هم (import، مش نسخ).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ural_erp/core/widgets/app_toast.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/shimmer_loading.dart';

import '../../products/providers/categories_controller.dart';
import '../../widgets/enhanced_components.dart';
import '../../widgets/category_icon_picker.dart';
import '../../widgets/category_card.dart';
import '../../../services/label_scale_service.dart';
import '../../../data/providers/providers.dart';
import '../../picpos_shell/picpos_screen_scaffold.dart';
import '../../picpos_shell/picpos_content_card.dart';
import '../../picpos_shell/picpos_toolbar.dart';

/// شاشة التصنيفات بهوية PicPos. تُختار بالعلامة في app_main_screen
/// (`Brand.isPicPos`). تعيد استخدام نفس `categoriesControllerProvider`
/// (وتوابعه `CategoriesState`/`CategoriesNotifier`) و`CategoryCard` و
/// `CategoryIconPicker` من UralCash — فقط طبقة العرض تبدّلت لـ picpos_shell
/// (هيدر + PicPosContentCard حول الشبكة بدل SectionHeader + Scaffold).
///
/// FULL PARITY مع الأصل: إضافة/تعديل تصنيف، حذف تصنيف فارغ (حوار تأكيد
/// بسيط)، حذف تصنيف بأصناف نشطة (حوار نقل ثم حذف مع اختيار وجهة)، تحذير
/// الأصناف المفوترة على الفرع الحالي، وضع الترتيب اليدوي (تحريك لأعلى/أسفل
/// + حفظ)، لوحة الألوان، منتقي الأيقونات، وترحيل أصناف الميزان.
///
/// راجع lib/presentation/screens/categories_screen.dart (الأصل).
class CategoriesPicposScreen extends ConsumerStatefulWidget {
  const CategoriesPicposScreen({super.key});

  @override
  ConsumerState<CategoriesPicposScreen> createState() =>
      _CategoriesPicposScreenState();
}

class _CategoriesPicposScreenState
    extends ConsumerState<CategoriesPicposScreen> {
  bool _isReorderMode = false;
  List<Category>? _reorderableCategories;

  void _showAddCategoryDialog(BuildContext context) {
    final nameController = TextEditingController();
    final colorController = TextEditingController(text: '#2563EB');
    int? selectedPrinterId;
    String? selectedIcon;
    bool isGlobal = true;
    List<int> selectedBranchIds = [];

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: const Row(
              children: [
                Icon(PhosphorIconsBold.squaresFour, color: AppColors.primary),
                SizedBox(width: 8),
                Text('إضافة تصنيف جديد'),
              ],
            ),
            content: SizedBox(
              width: 400,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(
                        labelText: 'اسم التصنيف *',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: colorController,
                      decoration: const InputDecoration(
                        labelText: 'لون التصنيف',
                        hintText: '#2563EB',
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildColorPalette(colorController),
                    const SizedBox(height: 16),
                    // Icon picker
                    CategoryIconPicker(
                      selectedIcon: selectedIcon,
                      onIconSelected: (icon) =>
                          setDialogState(() => selectedIcon = icon),
                    ),
                    // Printer selection — use Consumer for proper watch inside dialog
                    Consumer(
                      builder: (context, watchRef, _) {
                        final printersAsync = watchRef.watch(allPrintersProvider);
                        return printersAsync.when(
                          data: (printers) {
                            final activePrinters = printers.where((p) => p.isActive).toList();
                            return DropdownButtonFormField<int?>(
                              decoration: const InputDecoration(
                                labelText: 'طابعة المطبخ (أمر الشغل)',
                                prefixIcon: Icon(PhosphorIconsLight.printer),
                              ),
                              initialValue: selectedPrinterId,
                              items: [
                                const DropdownMenuItem(
                                  value: null,
                                  child: Text('بدون طابعة'),
                                ),
                                ...activePrinters.map(
                                  (p) => DropdownMenuItem(
                                    value: p.id,
                                    child: Text(p.name),
                                  ),
                                ),
                              ],
                              onChanged: (v) => setDialogState(
                                () => selectedPrinterId = v,
                              ),
                            );
                          },
                          loading: () => const Padding(
                            padding: EdgeInsets.all(8),
                            child: LinearProgressIndicator(),
                          ),
                          error: (e, _) => Text('خطأ في تحميل الطابعات: $e',
                            style: const TextStyle(color: AppColors.error, fontSize: 12)),
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                    const Divider(),
                    const SizedBox(height: 8),
                    SwitchListTile(
                      title: const Text('ظهور في جميع الفروع',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: const Text('إذا تم التفعيل سيظهر التصنيف في كل الفروع والأسواق تلقائياً',
                        style: TextStyle(fontSize: 12)),
                      value: isGlobal,
                      onChanged: (v) => setDialogState(() => isGlobal = v),
                    ),
                    if (!isGlobal) ...[
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8.0),
                        child: Text('اختر الفروع التي يظهر فيها التصنيف:',
                          style: TextStyle(fontSize: 13, color: Colors.grey)),
                      ),
                      Consumer(
                        builder: (context, ref, _) {
                          final branchesAsync = ref.watch(allBranchesProvider);
                          return branchesAsync.when(
                            data: (branches) => Column(
                              children: branches.map((b) => CheckboxListTile(
                                title: Text(b.name),
                                dense: true,
                                value: selectedBranchIds.contains(b.id),
                                onChanged: (v) {
                                  setDialogState(() {
                                    if (v == true) {
                                      selectedBranchIds.add(b.id);
                                    } else {
                                      selectedBranchIds.remove(b.id);
                                    }
                                  });
                                },
                              )).toList(),
                            ),
                            loading: () => const Center(child: CircularProgressIndicator()),
                            error: (e, _) => Text('خطأ في تحميل الفروع: $e'),
                          );
                        },
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('إلغاء'),
              ),
              ElevatedButton(
                onPressed: () async {
                  if (nameController.text.isEmpty) return;
                  // Capture the navigator BEFORE the await so we don't touch
                  // `context` after an async gap (prevents stale-context bugs).
                  final nav = Navigator.of(context);
                  final success = await ref
                      .read(categoriesControllerProvider.notifier)
                      .createCategory(
                        name: nameController.text,
                        color: colorController.text,
                        printerId: selectedPrinterId,
                        iconName: selectedIcon,
                        isGlobal: isGlobal,
                        branchIds: selectedBranchIds,
                      );
                  if (!context.mounted) return;
                  // ALWAYS close the dialog — regardless of success — so the
                  // user never gets trapped staring at a frozen dialog.
                  nav.pop();
                  if (success) {
                    // Fire-and-forget activity log (doesn't block the UI).
                    unawaited(() async {
                      try {
                        final user = ref.read(authProvider).user;
                        final logger = ref.read(activityLoggerProvider);
                        await logger.logCategoryAdd(
                          user?.id ?? 0,
                          user?.displayName ?? 'مجهول',
                          nameController.text,
                        );
                      } catch (e) {
                        debugPrint('⚠️ Category log failed: $e');
                      }
                    }());
                    AppToast.show(
                      context,
                      'تم إضافة التصنيف',
                      type: ToastType.success,
                    );
                  } else {
                    final err = ref.read(categoriesControllerProvider).error
                        ?? 'فشل إضافة التصنيف';
                    AppToast.show(context, err, type: ToastType.error);
                  }
                },
                child: const Text('حفظ'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showEditCategoryDialog(BuildContext context, Category category) async {
    final nameController = TextEditingController(text: category.name);
    final colorController = TextEditingController(text: category.color);
    int? selectedPrinterId = category.printerId;
    String? selectedIcon = category.iconName;
    bool isGlobal = category.isGlobal;

    // Fetch existing branch links
    final repository = ref.read(productRepositoryProvider);
    final initialBranchIds = await repository.getCategoryBranchIds(category.id);
    List<int> selectedBranchIds = List.from(initialBranchIds);

    if (!context.mounted) return;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: const Row(
              children: [
                Icon(PhosphorIconsBold.pencilSimple, color: AppColors.warning),
                SizedBox(width: 8),
                Text('تعديل التصنيف'),
              ],
            ),
            content: SizedBox(
              width: 400,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(
                        labelText: 'اسم التصنيف *',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: colorController,
                      decoration: const InputDecoration(
                        labelText: 'لون التصنيف',
                        hintText: '#2563EB',
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildColorPalette(colorController),
                    const SizedBox(height: 16),
                    // Icon picker
                    CategoryIconPicker(
                      selectedIcon: selectedIcon,
                      onIconSelected: (icon) =>
                          setDialogState(() => selectedIcon = icon),
                    ),
                    // Printer selection — use Consumer for proper watch inside dialog
                    Consumer(
                      builder: (context, watchRef, _) {
                        final printersAsync = watchRef.watch(allPrintersProvider);
                        return printersAsync.when(
                          data: (printers) {
                            final activePrinters = printers.where((p) => p.isActive).toList();
                            return DropdownButtonFormField<int?>(
                              decoration: const InputDecoration(
                                labelText: 'طابعة المطبخ (أمر الشغل)',
                                prefixIcon: Icon(PhosphorIconsLight.printer),
                              ),
                              initialValue: activePrinters.any((p) => p.id == selectedPrinterId)
                                  ? selectedPrinterId
                                  : null,
                              items: [
                                const DropdownMenuItem(
                                  value: null,
                                  child: Text('بدون طابعة'),
                                ),
                                ...activePrinters.map(
                                  (p) => DropdownMenuItem(
                                    value: p.id,
                                    child: Text(p.name),
                                  ),
                                ),
                              ],
                              onChanged: (v) => setDialogState(
                                () => selectedPrinterId = v,
                              ),
                            );
                          },
                          loading: () => const Padding(
                            padding: EdgeInsets.all(8),
                            child: LinearProgressIndicator(),
                          ),
                            error: (e, _) => Text('خطأ في تحميل الطابعات: $e',
                            style: const TextStyle(color: AppColors.error, fontSize: 12)),
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                    const Divider(),
                    const SizedBox(height: 8),
                    SwitchListTile(
                      title: const Text('ظهور في جميع الفروع',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: const Text('إذا تم التفعيل سيظهر التصنيف في كل الفروع والأسواق تلقائياً',
                        style: TextStyle(fontSize: 12)),
                      value: isGlobal,
                      onChanged: (v) => setDialogState(() => isGlobal = v),
                    ),
                    if (!isGlobal) ...[
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8.0),
                        child: Text('اختر الفروع التي يظهر فيها التصنيف:',
                          style: TextStyle(fontSize: 13, color: Colors.grey)),
                      ),
                      Consumer(
                        builder: (context, ref, _) {
                          final branchesAsync = ref.watch(allBranchesProvider);
                          return branchesAsync.when(
                            data: (branches) => Column(
                              children: branches.map((b) => CheckboxListTile(
                                title: Text(b.name),
                                dense: true,
                                value: selectedBranchIds.contains(b.id),
                                onChanged: (v) {
                                  setDialogState(() {
                                    if (v == true) {
                                      selectedBranchIds.add(b.id);
                                    } else {
                                      selectedBranchIds.remove(b.id);
                                    }
                                  });
                                },
                              )).toList(),
                            ),
                            loading: () => const Center(child: CircularProgressIndicator()),
                            error: (e, _) => Text('خطأ في تحميل الفروع: $e'),
                          );
                        },
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('إلغاء'),
              ),
              ElevatedButton(
                onPressed: () async {
                  if (nameController.text.isEmpty) return;
                  final nav = Navigator.of(context);
                  final success = await ref
                      .read(categoriesControllerProvider.notifier)
                      .updateCategory(
                        id: category.id,
                        name: nameController.text,
                        color: colorController.text,
                        printerId: selectedPrinterId,
                        iconName: selectedIcon,
                        isGlobal: isGlobal,
                        branchIds: selectedBranchIds,
                      );
                  if (success) {
                    // #Forensic Log: Category Edit
                    try {
                      final user = ref.read(authProvider).user;
                      final logger = ref.read(activityLoggerProvider);
                      await logger.logCategoryEdit(
                        user?.id ?? 0,
                        user?.displayName ?? 'مجهول',
                        nameController.text,
                      );
                    } catch (e) { debugPrint('Category log failed: $e'); }
                  }
                  nav.pop();
                  if (context.mounted) {
                    AppToast.show(
                      context,
                      success ? 'تم تعديل التصنيف' : 'فشل تعديل التصنيف',
                      type: success ? ToastType.success : ToastType.error,
                    );
                  }
                },
                child: const Text('حفظ'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Feature 045 — دیالوج الحذف يفتح بعد COUNT(*) مسبق للأصناف النشطة تحت
  // التصنيف. تدفّقان:
  //   - 0 صنف → دیالوج تأكيد بسيط (حذف ناعم).
  //   - ≥1 صنف → دیالوج نقل ثم حذف مع قائمة وجهة منسدلة. لازم يختار وجهة
  //     قبل ما يتفعّل زر الحذف.
  Future<void> _showDeleteCategoryDialog(
      BuildContext context, Category category) async {
    // Pre-flight count happens BEFORE the dialog opens so we know which
    // flow to render. A short delay shouldn't be perceptible (~milliseconds
    // for an indexed COUNT on `categoryId`).
    int activeCount;
    try {
      activeCount = await ref
          .read(categoriesControllerProvider.notifier)
          .countActiveProductsInCategory(category.id);
    } catch (e) {
      if (!context.mounted) return;
      AppToast.show(context, 'تعذّر قراءة عدد المنتجات: $e',
          type: ToastType.error);
      return;
    }

    // Field-report 2026-05-14: operator wants an extra warning if any
    // product under this category has invoices booked on the CURRENT
    // branch. Deletion is propagated globally to every branch, so an
    // operator clicking from a branch device needs to know that the
    // category they're about to remove is in active use locally — not
    // just somewhere in the cluster.
    int branchInvoicedCount = 0;
    try {
      final prefs = await SharedPreferences.getInstance();
      final branchId = prefs.getInt('client_branch_id');
      if (branchId != null) {
        branchInvoicedCount = await ref
            .read(categoriesControllerProvider.notifier)
            .countCategoryInvoicedItemsOnBranch(category.id, branchId);
      }
    } catch (e) {
      // Non-fatal — keep the dialog usable even if the warning count
      // fails. The user's existing flow still works.
      debugPrint('[CategoriesPicposScreen] branch-invoiced count failed: $e');
    }

    if (!context.mounted) return;

    if (activeCount == 0) {
      _showEmptyCategoryDeleteDialog(context, category, branchInvoicedCount);
    } else {
      _showBulkMoveDeleteDialog(
          context, category, activeCount, branchInvoicedCount);
    }
  }

  /// Reusable banner displayed at the top of both delete dialogs when the
  /// category has invoiced items on the operator's current branch.
  Widget? _branchInvoicedBanner(int branchInvoicedCount) {
    if (branchInvoicedCount <= 0) return null;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.12),
        border: Border.all(color: AppColors.warning),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(PhosphorIconsBold.warningCircle,
              color: AppColors.warning),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'هذا التصنيف به أصناف عليها '
              '$branchInvoicedCount حركة فاتورة على فرعك الحالي.\n'
              'الحذف ينتشر لكل الفروع — تأكد قبل المتابعة.',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  void _showEmptyCategoryDeleteDialog(
      BuildContext context, Category category,
      [int branchInvoicedCount = 0]) {
    bool isDeleting = false;
    final banner = _branchInvoicedBanner(branchInvoicedCount);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: const Row(
              children: [
                Icon(PhosphorIconsBold.warning, color: AppColors.error),
                SizedBox(width: 8),
                Text('تأكيد الحذف'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ?banner,
                Text(
                  'هل تريد حذف التصنيف "${category.name}"؟\n\n'
                  'لا يوجد منتجات نشطة تحت هذا التصنيف.',
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: isDeleting ? null : () => Navigator.pop(context),
                child: const Text('إلغاء'),
              ),
              ElevatedButton(
                style:
                    ElevatedButton.styleFrom(backgroundColor: AppColors.error),
                onPressed: isDeleting
                    ? null
                    : () => _runDelete(context, category, null,
                        setDialogState: setDialogState,
                        toggleIsDeleting: (v) => isDeleting = v),
                child: isDeleting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('حذف'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showBulkMoveDeleteDialog(BuildContext context, Category deleting,
      int activeCount, [int branchInvoicedCount = 0]) {
    final branchBanner = _branchInvoicedBanner(branchInvoicedCount);
    // Destination options: every ACTIVE category except the one being
    // deleted, plus a sentinel "بدون تصنيف" (categoryId=null). Default
    // selection priority: a category named exactly "عام" (the seeded
    // default) → otherwise the sentinel. The user can still override.
    final categoriesAsync = ref.read(allCategoriesProvider);
    final candidates = categoriesAsync
        .whenOrNull(
          data: (list) => list
              .where((c) => c.id != deleting.id && c.isActive)
              .toList(),
        ) ??
        const <Category>[];
    Category? generalDefault;
    for (final c in candidates) {
      if (c.name.trim() == 'عام') {
        generalDefault = c;
        break;
      }
    }
    int? selectedDestId = generalDefault?.id; // null sentinel = uncategorized
    bool isDeleting = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: Row(
              children: [
                const Icon(PhosphorIconsBold.warning, color: AppColors.error),
                const SizedBox(width: 8),
                Expanded(child: Text('حذف تصنيف "${deleting.name}"')),
              ],
            ),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ?branchBanner,
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.warning.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(PhosphorIconsBold.warning,
                            color: AppColors.warning, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'هذا التصنيف يحتوي على $activeCount منتج نشط.',
                            style: const TextStyle(
                                fontSize: 13, color: AppColors.warning),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text('انقل المنتجات إلى:',
                      style: TextStyle(fontSize: 13)),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<int?>(
                    initialValue: selectedDestId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                    ),
                    items: [
                      const DropdownMenuItem<int?>(
                        value: null,
                        child: Text('بدون تصنيف (uncategorized)'),
                      ),
                      ...candidates.map(
                        (c) => DropdownMenuItem<int?>(
                          value: c.id,
                          child: Text(c.name),
                        ),
                      ),
                    ],
                    onChanged: isDeleting
                        ? null
                        : (v) => setDialogState(() => selectedDestId = v),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'بعد النقل سيتم حذف تصنيف "${deleting.name}" '
                    '(يمكن استرجاعه من سجل النشاطات).',
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: isDeleting ? null : () => Navigator.pop(context),
                child: const Text('إلغاء'),
              ),
              ElevatedButton.icon(
                icon: const Icon(PhosphorIconsBold.arrowRight, size: 16),
                style:
                    ElevatedButton.styleFrom(backgroundColor: AppColors.error),
                onPressed: isDeleting
                    ? null
                    : () => _runDelete(context, deleting, selectedDestId,
                        setDialogState: setDialogState,
                        toggleIsDeleting: (v) => isDeleting = v),
                label: isDeleting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('نقل وحذف'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _runDelete(
    BuildContext context,
    Category category,
    int? moveToCategoryId, {
    required void Function(VoidCallback) setDialogState,
    required void Function(bool) toggleIsDeleting,
  }) async {
    setDialogState(() => toggleIsDeleting(true));
    final nav = Navigator.of(context);
    try {
      final success = await ref
          .read(categoriesControllerProvider.notifier)
          .deleteCategory(
            category.id,
            category.name,
            moveToCategoryId: moveToCategoryId,
          );
      if (!context.mounted) return;
      nav.pop();
      if (success) {
        unawaited(() async {
          try {
            final user = ref.read(authProvider).user;
            final logger = ref.read(activityLoggerProvider);
            await logger.logCategoryDelete(
              user?.id ?? 0,
              user?.displayName ?? 'مجهول',
              category.name,
            );
          } catch (e) {
            debugPrint('⚠️ Category delete log failed: $e');
          }
        }());
        if (!context.mounted) return;
        AppToast.show(context, 'تم حذف التصنيف', type: ToastType.success);
      } else {
        final error = ref.read(categoriesControllerProvider).error;
        if (!context.mounted) return;
        AppToast.show(context, error ?? 'فشل حذف التصنيف',
            type: ToastType.error);
      }
    } catch (e) {
      if (!context.mounted) return;
      nav.pop();
      AppToast.show(context, 'فشل حذف التصنيف: $e', type: ToastType.error);
    }
  }

  static Widget _buildColorPalette(TextEditingController controller) {
    final colors = [
      '#2563EB',
      '#10B981',
      '#F59E0B',
      '#EF4444',
      '#8B5CF6',
      '#EC4899',
      '#06B6D4',
      '#84CC16',
      '#F97316',
      '#6366F1',
    ];

    return StatefulBuilder(
      builder: (context, setState) => Wrap(
        spacing: 8,
        runSpacing: 8,
        children: colors.map((color) {
          final isSelected = controller.text == color;
          return InkWell(
            onTap: () {
              controller.text = color;
              setState(() {});
            },
            borderRadius: BorderRadius.circular(8),
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: (() {
                  try {
                    return Color(int.parse(color.replaceFirst('#', '0xFF')));
                  } catch (_) {
                    return const Color(0xFF2563EB); // Fallback color
                  }
                })(),
                borderRadius: BorderRadius.circular(8),
                border: isSelected
                    ? Border.all(color: Colors.black, width: 2)
                    : null,
              ),
              child: isSelected
                  ? const Icon(
                      PhosphorIconsBold.check,
                      color: Colors.white,
                      size: 16,
                    )
                  : null,
            ),
          );
        }).toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(allCategoriesProvider);

    return PicPosScreenScaffold(
      title: 'التصنيفات',
      subtitle: 'تنظيم تصنيفات الأصناف',
      icon: PhosphorIconsBold.squaresFour,
      toolbar: PicPosToolbar(children: [
        if (_isReorderMode) ...[
          FilledButton.icon(
            onPressed: _saveReorder,
            icon: const Icon(PhosphorIconsBold.floppyDisk, size: 18),
            label: const Text('حفظ الترتيب'),
            style: FilledButton.styleFrom(backgroundColor: AppColors.success),
          ),
          OutlinedButton.icon(
            onPressed: () => setState(() {
              _isReorderMode = false;
              _reorderableCategories = null;
            }),
            icon: const Icon(PhosphorIconsBold.x, size: 18),
            label: const Text('إلغاء'),
          ),
        ] else ...[
          OutlinedButton.icon(
            onPressed: () {
              final cats = categories.when(
                data: (d) => d,
                error: (_, _) => null,
                loading: () => null,
              );
              if (cats == null || cats.isEmpty) return;
              setState(() {
                _isReorderMode = true;
                _reorderableCategories = List.from(cats);
              });
            },
            icon: const Icon(PhosphorIconsBold.arrowsDownUp, size: 18),
            label: const Text('ترتيب'),
          ),
          ElevatedButton.icon(
            onPressed: () => _showAddCategoryDialog(context),
            icon: const Icon(PhosphorIconsBold.plus),
            label: const Text('إضافة تصنيف'),
          ),
        ],
      ]),
      body: PicPosContentCard(
        padding: const EdgeInsets.all(16),
        child: _isReorderMode && _reorderableCategories != null
            ? _buildReorderGrid()
            : categories.when(
                data: (cats) => GridView.builder(
                  gridDelegate:
                      const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 220,
                        childAspectRatio: 1.2,
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                      ),
                  itemCount: cats.length,
                  itemBuilder: (context, index) {
                    final cat = cats[index];
                    Color color;
                    try {
                      color = Color(int.parse(cat.color.replaceFirst('#', '0xFF')));
                    } catch (_) {
                      color = const Color(0xFF2563EB); // Fallback color
                    }
                    final isLocked = cat.isLocked;
                    final isExcluded = cat.isExcluded;
                    // Get icon based on saved iconName or fallback to auto-detection
                    final categoryIcon = cat.iconName != null
                        ? CategoryIconPicker.getIconData(cat.iconName)
                        : EnhancedCategoryFilter.getIconForCategory(
                            cat.name,
                          );

                    return CategoryCard(
                      cat: cat,
                      color: color,
                      isLocked: isLocked,
                      isExcluded: isExcluded,
                      categoryIcon: categoryIcon,
                      onLockToggle: () async {
                        await ref
                            .read(categoriesControllerProvider.notifier)
                            .toggleCategoryLock(
                              cat.id,
                              !isLocked,
                              cat.name,
                            );
                        if (context.mounted) {
                          AppToast.show(
                            context,
                            isLocked
                                ? 'تم فتح التصنيف - يمكن بيع الأصناف الآن'
                                : 'تم قفل التصنيف وجميع أصنافه - يمكنك فتح أصناف معينة من شاشة الأصناف',
                            type: ToastType.warning,
                          );
                        }
                      },
                      onExcludeAll: () async {
                        await ref
                            .read(categoriesControllerProvider.notifier)
                            .toggleCategoryExclusion(
                              cat.id,
                              !isExcluded,
                              cat.name,
                            );
                        if (context.mounted) {
                          if (!isExcluded) {
                            AppToast.show(
                              context,
                              'تم استثناء التصنيف - أصنافه مخفية من العرض ولكن يمكن البحث عنها',
                              type: ToastType.warning,
                            );
                          } else {
                            AppToast.show(
                              context,
                              'تم إلغاء استثناء التصنيف - جميع الأصناف ظاهرة الآن',
                              type: ToastType.success,
                            );
                          }
                        }
                      },
                      onEdit: () =>
                          _showEditCategoryDialog(context, cat),
                      onDelete: () =>
                          _showDeleteCategoryDialog(context, cat),
                      onScaleUpload: () => _uploadCategoryToScale(cat),
                      onPosVisibilityToggle: () async {
                        await ref
                            .read(categoriesControllerProvider.notifier)
                            .toggleShowInPos(
                              cat.id,
                              !cat.showInPos,
                              cat.name,
                            );
                        if (context.mounted) {
                          AppToast.show(
                            context,
                            cat.showInPos
                                ? 'تم إخفاء التصنيف من البيع السريع'
                                : 'تم إظهار التصنيف في البيع السريع',
                            type: cat.showInPos
                                ? ToastType.warning
                                : ToastType.success,
                          );
                        }
                      },
                    );
                  },
                ),
                loading: () => Padding(
                  padding: const EdgeInsets.all(16),
                  child: ShimmerLoading.list(itemCount: 5),
                ),
                error: (e, _) => Center(child: Text('خطأ: $e')),
              ),
      ),
    );
  }

  /// Build the reorder grid with swap buttons
  Widget _buildReorderGrid() {
    final cats = _reorderableCategories!;
    return GridView.builder(
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 5,
        childAspectRatio: 1.2,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
      ),
      itemCount: cats.length,
      itemBuilder: (context, index) {
        final cat = cats[index];
        Color color;
        try {
          color = Color(int.parse(cat.color.replaceFirst('#', '0xFF')));
        } catch (_) {
          color = const Color(0xFF2563EB); // Fallback
        }
        return Container(
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.4)),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Position badge
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${index + 1}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                cat.name,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: color,
                  fontSize: 14,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    onPressed: index > 0
                        ? () => _swapCategories(index, index - 1)
                        : null,
                    icon: const Icon(PhosphorIconsBold.arrowUp, size: 20),
                    tooltip: 'تحريك لأعلى',
                    style: IconButton.styleFrom(
                      backgroundColor: index > 0
                          ? AppColors.primary.withValues(alpha: 0.1)
                          : null,
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: index < cats.length - 1
                        ? () => _swapCategories(index, index + 1)
                        : null,
                    icon: const Icon(PhosphorIconsBold.arrowDown, size: 20),
                    tooltip: 'تحريك لأسفل',
                    style: IconButton.styleFrom(
                      backgroundColor: index < cats.length - 1
                          ? AppColors.primary.withValues(alpha: 0.1)
                          : null,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  void _swapCategories(int from, int to) {
    setState(() {
      final temp = _reorderableCategories![from];
      _reorderableCategories![from] = _reorderableCategories![to];
      _reorderableCategories![to] = temp;
    });
  }

  Future<void> _saveReorder() async {
    final cats = _reorderableCategories;
    if (cats == null || cats.isEmpty) return;

    await ref
        .read(categoriesControllerProvider.notifier)
        .updateSortOrders(cats.map((c) => c.id).toList());

    if (mounted) {
      setState(() {
        _isReorderMode = false;
        _reorderableCategories = null;
      });
      AppToast.show(
        context,
        'تم حفظ ترتيب التصنيفات بنجاح',
        type: ToastType.success,
      );
    }
  }

  /// Upload all weight products in a category to label scale
  Future<void> _uploadCategoryToScale(Category category) async {
    final repository = ref.read(productRepositoryProvider);
    final productEntities = await repository.getProducts(
      categoryId: category.id,
      limit: 10000,
    );
    // Map ProductEntity to Product (Drift class for scale service compatibility if needed,
    // but the ScalePLUItem mapping below looks like it uses properties common to both)
    final weightProducts = productEntities
        .where(
          (p) =>
              p.scaleType == 'weight' ||
              p.scaleType == 'weightByPiece' ||
              p.isSoldByWeight,
        )
        .toList();

    if (weightProducts.isEmpty) {
      if (mounted) {
        AppToast.show(
          context,
          'لا توجد أصناف للميزان في هذا التصنيف',
          type: ToastType.warning,
        );
      }
      return;
    }

    final settings = await LabelScaleService.instance.loadSettings();
    final brand = settings['brand'] as LabelScaleBrand;
    final connection = settings['connection'] as LabelScaleConnection;
    final ipAddress = settings['ipAddress'] as String?;
    final comPort = settings['comPort'] as String?;

    // Validate scale connection settings before attempting upload
    if (connection == LabelScaleConnection.tcp || connection == LabelScaleConnection.ftp) {
      if (ipAddress == null || ipAddress.isEmpty) {
        if (mounted) {
          AppToast.show(context, 'يجب إعداد عنوان IP للميزان أولاً من شاشة ميزان التسعير', type: ToastType.error);
        }
        return;
      }
    } else if (connection == LabelScaleConnection.serial) {
      if (comPort == null || comPort.isEmpty) {
        if (mounted) {
          AppToast.show(context, 'يجب إعداد منفذ COM للميزان أولاً من شاشة ميزان التسعير', type: ToastType.error);
        }
        return;
      }
    }

    final pluItems = weightProducts
        .map(
          (p) => ScalePLUItem(
            pluNumber: (p.scalePluNumber != null && p.scalePluNumber! > 0) ? p.scalePluNumber! : p.id,
            name: p.name,
            unitPrice: p.pricePerUnit ?? p.salePrice,
            isByWeight: scaleItemIsSoldByWeight(
              scaleType: p.scaleType,
              isSoldByWeight: p.isSoldByWeight,
            ),
            barcode: p.barcode,
            productCode: p.code,
          ),
        )
        .toList();

    if (mounted) {
      AppToast.show(
        context,
        'جاري ترحيل ${pluItems.length} صنف من ${category.name} للميزان...',
        type: ToastType.info,
      );
    }

    try {
      final result = await LabelScaleService.instance.uploadPLUItems(
        brand: brand,
        connection: connection,
        items: pluItems,
        ipAddress: settings['ipAddress'] as String?,
        port: settings['port'] as int?,
        comPort: settings['comPort'] as String?,
        baudRate: settings['baudRate'] as int?,
      );

      // Log activity
      try {
        final user = ref.read(authProvider).user;
        final logger = ref.read(activityLoggerProvider);
        await logger.log(
          userId: user?.id,
          userName: user?.displayName ?? 'مستخدم',
          action: 'category_upload_scale',
          entityType: 'category',
          entityId: category.id,
          description:
              'ترحيل ${result.success}/${result.total} صنف من ${category.name} للميزان',
        );
      } catch (e) { debugPrint('⚠️ Category operation failed: $e'); }

      if (mounted) {
        AppToast.show(
          context,
          'تم ترحيل ${result.success}/${result.total} صنف بنجاح',
          type: result.failed == 0 ? ToastType.success : ToastType.warning,
        );
      }
    } catch (e) {
      if (mounted) {
        AppToast.show(context, 'خطأ في الترحيل: $e', type: ToastType.error);
      }
    }
  }
}
