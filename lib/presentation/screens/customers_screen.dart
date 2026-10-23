import 'package:ural_erp/core/i18n/tr.dart';
// ignore_for_file: avoid_dynamic_calls
import 'package:flutter/material.dart';
import '../../core/widgets/app_shortcuts.dart';
import '../../core/widgets/app_toast.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/shimmer_loading.dart';
import '../../data/providers/providers.dart';
import '../../services/client_write_interceptor.dart';
import '../widgets/enhanced_components.dart';
import 'parties/party_data_gate.dart';
import 'party_statement_screen.dart';
import '../../core/constants/app_constants.dart';
import 'widgets/dialogs/party_edit_dialog.dart';
import '../widgets/dialogs/app_confirm_dialog.dart';

/// Customers management screen
class CustomersScreen extends ConsumerStatefulWidget {
  const CustomersScreen({super.key});

  @override
  ConsumerState<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends ConsumerState<CustomersScreen> {
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  static const _pageSize = 50;
  int _displayedCount = 50;

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _showAddCustomerDialog() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => const PartyEditDialog(isSupplier: false, isCustomer: true),
    );
    if (result == true && mounted) {
      AppToast.show(context, tr('تم إضافة العميل بنجاح'), type: ToastType.success);
    }
  }

  void _showEditCustomerDialog(Party customer) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => PartyEditDialog(existing: customer, isSupplier: customer.isSupplier, isCustomer: customer.isCustomer),
    );
    if (result == true && mounted) {
      AppToast.show(context, tr('تم تحديث بيانات العميل بنجاح'), type: ToastType.success);
    }
  }

  void _showDeleteCustomerDialog(Party customer) async {
    final confirmed = await AppConfirmDialog.show(
      context,
      title: tr('تأكيد الحذف'),
      message: tr('هل أنت متأكد من حذف العميل "{p0}"؟', {'p0': customer.name}),
      confirmLabel: tr('حذف'),
      isDangerous: true,
      customContent: customer.balance != 0
          ? Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(PhosphorIconsBold.warning, color: AppColors.warning, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        tr('لديه رصيد: {p0} {p1}', {'p0': customer.balance.toStringAsFixed(AppConstants.decimalPlaces), 'p1': AppConstants.currencySymbolEn}),
                        style: const TextStyle(color: AppColors.warning),
                      ),
                    ),
                  ],
                ),
              ),
            )
          : null,
    );

    if (confirmed == true && mounted) {
      final partiesRepo = ref.read(partiesRepositoryProvider);
      final deleted = await ClientWriteInterceptor.deleteParty(customer.id);
      if (!deleted) {
        await partiesRepo.deleteParty(customer.id);
      }

      // Log activity
      final user = ref.read(authProvider).user;
      final activityLogRepo = ref.read(activityLogRepositoryProvider);
      await activityLogRepo.logActivity(
        userId: user?.id,
        userName: user?.displayName ?? tr('مجهول'),
        action: 'delete_customer',
        entityType: 'party',
        entityId: customer.id,
        description: tr('حذف عميل: {p0}', {'p0': customer.name}),
      );

      if (mounted) {
        AppToast.show(context, tr('تم إلغاء تفعيل العميل'), type: ToastType.warning);
      }
    }
  }

  Future<void> _exportTemplate() async {
    if (!await ensurePartyDataAccess(ref, context, PartyDataAction.export,
        isSupplier: false)) {
      return;
    }
    final service = ref.read(excelServiceProvider);
    final path = await service.exportPartiesTemplate(false);
    if (path != null && mounted) {
      AppToast.show(context, tr('تم تصدير النموذج بنجاح: {path}', {'path': path}), type: ToastType.success);
      try {
        final user = ref.read(authProvider).user;
        final logger = ref.read(activityLoggerProvider);
        await logger.logExport(user?.id ?? 0, user?.displayName ?? tr('مجهول'), 'customer', 'Excel');
      } catch (_) {}
    }
  }

  Future<void> _importData() async {
    if (!await ensurePartyDataAccess(ref, context, PartyDataAction.import,
        isSupplier: false)) {
      return;
    }
    final service = ref.read(excelServiceProvider);
    final result = await service.importParties(false);
    if (mounted) {
      AppToast.show(context, result.message, type: result.success == true ? ToastType.success : ToastType.error);
      if (result.success) {
        ref.invalidate(allCustomersProvider);
        try {
          final user = ref.read(authProvider).user;
          final logger = ref.read(activityLoggerProvider);
          await logger.logImport(user?.id ?? 0, user?.displayName ?? tr('مجهول'), 'customer', 0);
        } catch (_) {}
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final customers = ref.watch(allCustomersProvider);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: AppShortcuts(
        searchFocusNode: _searchFocusNode,
        searchController: _searchController,
        onNew: _showAddCustomerDialog,
        child: Scaffold(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          body: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SectionHeader(
                  title: tr('إدارة العملاء'),
                  icon: PhosphorIconsBold.users,
                  fontSize: 24,
                  action: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _exportTemplate,
                        icon: const Icon(PhosphorIconsBold.fileArrowUp, size: 18),
                        label:  Text(tr('قالب الإدخال الذكي')),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        onPressed: _importData,
                        icon: const Icon(PhosphorIconsBold.fileArrowDown, size: 18),
                        label:  Text(tr('استيراد بيانات')),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton.icon(
                        onPressed: _showAddCustomerDialog,
                        icon: const Icon(PhosphorIconsBold.plus),
                        label:  Text(tr('إضافة عميل')),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _searchController,
                  focusNode: _searchFocusNode,
                  decoration: InputDecoration(
                    hintText: tr('البحث عن عميل...'),
                    prefixIcon: const Icon(PhosphorIconsBold.magnifyingGlass),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    filled: true,
                    fillColor: Theme.of(context).cardColor,
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: customers.when(
                      data: (list) {
                        final filtered = _searchController.text.isEmpty
                            ? list
                            : list
                                .where((c) =>
                                    c.name.contains(_searchController.text) ||
                                    (c.phone?.contains(_searchController.text) ?? false))
                                .toList();

                        if (filtered.isEmpty) {
                          return EmptyStateWidget(
                            icon: PhosphorIconsBold.users,
                            message: tr('لا يوجد عملاء'),
                            actionLabel: tr('إضافة عميل'),
                            onAction: _showAddCustomerDialog,
                          );
                        }

                        return ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: filtered.length > _displayedCount ? _displayedCount + 1 : filtered.length,
                          separatorBuilder: (_, index) => const Divider(),
                          itemBuilder: (context, index) {
                            if (index >= _displayedCount) {
                              return Center(
                                child: TextButton.icon(
                                  onPressed: () => setState(() => _displayedCount += _pageSize),
                                  icon: const Icon(PhosphorIconsBold.arrowDown),
                                  label: Text(tr('تحميل المزيد ({p0} متبقي)', {'p0': filtered.length - _displayedCount})),
                                ),
                              );
                            }
                            final c = filtered[index];
                            return ListTile(
                              leading: Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  CircleAvatar(
                                    backgroundColor: c.isFavorite
                                        ? AppColors.warning.withValues(alpha: 0.15)
                                        : AppColors.primary.withValues(alpha: 0.1),
                                    child: Icon(
                                      c.isFavorite ? PhosphorIconsBold.star : PhosphorIconsBold.user,
                                      color: c.isFavorite ? AppColors.warning : AppColors.primary,
                                    ),
                                  ),
                                  if (c.balance > 0)
                                    PositionedDirectional(
                                      start: -4,
                                      top: -4,
                                      child: Container(
                                        width: 14,
                                        height: 14,
                                        decoration: const BoxDecoration(color: AppColors.error, shape: BoxShape.circle),
                                        child: const Icon(PhosphorIconsBold.currencyCircleDollar,
                                            size: 10, color: Colors.white),
                                      ),
                                    ),
                                ],
                              ),
                              title: Row(
                                children: [
                                  Expanded(child: Text(c.name, style: const TextStyle(fontWeight: FontWeight.w500))),
                                  if (c.code != null && c.code!.isNotEmpty)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: AppColors.primary.withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(c.code!, style: const TextStyle(fontSize: 11, color: AppColors.primary, fontWeight: FontWeight.w600)),
                                    ),
                                ],
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(c.phone ?? tr('لا يوجد رقم')),
                                  if (c.address != null && c.address!.isNotEmpty)
                                    Text(c.address!, style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
                                ],
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        '${c.balance.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolEn}',
                                        style: TextStyle(
                                          color: c.balance >= 0 ? AppColors.success : AppColors.error,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      Text(
                                        tr('حد الائتمان: {p0}', {'p0': c.creditLimit.toStringAsFixed(0)}),
                                        style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(width: 8),
                                  PopupMenuButton<String>(
                                    onSelected: (val) {
                                      if (val == 'edit') {
                                        _showEditCustomerDialog(c);
                                      } else if (val == 'delete') {
                                        _showDeleteCustomerDialog(c);
                                      } else if (val == 'statement') {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(builder: (_) => PartyStatementScreen(partyId: c.id)),
                                        );
                                      }
                                    },
                                    itemBuilder: (_) => [
                                       PopupMenuItem(
                                        value: 'statement',
                                        child: Row(children: [
                                          const Icon(PhosphorIconsBold.fileText, size: 18),
                                          const SizedBox(width: 8),
                                          Text(tr('كشف حساب')),
                                        ]),
                                      ),
                                       PopupMenuItem(
                                        value: 'edit',
                                        child: Row(children: [
                                          const Icon(PhosphorIconsBold.pencilSimple, size: 18),
                                          const SizedBox(width: 8),
                                          Text(tr('تعديل')),
                                        ]),
                                      ),
                                       PopupMenuItem(
                                        value: 'delete',
                                        child: Row(children: [
                                          const Icon(PhosphorIconsBold.trash, size: 18, color: AppColors.error),
                                          const SizedBox(width: 8),
                                          Text(tr('حذف'), style: const TextStyle(color: AppColors.error)),
                                        ]),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            );
                          },
                        );
                      },
                      loading: () => const ShimmerLoading(),
                      error: (e, s) => Center(child: Text(tr('خطأ في تحميل البيانات: {e}', {'e': e}))),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}