import 'package:picpos_erp/core/i18n/tr.dart';
import 'package:picpos_erp/core/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:intl/intl.dart';
import '../../data/database/database.dart' as db;
import '../../data/providers/providers.dart';
import '../../domain/repositories/landed_cost_repository.dart';
import '../../core/widgets/app_toast.dart';
import 'landed_cost/landed_cost_controller.dart';

final _fmt = NumberFormat('#,##0.00', 'ar');

/// Landed Cost Screen — توزيع التكاليف المحملة
/// Manage landed cost sheets, cost items, and allocations
class LandedCostScreen extends ConsumerWidget {
  const LandedCostScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final repo = ref.watch(landedCostRepositoryProvider);
    final state = ref.watch(landedCostControllerProvider);
    final notifier = ref.read(landedCostControllerProvider.notifier);

    return Scaffold(
      body: Row(
        children: [
          // ─── Sheets List Panel ───
          SizedBox(
            width: 340,
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerLow,
                    border: Border(bottom: BorderSide(color: theme.dividerColor)),
                  ),
                  child: Row(
                    children: [
                      Icon(PhosphorIconsBold.money, color: theme.colorScheme.primary),
                      const SizedBox(width: 8),
                      Text(tr('التكاليف المحملة'),
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold)),
                      const Spacer(),
                      FilledButton.icon(
                        onPressed: () => _showCreateSheetDialog(context, ref, repo, notifier),
                        icon: const Icon(Icons.add, size: 18),
                        label:  Text(tr('جديد')),
                        style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: state.isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : state.sheets.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(PhosphorIconsBold.money,
                                      size: 48,
                                      color: theme.colorScheme.onSurfaceVariant
                                          .withValues(alpha: 0.3)),
                                  const SizedBox(height: 12),
                                  Text(tr('لا توجد أوراق تكاليف محملة'),
                                      style: theme.textTheme.bodyMedium),
                                ],
                              ),
                            )
                          : ListView.builder(
                              itemCount: state.sheets.length,
                              itemBuilder: (ctx, i) =>
                                  _buildSheetTile(theme, state.sheets[i], state, notifier),
                            ),
                ),
              ],
            ),
          ),
          VerticalDivider(width: 1, color: theme.dividerColor),
          Expanded(
            child: state.selectedSheet == null
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(PhosphorIconsBold.arrowLeft,
                            size: 48,
                            color: theme.colorScheme.onSurfaceVariant
                                .withValues(alpha: 0.3)),
                        const SizedBox(height: 12),
                        Text(tr('اختر ورقة تكاليف من القائمة'),
                            style: theme.textTheme.bodyLarge),
                      ],
                    ),
                  )
                : _buildDetailPanel(context, ref, theme, repo, state, notifier),
          ),
        ],
      ),
    );
  }

  Widget _buildSheetTile(ThemeData theme, db.LandedCostSheetData sheet, LandedCostState state, LandedCostController notifier) {
    final isSelected = state.selectedSheet?.id == sheet.id;
    final statusColor = sheet.status == 'applied'
        ? Colors.green
        : (sheet.status == 'cancelled' || sheet.status == 'voided')
            ? AppColors.error
            : Colors.amber;
    final statusLabel = sheet.status == 'applied'
        ? tr('مطبق')
        : sheet.status == 'cancelled'
            ? tr('ملغى')
            : sheet.status == 'voided'
                ? tr('ملغى (إلغاء الفاتورة)')
                : tr('مسودة');

    return ListTile(
      selected: isSelected,
      selectedTileColor: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
      onTap: () => notifier.selectSheet(sheet),
      title: Text(sheet.sheetNumber,
          style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(tr('التكلفة: {p0}', {'p0': _fmt.format(sheet.totalAdditionalCost)}),
          style: theme.textTheme.bodySmall),
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: statusColor.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(statusLabel,
            style: TextStyle(fontSize: 11, color: statusColor, fontWeight: FontWeight.w600)),
      ),
    );
  }

  Widget _buildDetailPanel(BuildContext context, WidgetRef ref, ThemeData theme, ILandedCostRepository repo, LandedCostState state, LandedCostController notifier) {
    final sheet = state.selectedSheet!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerLow,
            border: Border(bottom: BorderSide(color: theme.dividerColor)),
          ),
          child: Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(sheet.sheetNumber,
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(
                    tr('طريقة التوزيع: {p0} | الإجمالي: {p1}', {'p0': _methodLabel(sheet.allocationMethod), 'p1': _fmt.format(sheet.totalAdditionalCost)}),
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
              const Spacer(),
              if (sheet.status == 'draft') ...[
                OutlinedButton.icon(
                  onPressed: () => _addCostItem(context, repo, sheet.id, state, notifier),
                  icon: const Icon(Icons.add, size: 18),
                  label:  Text(tr('إضافة تكلفة')),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: state.isApplying
                      ? null
                      : () => _calculateAndApply(context, ref, repo, sheet.id, state, notifier),
                  icon: const Icon(Icons.calculate, size: 18),
                  label:  Text(tr('حساب وتطبيق')),
                ),
              ],
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(tr('بنود التكاليف'),
              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
        ),
        if (state.costItems.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(tr('لا توجد بنود — أضف تكاليف الشحن والجمارك'),
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          )
        else
          SizedBox(
            height: 120,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: state.costItems.length,
              itemBuilder: (ctx, i) {
                final item = state.costItems[i];
                return Card(
                  margin: const EdgeInsetsDirectional.only(end: 8),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Icon(_costIcon(item.costType), size: 18, color: theme.colorScheme.primary),
                          const SizedBox(width: 8),
                          Text(_costLabel(item.costType),
                              style: const TextStyle(fontWeight: FontWeight.w600)),
                        ]),
                        const SizedBox(height: 8),
                        Text(item.description, style: theme.textTheme.bodySmall),
                        const Spacer(),
                        Text(_fmt.format(item.amount),
                            style: TextStyle(
                                fontWeight: FontWeight.bold, color: theme.colorScheme.primary)),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        const SizedBox(height: 16),
        const Divider(),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(tr('توزيع التكاليف على الأصناف'),
              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
        ),
        Expanded(
          child: state.allocations.isEmpty
              ? Center(child: Text(tr('لم يتم حساب التوزيع بعد'), style: theme.textTheme.bodyMedium))
              : SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: DataTable(
                    columns:  [
                      DataColumn(label: Text(tr('الصنف'))),
                      DataColumn(label: Text(tr('الكمية')), numeric: true),
                      DataColumn(label: Text(tr('التكلفة الأصلية')), numeric: true),
                      DataColumn(label: Text(tr('المبلغ الموزّع')), numeric: true),
                      DataColumn(label: Text(tr('التكلفة الجديدة')), numeric: true),
                    ],
                    rows: state.allocations.map((a) {
                      return DataRow(cells: [
                        DataCell(Text(a['product_name']?.toString() ?? '—')),
                        DataCell(Text(_fmt.format(a['quantity'] ?? 0))),
                        DataCell(Text(_fmt.format(a['original_cost'] ?? 0))),
                        DataCell(Text(_fmt.format(a['allocated_amount'] ?? 0),
                            style: const TextStyle(color: Colors.orange))),
                        DataCell(Text(_fmt.format(a['new_unit_cost'] ?? 0),
                            style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green))),
                      ]);
                    }).toList(),
                  ),
                ),
        ),
      ],
    );
  }

  Future<void> _showCreateSheetDialog(BuildContext context, WidgetRef ref, ILandedCostRepository repo, LandedCostController notifier) async {
    final numberCtrl = TextEditingController();
    String method = 'by_value';
    int? purchaseInvoiceId;

    final purchasesRepo = ref.read(purchasesRepositoryProvider);
    final invoices = await purchasesRepo.watchInvoices().first;

    if (!context.mounted) return;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title:  Row(children: [
            const Icon(Icons.receipt_long, color: Colors.teal),
            const SizedBox(width: 8),
            Text(tr('ورقة تكاليف جديدة')),
          ]),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<int>(
                  decoration:  InputDecoration(
                      labelText: tr('فاتورة الشراء'), border: const OutlineInputBorder()),
                  items: invoices.map((inv) {
                    return DropdownMenuItem(
                      value: inv.id,
                      child: Text(inv.invoiceNumber),
                    );
                  }).toList(),
                  onChanged: (v) => purchaseInvoiceId = v,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: numberCtrl,
                  decoration:  InputDecoration(
                      labelText: tr('رقم الورقة'), border: const OutlineInputBorder(), hintText: 'LC-001'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: method,
                  decoration:  InputDecoration(
                      labelText: tr('طريقة التوزيع'), border: const OutlineInputBorder()),
                  items:  [
                    DropdownMenuItem(value: 'by_value', child: Text(tr('حسب القيمة'))),
                    DropdownMenuItem(value: 'by_quantity', child: Text(tr('حسب الكمية'))),
                    DropdownMenuItem(value: 'equal', child: Text(tr('بالتساوي'))),
                  ],
                  onChanged: (v) {
                    if (v != null) method = v;
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child:  Text(tr('إلغاء'))),
            FilledButton(
              onPressed: () async {
                if (purchaseInvoiceId == null || numberCtrl.text.isEmpty) {
                  AppToast.show(ctx, tr('يرجى ملء جميع الحقول'), type: ToastType.error);
                  return;
                }
                await repo.createLandedCostSheet(
                  purchaseInvoiceId: purchaseInvoiceId!,
                  sheetNumber: numberCtrl.text,
                  allocationMethod: method,
                );
                if (ctx.mounted) Navigator.pop(ctx);
                notifier.refresh();
              },
              child:  Text(tr('إنشاء')),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addCostItem(BuildContext context, ILandedCostRepository repo, int sheetId, LandedCostState state, LandedCostController notifier) async {
    final descCtrl = TextEditingController();
    final amountCtrl = TextEditingController();
    String costType = 'shipping';

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title:  Row(children: [
          const Icon(Icons.add_circle, color: Colors.teal),
          const SizedBox(width: 8),
          Text(tr('إضافة بند تكلفة')),
        ]),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: costType,
                decoration:  InputDecoration(
                    labelText: tr('نوع التكلفة'), border: const OutlineInputBorder()),
                items:  [
                  DropdownMenuItem(value: 'shipping', child: Text(tr('شحن'))),
                  DropdownMenuItem(value: 'customs', child: Text(tr('جمارك'))),
                  DropdownMenuItem(value: 'insurance', child: Text(tr('تأمين'))),
                  DropdownMenuItem(value: 'freight', child: Text(tr('نقل'))),
                  DropdownMenuItem(value: 'handling', child: Text(tr('مناولة'))),
                  DropdownMenuItem(value: 'other', child: Text(tr('أخرى'))),
                ],
                onChanged: (v) {
                  if (v != null) costType = v;
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descCtrl,
                decoration:  InputDecoration(labelText: tr('الوصف'), border: const OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: amountCtrl,
                keyboardType: TextInputType.number,
                decoration:  InputDecoration(labelText: tr('المبلغ'), border: const OutlineInputBorder()),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child:  Text(tr('إلغاء'))),
          FilledButton(
            onPressed: () async {
              final amount = double.tryParse(amountCtrl.text);
              if (descCtrl.text.isEmpty || amount == null) {
                AppToast.show(ctx, tr('يرجى ملء جميع الحقول'), type: ToastType.error);
                return;
              }
              await repo.addLandedCostItem(
                  sheetId: sheetId, costType: costType, description: descCtrl.text, amount: amount);
              if (ctx.mounted) Navigator.pop(ctx);
              notifier.selectSheet(state.selectedSheet!);
            },
            child:  Text(tr('إضافة')),
          ),
        ],
      ),
    );
  }

  Future<void> _calculateAndApply(BuildContext context, WidgetRef ref, ILandedCostRepository repo, int sheetId, LandedCostState state, LandedCostController notifier) async {
    // R2: guard against a second in-flight apply (rapid double-tap) even before
    // the widget rebuilds and disables the button.
    if (ref.read(landedCostControllerProvider).isApplying) return;

    final allocs = await repo.calculateAllocations(sheetId);
    if (allocs.isEmpty) {
      if (context.mounted) AppToast.show(context, tr('لا توجد بنود للتوزيع'), type: ToastType.error);
      return;
    }
    if (!context.mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title:  Text(tr('تأكيد تطبيق التكاليف')),
        content: Text(tr('سيتم توزيع التكاليف على {p0} صنف وتحديث تكلفة المخزون.\n\nهل تريد المتابعة؟', {'p0': allocs.length})),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child:  Text(tr('إلغاء'))),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.green),
            child:  Text(tr('تطبيق')),
          ),
        ],
      ),
    );
    if (ok != true) {
      notifier.selectSheet(state.selectedSheet!);
      return;
    }

    notifier.setApplying(true);
    try {
      // S-COST: applyLandedCost now blends WAC (products.costPrice +
      // inventory_balances.average_cost) AND posts the balanced journal entry
      // atomically. No separate GL call here — that path (cash-fixed, non-atomic)
      // was the bug.
      await repo.applyLandedCost(sheetId);
      if (context.mounted) {
        AppToast.show(context, tr('تم تطبيق التكاليف وتسجيل القيد المحاسبي'));
      }
      notifier.refresh();
    } finally {
      notifier.setApplying(false);
    }
  }

  String _methodLabel(String m) =>
      {'by_value': tr('حسب القيمة'), 'by_quantity': tr('حسب الكمية'), 'equal': tr('بالتساوي')}[m] ?? m;

  String _costLabel(String t) =>
      {'shipping': tr('شحن'), 'customs': tr('جمارك'), 'insurance': tr('تأمين'), 'freight': tr('نقل'), 'handling': tr('مناولة')}[t] ?? tr('أخرى');

  IconData _costIcon(String t) => {
    'shipping': PhosphorIconsBold.truck,
    'customs': PhosphorIconsBold.stamp,
    'insurance': PhosphorIconsBold.shieldCheck,
    'freight': PhosphorIconsBold.boat,
    'handling': PhosphorIconsBold.handGrabbing,
  }[t] ?? PhosphorIconsBold.money;
}
