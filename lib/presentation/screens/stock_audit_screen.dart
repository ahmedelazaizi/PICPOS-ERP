import 'package:flutter/material.dart';
import 'package:ural_erp/core/utils/friendly_error.dart';
import 'package:ural_erp/core/widgets/app_toast.dart';
import 'dart:ui' as ui;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/shimmer_loading.dart';

import '../../data/providers/providers.dart';
import 'inventory/providers/stock_audit_controller.dart';

/// Stock Audit Screen - The Auditor
class StockAuditScreen extends ConsumerStatefulWidget {
  const StockAuditScreen({super.key});

  @override
  ConsumerState<StockAuditScreen> createState() => _StockAuditScreenState();
}

class _StockAuditScreenState extends ConsumerState<StockAuditScreen> {
  final TextEditingController _barcodeController = TextEditingController();
  final FocusNode _barcodeFocusNode = FocusNode();

  @override
  void dispose() {
    _barcodeController.dispose();
    _barcodeFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auditAsync = ref.watch(openAuditProvider);

    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('جرد المخزون (The Auditor)'),
          actions: [
            auditAsync.when(
              data: (audit) => audit != null
                  ? TextButton.icon(
                      onPressed: () => _finalizeAudit(audit.id),
                      icon: const Icon(PhosphorIconsBold.checkCircle),
                      label: const Text('اعتماد الجرد النهائي'),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.success,
                      ),
                    )
                  : const SizedBox.shrink(),
              loading: () => const SizedBox.shrink(),
              error: (_, _) => const SizedBox.shrink(),
            ),
          ],
        ),
        body: auditAsync.when(
          data: (audit) => audit == null
              ? _buildNoAuditState()
              : _buildAuditWorkspace(audit),
          loading: () => Padding(
            padding: const EdgeInsets.all(16),
            child: ShimmerLoading.list(itemCount: 6),
          ),
          error: (e, _) => Center(child: Text(friendlyError(e))),
        ),
      ),
    );
  }

  Widget _buildNoAuditState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            PhosphorIconsBold.archive,
            size: 80,
            color: AppColors.textMuted,
          ),
          const SizedBox(height: 24),
          const Text(
            'لا توجد جلسة جرد مفتوحة حالياً',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'ابدأ جلسة جرد جديدة لمطابقة المتوفر الفعلي مع النظام',
            style: TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 32),
          ElevatedButton.icon(
            onPressed: _startNewAudit,
            icon: const Icon(PhosphorIconsBold.plus),
            label: const Text('بدء جلسة جرد جديدة'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAuditWorkspace(StockAudit audit) {
    final itemsAsync = ref.watch(stockAuditItemsProvider(audit.id));

    return Column(
      children: [
        // Top Toolbar / Barcode Input
        Container(
          padding: const EdgeInsets.all(16),
          color: Theme.of(context).cardColor,
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _barcodeController,
                  focusNode: _barcodeFocusNode,
                  decoration: InputDecoration(
                    hintText: 'امسح الباركود أو أدخل كود الصنف...',
                    prefixIcon: const Icon(PhosphorIconsBold.barcode),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onSubmitted: (val) => _onBarcodeScanned(val, audit.id),
                ),
              ),
              const SizedBox(width: 16),
              ElevatedButton.icon(
                onPressed: () =>
                    _onBarcodeScanned(_barcodeController.text, audit.id),
                icon: const Icon(PhosphorIconsBold.magnifyingGlass),
                label: const Text('إضافة للصف'),
              ),
            ],
          ),
        ),

        // Items Table
        Expanded(
          child: itemsAsync.when(
            data: (items) {
              if (items.isEmpty) {
                return const Center(
                  child: Text('ابدأ بمسح الأصناف للبدء في الجرد'),
                );
              }
              return _buildItemsList(items);
            },
            loading: () => Padding(
              padding: const EdgeInsets.all(16),
              child: ShimmerLoading.list(itemCount: 6),
            ),
            error: (e, _) => Center(child: Text('Error loading items: $e')),
          ),
        ),
      ],
    );
  }

  Widget _buildItemsList(List<StockAuditItem> items) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: items.length,
      separatorBuilder: (context, index) => const Divider(),
      itemBuilder: (context, index) {
        final item = items[index];
        // We'd need to fetch product names. For simplicity here, assume we have them or fetch them.
        return FutureBuilder<Product?>(
          future: ref
              .read(stockAuditControllerProvider.notifier)
              .getProductDetails(item.productId),
          builder: (context, snapshot) {
            final product = snapshot.data;
            return ListTile(
              title: Text(product?.name ?? 'Loading...'),
              subtitle: Text('كود: ${product?.code ?? '...'}'),
              trailing: SizedBox(
                width: 300,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    _buildCountBox(
                      'المتوقع',
                      item.expectedQuantity,
                      color: AppColors.info,
                    ),
                    const SizedBox(width: 16),
                    _buildCountBox(
                      'الفعلي',
                      item.actualQuantity,
                      color: AppColors.primary,
                      isEditable: true,
                      item: item,
                    ),
                    const SizedBox(width: 16),
                    _buildDifferenceBox(item.difference),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildCountBox(
    String label,
    double value, {
    required Color color,
    bool isEditable = false,
    StockAuditItem? item,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 10, color: AppColors.textMuted),
        ),
        const SizedBox(height: 4),
        isEditable
            ? SizedBox(
                width: 80,
                height: 35,
                child: TextField(
                  textAlign: TextAlign.center,
                  decoration: InputDecoration(
                    contentPadding: EdgeInsets.zero,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  controller: TextEditingController(
                    text: value.toStringAsFixed(0),
                  ),
                  onSubmitted: (val) {
                    final newValue = double.tryParse(val);
                    if (newValue != null && item != null) {
                      _updateCount(item, newValue);
                    }
                  },
                ),
              )
            : Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  value.toStringAsFixed(0),
                  style: TextStyle(fontWeight: FontWeight.bold, color: color),
                ),
              ),
      ],
    );
  }

  Widget _buildDifferenceBox(double diff) {
    final color = diff == 0
        ? AppColors.success
        : (diff > 0 ? AppColors.warning : AppColors.error);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'الفارق',
          style: TextStyle(fontSize: 10, color: AppColors.textMuted),
        ),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            (diff > 0 ? '+' : '') + diff.toStringAsFixed(0),
            style: TextStyle(fontWeight: FontWeight.bold, color: color),
          ),
        ),
      ],
    );
  }

  Future<void> _startNewAudit() async {
    await ref.read(stockAuditControllerProvider.notifier).startNewAudit();
    // UI will rebuild via Stream
  }

  Future<void> _onBarcodeScanned(String barcode, int auditId) async {
    if (barcode.isEmpty) return;

    final error = await ref
        .read(stockAuditControllerProvider.notifier)
        .scanBarcode(barcode, auditId);
    if (error != null) {
      if (!mounted) return;
      AppToast.show(context, error);
      return;
    }

    _barcodeController.clear();
    _barcodeFocusNode.requestFocus();
  }

  Future<void> _updateCount(StockAuditItem item, double newValue) async {
    await ref
        .read(stockAuditControllerProvider.notifier)
        .updateCount(item, newValue);
  }

  Future<void> _finalizeAudit(int auditId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تأكيد اعتماد الجرد'),
        content: const Text(
          'سيتم تعديل الكميات في المخزن تلقائياً بناءً على نتائج هذا الجرد. هل أنت متأكد؟',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('تأكيد واعتماد'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final success = await ref
          .read(stockAuditControllerProvider.notifier)
          .finalizeAudit(auditId);

      if (success && mounted) {
        AppToast.show(
          context,
          'تم اعتماد الجرد وتحديث المخزون بنجاح',
          type: ToastType.success,
        );
        Navigator.pop(context);
      }
    }
  }
}
