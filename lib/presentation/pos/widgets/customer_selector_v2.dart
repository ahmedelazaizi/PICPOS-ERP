import 'package:ural_erp/core/i18n/tr.dart';
import 'package:flutter/material.dart';
import 'package:ural_erp/core/widgets/app_toast.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:drift/drift.dart' show Value;
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/permissions/permission_codes.dart';
import '../../../data/providers/providers.dart';
import '../../../services/client_write_interceptor.dart';
import '../../widgets/permission_guard.dart';
import 'package:ural_erp/presentation/pos/providers/cart_controller.dart';

/// زرار «إضافة عميل سريع» بجانب حقل البحث — مستخرج كودجت مستقل عن
/// `_CustomerSelectorV2State` عشان يتعمله اختبار widget من غير ما نركّب
/// الشاشة كلها أو نلمس قاعدة بيانات (نفس نمط Task 6a/6b).
///
/// `allowManagerOverride` لأن دي عملية إضافة حقيقية (كتابة عميل جديد)، مش
/// مجرد عرض — المستخدم من غير الكود لسه يقدر يشتغل بعد موافقة مدير.
@visibleForTesting
Widget buildPosCustomerAddIconButton({required VoidCallback onPressed}) {
  return PermissionGuard(
    permission: PermissionCodes.posCustomerAdd,
    allowManagerOverride: true,
    actionName: tr('إضافة عميل سريع'),
    onGranted: onPressed,
    child: IconButton(
      icon: const Icon(PhosphorIconsBold.userPlus, size: 20),
      onPressed: onPressed,
      color: AppColors.primary,
      tooltip: tr('إضافة عميل سريع'),
    ),
  );
}

/// Advanced Customer Selector for POS
///
/// Features:
/// - Fast search by name or phone
/// - Quick add for new customers
/// - Clear selection
/// - Displays balance for existing customers
class CustomerSelectorV2 extends ConsumerStatefulWidget {
  const CustomerSelectorV2({super.key});

  @override
  ConsumerState<CustomerSelectorV2> createState() => _CustomerSelectorV2State();
}

class _CustomerSelectorV2State extends ConsumerState<CustomerSelectorV2> {
  final TextEditingController _searchController = TextEditingController();
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;
  bool _isFocused = false;
  bool _isSelectingCustomer = false; // Flag to prevent hiding during selection

  @override
  void dispose() {
    _hideOverlay();
    _searchController.dispose();
    super.dispose();
  }

