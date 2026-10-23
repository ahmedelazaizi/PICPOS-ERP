import 'package:picpos_erp/core/i18n/tr.dart';
import 'package:flutter/material.dart';
import 'package:picpos_erp/core/utils/friendly_error.dart';
import 'package:picpos_erp/core/widgets/app_toast.dart';
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
  // BUG-C twin: persistent per-item "الفعلي" controllers + focus nodes (keyed by
  // audit-item id). Seeded once, they survive rebuilds so a value typed-but-not-
  // Entered isn't lost, and are flushed to the DB before finalize. The focus node
  // lets us refresh the field from a barcode-scan-updated DB value only while the
  // user isn't actively editing.
  final Map<int, TextEditingController> _actualCtrls = {};
  final Map<int, FocusNode> _actualFocus = {};

  @override
  void dispose() {
    _barcodeController.dispose();
    _barcodeFocusNode.dispose();
    for (final c in _actualCtrls.values) {
      c.dispose();
    }
    for (final f in _actualFocus.values) {
      f.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auditAsync = ref.watch(openAuditProvider);

    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title:  Text(tr('جرد المخزون (The Auditor)')),
          actions: [
            auditAsync.when(
              data: (audit) => audit != null
                  ? TextButton.icon(
                      onPressed: () => _finalizeAudit(audit.id),
                      icon: const Icon(PhosphorIconsBold.checkCircle),
                      label:  Text(tr('اعتماد الجرد النهائي')),
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
           Text(
            tr('لا توجد جلسة جرد مفتوحة حالياً'),
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
           Text(
            tr('ابدأ جلسة جرد جديدة لمطابقة المتوفر الفعلي مع النظام'),
            style: const TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 32),
          ElevatedButton.icon(
            onPressed: _startNewAudit,
            icon: const Icon(PhosphorIconsBold.plus),
            label:  Text(tr('بدء جلسة جرد جديدة')),
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
                    hintText: tr('امسح الباركود أو أدخل كود الصنف...'),
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
                onPressed: () => _onAddItem(_barcodeController.text, audit.id),
                icon: const Icon(PhosphorIconsBold.plus),
                label:  Text(tr('إضافة صنف')),
              ),
            ],
          ),
        ),

        // Items Table
        Expanded(
          child: itemsAsync.when(
            data: (items) {
              if (items.isEmpty) {
                return  Center(
                  child: Text(tr('ابدأ بمسح الأصناف للبدء في الجرد')),
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
              subtitle: Text(tr('كود: {p0}', {'p0': product?.code ?? '...'})),
              trailing: SizedBox(
                width: 300,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    _buildCountBox(
                      tr('المتوقع'),
                      item.expectedQuantity,
                      color: AppColors.info,
                    ),
                    const SizedBox(width: 16),
                    _buildCountBox(
                      tr('الفعلي'),
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
            ? _buildActualField(value, item)
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

  /// Editable "الفعلي" field backed by a persistent per-item controller.
  Widget _buildActualField(double value, StockAuditItem? item) {
    final decoration = InputDecoration(
      contentPadding: EdgeInsets.zero,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
    );
    if (item == null) {
      return SizedBox(
        width: 80,
        height: 35,
        child: TextField(
          textAlign: TextAlign.center,
          decoration: decoration,
          controller: TextEditingController(text: value.toStringAsFixed(0)),
        ),
      );
    }
    // Persistent (survives rebuilds) so a typed-but-not-Entered count isn't lost.
    final ctrl = _actualCtrls.putIfAbsent(
      item.id,
      () => TextEditingController(text: value.toStringAsFixed(0)),
    );
    final focus = _actualFocus.putIfAbsent(item.id, () => FocusNode());
    // Refresh from the DB value (e.g. a barcode scan bumped actualQuantity) only
    // while the user isn't editing — never clobber in-progress typing.
    final formatted = value.toStringAsFixed(0);
    if (!focus.hasFocus && ctrl.text != formatted) {
      ctrl.text = formatted;
    }
    return SizedBox(
      width: 80,
      height: 35,
      child: TextField(
        textAlign: TextAlign.center,
        decoration: decoration,
        controller: ctrl,
        focusNode: focus,
        onSubmitted: (val) {
          final newValue = double.tryParse(val);
          if (newValue != null) _updateCount(item, newValue);
        },
      ),
    );
  }

  Widget _buildDifferenceBox(double diff) {
    final color = diff == 0
        ? AppColors.success
        : (diff > 0 ? AppColors.warning : AppColors.error);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
         Text(
          tr('الفارق'),
          style: const TextStyle(fontSize: 10, color: AppColors.textMuted),
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

  /// Genuine barcode SCAN (field submit / Enter from a scanner gun): accumulate
  /// the actual count by 1 for each physical unit scanned.
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

  /// Manual "add item" (search a code, click Add): add the row ONCE with
  /// actual = expected. Does NOT accumulate.
  Future<void> _onAddItem(String query, int auditId) async {
    if (query.isEmpty) return;

    final error = await ref
        .read(stockAuditControllerProvider.notifier)
        .addItemToAudit(query, auditId);
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

  /// Persist any typed-but-not-Entered "الفعلي" counts before finalize.
  Future<void> _flushPendingActualCounts(List<StockAuditItem> items) async {
    for (final item in items) {
      final ctrl = _actualCtrls[item.id];
      if (ctrl == null) continue;
      final txt = ctrl.text.trim();
      if (txt.isEmpty) continue;
      final qty = double.tryParse(txt);
      if (qty == null) continue;
      // Only write when it differs from what's already stored.
      if ((item.actualQuantity - qty).abs() > 0.0001) {
        await _updateCount(item, qty);
      }
    }
  }

  Future<void> _finalizeAudit(int auditId) async {
    // Option B: the count subsystem isn't sync-aware yet, so finalize is blocked
    // on client/mirror (would write inventory + JE local-only, reverted on pull).
    if (ref.read(isClientModeProvider)) {
      AppToast.show(
        context,
        tr('لا يمكن اعتماد الجرد من جهاز عميل أو مرآة — نفّذه على الخادم الرئيسي'),
        type: ToastType.error,
      );
      return;
    }
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title:  Text(tr('تأكيد اعتماد الجرد')),
        content:  Text(
          tr('سيتم تعديل الكميات في المخزن تلقائياً بناءً على نتائج هذا الجرد. هل أنت متأكد؟'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child:  Text(tr('إلغاء')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child:  Text(tr('تأكيد واعتماد')),
          ),
        ],
      ),
    );

    if (confirm == true) {
      // BUG-C twin: flush any typed-but-not-Entered "الفعلي" values to the DB
      // FIRST, so finalizeAudit sees them. Otherwise a count typed then confirmed
      // without pressing Enter stays at its seeded value → difference=0 → no stock
      // adjustment, yet the success toast still fires (silent lost adjustment).
      final items =
          ref.read(stockAuditItemsProvider(auditId)).value ??
              const <StockAuditItem>[];
      await _flushPendingActualCounts(items);
      final success = await ref
          .read(stockAuditControllerProvider.notifier)
          .finalizeAudit(auditId);

      if (success && mounted) {
        AppToast.show(
          context,
          tr('تم اعتماد الجرد وتحديث المخزون بنجاح'),
          type: ToastType.success,
        );
        Navigator.pop(context);
      }
    }
  }
}
