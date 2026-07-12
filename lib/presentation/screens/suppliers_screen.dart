// ignore_for_file: avoid_dynamic_calls
import 'package:flutter/material.dart';
import 'package:ural_erp/core/widgets/app_toast.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/shimmer_loading.dart';

import '../../data/providers/providers.dart';
import '../../services/client_write_interceptor.dart';
import '../widgets/enhanced_components.dart';
import 'party_statement_screen.dart';
import '../../core/constants/app_constants.dart';
import '../widgets/dialogs/app_confirm_dialog.dart';
import 'widgets/dialogs/party_edit_dialog.dart';

/// Suppliers management screen
class SuppliersScreen extends ConsumerStatefulWidget {
  const SuppliersScreen({super.key});

  @override
  ConsumerState<SuppliersScreen> createState() => _SuppliersScreenState();
}

class _SuppliersScreenState extends ConsumerState<SuppliersScreen> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _showAddSupplierDialog() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => const PartyEditDialog(
        isSupplier: true,
        isCustomer: false,
      ),
    );
    if (result == true && mounted) {
      AppToast.show(
        context,
        'تم إضافة المورد بنجاح',
        type: ToastType.success,
      );
    }
  }

  void _showEditSupplierDialog(Party supplier) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => PartyEditDialog(
        existing: supplier,
        isSupplier: true,
        isCustomer: false,
      ),
    );
    if (result == true && mounted) {
      AppToast.show(
        context,
        'تم تحديث بيانات المورد',
        type: ToastType.success,
      );
    }
  }

  void _showDeleteSupplierDialog(Party supplier) async {
    final confirmed = await AppConfirmDialog.show(
      context,
      title: 'تأكيد الحذف',
      message: 'هل أنت متأكد من حذف المورد "${supplier.name}"؟',
      confirmLabel: 'حذف',
      isDangerous: true,
      customContent: supplier.balance != 0
          ? Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(
                    PhosphorIconsBold.warning,
                    color: AppColors.warning,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'لديه رصيد: ${supplier.balance.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolEn}',
                      style: const TextStyle(color: AppColors.warning),
                    ),
                  ),
                ],
              ),
            )
          : null,
    );

    if (confirmed == true) {
      final partiesRepo = ref.read(partiesRepositoryProvider);
      // ── Client mode: route to server ──
      final deleted = await ClientWriteInterceptor.deleteParty(supplier.id);
      if (!deleted) {
        final deactivated = supplier.copyWith(isActive: false);
        await partiesRepo.updateParty(deactivated);
      }

      // Log activity
      try {
        final user = ref.read(authProvider).user;
        final logger = ref.read(activityLoggerProvider);
        await logger.log(
          userId: user?.id ?? 0,
          userName: user?.displayName ?? 'مجهول',
          action: 'delete',
          entityType: 'party',
          description: 'حذف مورد: ${supplier.name}',
        );
      } catch (_) {}

      if (mounted) {
        AppToast.show(
          context,
          'تم إلغاء تفعيل المورد',
          type: ToastType.warning,
        );
      }
    }
  }

  Future<void> _exportTemplate() async {
    final service = ref.read(excelServiceProvider);
    final path = await service.exportPartiesTemplate(true);
    if (path != null && mounted) {
      AppToast.show(
        context,
        'تم تصدير النموذج بنجاح: $path',
        type: ToastType.success,
      );
      // Log activity
      try {
        final user = ref.read(authProvider).user;
        final logger = ref.read(activityLoggerProvider);
        await logger.log(
          userId: user?.id,
          userName: user?.displayName ?? 'مجهول',
          action: 'export_template',
          entityType: 'party',
          description: 'تصدير قالب موردين',
        );
      } catch (_) {}
    }
  }

  Future<void> _importData() async {
    final service = ref.read(excelServiceProvider);
    final result = await service.importParties(true);
    if (mounted) {
      AppToast.show(
        context,
        result.message,
        type: result.success == true ? ToastType.success : ToastType.error,
      );
      if (result.success) {
        ref.invalidate(allSuppliersProvider);
        // Log activity
        try {
          final user = ref.read(authProvider).user;
          final logger = ref.read(activityLoggerProvider);
          await logger.log(
            userId: user?.id,
            userName: user?.displayName ?? 'مجهول',
            action: 'import_data',
            entityType: 'party',
            description: 'استيراد بيانات موردين من Excel',
          );
        } catch (_) {}
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final suppliers = ref.watch(allSuppliersProvider);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header with enhanced section header
              SectionHeader(
                title: 'إدارة الموردين',
                icon: PhosphorIconsBold.truck,
                fontSize: 24,
                action: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _exportTemplate,
                      icon: const Icon(PhosphorIconsBold.fileArrowUp, size: 18),
                      label: const Text('قالب الإدخال الذكي'),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: _importData,
                      icon: const Icon(
                        PhosphorIconsBold.fileArrowDown,
                        size: 18,
                      ),
                      label: const Text('استيراد بيانات'),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton.icon(
                      onPressed: _showAddSupplierDialog,
                      icon: const Icon(PhosphorIconsBold.plus),
                      label: const Text('إضافة مورد'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Search
              TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'البحث عن مورد...',
                  prefixIcon: const Icon(PhosphorIconsBold.magnifyingGlass),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  fillColor: Theme.of(context).cardColor,
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 16),

              // Suppliers List
              Expanded(
                child: Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: suppliers.when(
                    data: (list) {
                      // Filter by search
                      final filtered = _searchController.text.isEmpty
                          ? list
                          : list
                                .where(
                                  (s) =>
                                      s.name.contains(_searchController.text) ||
                                      (s.phone?.contains(
                                            _searchController.text,
                                          ) ??
                                          false),
                                )
                                .toList();

                      if (filtered.isEmpty) {
                        return EmptyStateWidget(
                          icon: PhosphorIconsBold.truck,
                          message: 'لا يوجد موردين',
                          actionLabel: 'إضافة مورد',
                          onAction: _showAddSupplierDialog,
                        );
                      }

                      return ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: filtered.length,
                        separatorBuilder: (ctx, idx) =>
                            const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final s = filtered[index];
                          return _SupplierListTile(
                            supplier: s,
                            onEdit: () => _showEditSupplierDialog(s),
                            onDelete: () => _showDeleteSupplierDialog(s),
                            onStatement: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => PartyStatementScreen(
                                  isSupplier: true,
                                  partyId: s.id,
                                  partyName: s.name,
                                ),
                              ),
                            ),
                          );
                        },
                      );
                    },
                    loading: () => Padding(
                      padding: const EdgeInsets.all(16),
                      child: ShimmerLoading.list(itemCount: 6),
                    ),
                    error: (e, _) => Center(child: Text('خطأ: $e')),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Enhanced supplier list tile with hover effect and avatar
class _SupplierListTile extends StatefulWidget {
  final Party supplier;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onStatement;

  const _SupplierListTile({
    required this.supplier,
    required this.onEdit,
    required this.onDelete,
    required this.onStatement,
  });

  @override
  State<_SupplierListTile> createState() => _SupplierListTileState();
}

class _SupplierListTileState extends State<_SupplierListTile> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final s = widget.supplier;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: _isHovered ? AppColors.primary.withValues(alpha: 0.05) : null,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            // Avatar with initials
            AvatarBadge(
              name: s.name,
              size: 44,
              backgroundColor: AppColors.warning,
            ),
            const SizedBox(width: 14),
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          s.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      if (s.code != null && s.code!.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(s.code!, style: const TextStyle(fontSize: 11, color: AppColors.primary, fontWeight: FontWeight.w600)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      const Icon(
                        PhosphorIconsBold.phone,
                        size: 12,
                        color: AppColors.textMuted,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        s.phone ?? 'لا يوجد رقم',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      if (s.taxId != null && s.taxId!.isNotEmpty) ...[
                        const SizedBox(width: 12),
                        const Icon(
                          PhosphorIconsBold.receipt,
                          size: 12,
                          color: AppColors.textMuted,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          s.taxId!,
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            // Balance badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: s.balance <= 0
                    ? AppColors.error.withValues(alpha: 0.1)
                    : AppColors.success.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${s.balance.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolEn}',
                style: TextStyle(
                  color: s.balance <= 0 ? AppColors.error : AppColors.success,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Action buttons
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _ActionIconButton(
                  icon: PhosphorIconsBold.fileText,
                  color: AppColors.primary,
                  tooltip: 'كشف حساب',
                  onTap: widget.onStatement,
                ),
                const SizedBox(width: 4),
                _ActionIconButton(
                  icon: PhosphorIconsBold.pencilSimple,
                  color: AppColors.warning,
                  tooltip: 'تعديل',
                  onTap: widget.onEdit,
                ),
                const SizedBox(width: 4),
                _ActionIconButton(
                  icon: PhosphorIconsBold.trash,
                  color: AppColors.error,
                  tooltip: 'حذف',
                  onTap: widget.onDelete,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Action icon button with hover effect
class _ActionIconButton extends StatefulWidget {
  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback onTap;

  const _ActionIconButton({
    required this.icon,
    required this.color,
    required this.tooltip,
    required this.onTap,
  });

  @override
  State<_ActionIconButton> createState() => _ActionIconButtonState();
}

class _ActionIconButtonState extends State<_ActionIconButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: Tooltip(
        message: widget.tooltip,
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: _isHovered
                  ? widget.color.withValues(alpha: 0.15)
                  : widget.color.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(widget.icon, size: 16, color: widget.color),
          ),
        ),
      ),
    );
  }
}