  void _showOverlay() {
    _hideOverlay();

    final RenderBox renderBox = context.findRenderObject() as RenderBox;
    final size = renderBox.size;

    _overlayEntry = OverlayEntry(
      builder: (overlayContext) => PositionedDirectional(
        width: size.width,
        child: CompositedTransformFollower(
          link: _layerLink,
          showWhenUnlinked: false,
          offset: Offset(0, size.height + 5),
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(12),
            color: AppColors.surface,
            child: Container(
              constraints: const BoxConstraints(maxHeight: 300),
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.border),
                borderRadius: BorderRadius.circular(12),
              ),
              // Use ValueListenableBuilder to rebuild on text change
              child: ValueListenableBuilder<TextEditingValue>(
                valueListenable: _searchController,
                builder: (ctx, value, _) {
                  return Consumer(
                    builder: (ctx, ref, _) =>
                        _buildSearchResultsInternal(ref, value.text),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );

    Overlay.of(context).insert(_overlayEntry!);
  }

  void _hideOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  Widget _buildSearchResultsInternal(WidgetRef ref, String query) {
    final customersAsync = ref.watch(allCustomersProvider);

    // نفس الفعل مطلوب في مكانين تحت (onGranted وchild.onPressed) — دالة
    // محلية واحدة بدل ما يتكرر نفس الجسم حرفياً مرتين (لاحظه المراجع).
    void addCustomer() {
      _hideOverlay();
      _showQuickAddDialog();
    }

    return customersAsync.when(
      data: (customers) {
        var filtered = customers.where((c) {
          final q = query.toLowerCase();
          return c.name.toLowerCase().contains(q) ||
              (c.phone?.contains(q) ?? false);
        }).toList();

        // Sort: favorites first, then by name
        filtered.sort((a, b) {
          if (a.isFavorite && !b.isFavorite) return -1;
          if (!a.isFavorite && b.isFavorite) return 1;
          return a.name.compareTo(b.name);
        });

        if (filtered.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                 Text(
                  tr('لا يوجد نتائج'),
                  style: const TextStyle(color: AppColors.textMuted),
                ),
                const SizedBox(height: 8),
                PermissionGuard(
                  permission: PermissionCodes.posCustomerAdd,
                  allowManagerOverride: true,
                  actionName: tr('إضافة عميل سريع'),
                  onGranted: addCustomer,
                  child: TextButton.icon(
                    onPressed: addCustomer,
                    icon: const Icon(PhosphorIconsBold.plus),
                    label:  Text(tr('إضافة عميل جديد')),
                  ),
                ),
              ],
            ),
          );
        }

        return ListView.separated(
          shrinkWrap: true,
          padding: EdgeInsets.zero,
          itemCount: filtered.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (ctx, index) {
            final c = filtered[index];
            final hasDebt = c.balance > 0;

            return ListTile(
              leading: Stack(
                clipBehavior: Clip.none,
                children: [
                  CircleAvatar(
                    backgroundColor: c.isFavorite
                        ? AppColors.warning.withValues(alpha: 0.15)
                        : AppColors.primary.withValues(alpha: 0.1),
                    child: Icon(
                      c.isFavorite
                          ? PhosphorIconsBold.star
                          : PhosphorIconsBold.user,
                      size: 20,
                      color: c.isFavorite
                          ? AppColors.warning
                          : AppColors.primary,
                    ),
                  ),
                  // Red badge for debt
                  if (hasDebt)
                    PositionedDirectional(
                      start: -4,
                      top: -4,
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: const BoxDecoration(
                          color: AppColors.error,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          PhosphorIconsBold.currencyCircleDollar,
                          size: 8,
                          color: Colors.white,
                        ),
                      ),
                    ),
                ],
              ),
              title: Row(
                children: [
                  Expanded(
                    child: Text(
                      c.name,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  if (c.isFavorite)
                    const Padding(
                      padding: EdgeInsetsDirectional.only(start: 4),
                      child: Icon(
                        PhosphorIconsBold.star,
                        size: 14,
                        color: AppColors.warning,
                      ),
                    ),
                ],
              ),
              subtitle: Text(
                c.phone ?? tr('بدون هاتف'),
                style: const TextStyle(fontSize: 12),
              ),
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    tr('{p0} د.أ', {'p0': c.balance.toStringAsFixed(AppConstants.decimalPlaces)}),
                    style: TextStyle(
                      color: hasDebt ? AppColors.error : AppColors.success,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                  if (hasDebt)
                     Text(
                      tr('رصيد مستحق'),
                      style: const TextStyle(fontSize: 10, color: AppColors.error),
                    ),
                ],
              ),
              onTap: () {
                _isSelectingCustomer = true; // Prevent overlay from hiding prematurely
                final cart = ref.read(cartControllerProvider.notifier);
                cart.setCustomer(c.id, c.name);
                // Always apply the customer's price level to the cart
                final level = c.priceLevel;
                cart.setPriceLevel(level);
                // Auto-set credit payment AND delivery order type for delivery platform customers
                if (['talabat', 'careem', 'ashyae'].contains(level)) {
                  cart.setPaymentMethod('credit');
                  cart.setOrderType('delivery');
                }
                _searchController.text = c.name;
                _hideOverlay();
                _isSelectingCustomer = false;
                
                // ── POS Hardware Focus Fix: Unfocus the text field so the main scanner can take over ──
                FocusScope.of(context).unfocus();
              },
            );
          },
        );
      },
      loading: () => const Center(
        child: Padding(
          padding: EdgeInsets.all(16.0),
          child: CircularProgressIndicator(),
        ),
      ),
      error: (e, _) => Center(child: Text(tr('خطأ: {e}', {'e': e}))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cartState = ref.watch(cartControllerProvider);
    final isSelected = cartState.selectedCustomerId != null;

    if (isSelected && _searchController.text.isEmpty) {
      _searchController.text = cartState.selectedCustomerName ?? '';
    } else if (!isSelected && _searchController.text.isNotEmpty) {
      _searchController.clear();
    }

    return CompositedTransformTarget(
      link: _layerLink,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border.all(
            color: _isFocused ? AppColors.primary : AppColors.border,
          ),
          borderRadius: BorderRadius.circular(12),
          boxShadow: _isFocused
              ? [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          children: [
            Icon(
              PhosphorIconsBold.user,
              size: 20,
              color: isSelected ? AppColors.primary : AppColors.textMuted,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Focus(
                onFocusChange: (f) {
                  setState(() => _isFocused = f);
                  if (f) {
                    _showOverlay();
                  } else {
                    // Delay to allow onTap to trigger before hiding
                    Future.delayed(const Duration(milliseconds: 350), () {
                      if (mounted && !_isSelectingCustomer) _hideOverlay();
                    });
                  }
                },
                child: TextField(
                  controller: _searchController,
                  decoration:  InputDecoration(
                    hintText: tr('بحث عن عميل أو هاتف...'),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  onChanged: (v) {
                    if (isSelected && v != cartState.selectedCustomerName) {
                      final cart = ref.read(cartControllerProvider.notifier);
                      cart.setCustomer(null, null);
                      cart.setPriceLevel('retail');
                      cart.setPaymentMethod('cash');
                    }
                    if (_isFocused) _showOverlay();
                  },
                ),
              ),
            ),
            if (isSelected)
              IconButton(
                icon: const Icon(PhosphorIconsBold.x, size: 16),
                onPressed: () {
                  final cart = ref.read(cartControllerProvider.notifier);
                  cart.setCustomer(null, null);
                  cart.setPriceLevel('retail');
                  cart.setPaymentMethod('cash');
                  _searchController.clear();
                  FocusScope.of(context).unfocus();
                },
              )
            else
              buildPosCustomerAddIconButton(onPressed: _showQuickAddDialog),
          ],
        ),
      ),
    );
  }

  void _showQuickAddDialog() {
    final nameController = TextEditingController();
    final phoneController = TextEditingController();
    final addressController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title:  Text(tr('إضافة عميل سريع')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                autofocus: true,
                decoration:  InputDecoration(
                  labelText: tr('اسم العميل'),
                  prefixIcon: const Icon(PhosphorIconsBold.user),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: phoneController,
                decoration:  InputDecoration(
                  labelText: tr('رقم الهاتف'),
                  prefixIcon: const Icon(PhosphorIconsBold.phone),
                ),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: addressController,
                decoration:  InputDecoration(
                  labelText: tr('العنوان'),
                  prefixIcon: const Icon(PhosphorIconsBold.mapPin),
                ),
                maxLines: 2,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child:  Text(tr('إلغاء')),
            ),
            ElevatedButton(
              onPressed: () async {
                final name = nameController.text.trim();
                if (name.isEmpty) {
                  AppToast.show(
                    ctx,
                    tr('يرجى إدخال اسم العميل'),
                    type: ToastType.error,
                  );
                  return;
                }

                try {
                  final partiesRepo = ref.read(partiesRepositoryProvider);
                  final phone = phoneController.text.trim();
                  final address = addressController.text.trim();

                  // ── Client mode: route to server ──
                  var id = await ClientWriteInterceptor.createParty(
                    name: name,
                    phone: phone.isEmpty ? null : phone,
                    address: address.isEmpty ? null : address,
                    isCustomer: true,
                    isSupplier: false,
                  );
                  id ??= await partiesRepo.insertParty(
                    PartiesCompanion.insert(
                      name: name,
                      phone: Value(phone.isEmpty ? null : phone),
                      isCustomer: const Value(true),
                      isSupplier: const Value(false),
                      address: Value(address.isEmpty ? null : address),
                    ),
                  );

                  // Refresh customer list
                  ref.invalidate(allCustomersProvider);

                  // Set selected customer in POS
                  ref
                      .read(cartControllerProvider.notifier)
                      .setCustomer(id, name);
                  _searchController.text = name;

                  // Close dialog
                  if (ctx.mounted) Navigator.pop(ctx);
                } catch (e) {
                  debugPrint('Error adding customer: $e');
                  if (ctx.mounted) {
                    AppToast.show(
                      ctx,
                      tr('خطأ في إضافة العميل: {e}', {'e': e}),
                      type: ToastType.error,
                    );
                  }
                }
              },
              child:  Text(tr('إضافة واختيار')),
            ),
          ],
        ),
      ),
    );
  }
}
