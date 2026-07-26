import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/number_utils.dart';
import '../../../data/providers/providers.dart';
import '../../pos/providers/cart_controller.dart';

/// Invoice header: date · invoice no. · customer · customer balance · warehouse.
class PicPosInvoiceHeader extends ConsumerWidget {
  final VoidCallback onPickCustomer;

  const PicPosInvoiceHeader({super.key, required this.onPickCustomer});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart = ref.watch(cartControllerProvider);
    final now = DateTime.now();
    final dateText =
        '${now.year}/${now.month.toString().padLeft(2, '0')}/${now.day.toString().padLeft(2, '0')}';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          _Field(
            icon: PhosphorIconsBold.calendarBlank,
            label: 'التاريخ',
            value: dateText,
          ),
          const _Divider(),
          // The invoice number is assigned by the sales repository at save
          // time, not reserved up front — showing a number here before the
          // sale is committed would promise a number the invoice may not get
          // (a concurrent till on the same branch takes the next one).
          const _Field(
            icon: PhosphorIconsBold.hash,
            label: 'رقم الفاتورة',
            value: 'يُحدَّد عند الحفظ',
            muted: true,
          ),
          const _Divider(),
          Expanded(
            flex: 2,
            child: _CustomerField(
              name: cart.selectedCustomerName,
              onTap: onPickCustomer,
            ),
          ),
          const _Divider(),
          Expanded(
            flex: 2,
            child: _BalanceField(customerId: cart.selectedCustomerId),
          ),
          const _Divider(),
          const Expanded(flex: 2, child: _WarehouseField()),
        ],
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) => Container(
        width: 1,
        height: 34,
        margin: const EdgeInsets.symmetric(horizontal: 8),
        color: AppColors.border,
      );
}

class _Field extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;
  final bool muted;

  const _Field({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
    this.muted = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 12, color: AppColors.textMuted),
            const SizedBox(width: 4),
            Text(label,
                style: const TextStyle(
                    fontSize: 10, color: AppColors.textMuted)),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          value,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: muted ? 11 : 13,
            fontWeight: muted ? FontWeight.normal : FontWeight.bold,
            fontStyle: muted ? FontStyle.italic : FontStyle.normal,
            color: valueColor ?? (muted ? AppColors.textMuted : null),
          ),
        ),
      ],
    );
  }
}

class _CustomerField extends StatelessWidget {
  final String? name;
  final VoidCallback onTap;

  const _CustomerField({required this.name, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: _Field(
          icon: PhosphorIconsBold.user,
          label: 'العميل',
          value: name ?? 'عميل نقدي',
          valueColor: name == null ? AppColors.textMuted : AppColors.primary,
        ),
      ),
    );
  }
}

/// Customer balance. Read off the same `parties.balance` column the parties
/// screen and the account statement use — a POS-local recomputation would be
/// a second source of truth for a figure the cashier quotes out loud.
class _BalanceField extends ConsumerWidget {
  final int? customerId;

  const _BalanceField({required this.customerId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (customerId == null) {
      return const _Field(
        icon: PhosphorIconsBold.wallet,
        label: 'رصيد العميل',
        value: '—',
        muted: true,
      );
    }
    final customers = ref.watch(allCustomersProvider);
    return customers.when(
      loading: () => const _Field(
        icon: PhosphorIconsBold.wallet,
        label: 'رصيد العميل',
        value: '...',
        muted: true,
      ),
      error: (error, stack) => const _Field(
        icon: PhosphorIconsBold.wallet,
        label: 'رصيد العميل',
        value: 'غير متاح',
        muted: true,
      ),
      data: (list) {
        final match = list.where((p) => p.id == customerId).firstOrNull;
        if (match == null) {
          return const _Field(
            icon: PhosphorIconsBold.wallet,
            label: 'رصيد العميل',
            value: '—',
            muted: true,
          );
        }
        final value = match.balance;
        return _Field(
          icon: PhosphorIconsBold.wallet,
          label: 'رصيد العميل',
          value: NumberUtils.formatCurrency(value),
          // Debit (owed to us) red, credit green — same convention as the
          // parties screen so the sign never means two different things.
          valueColor: value > 0
              ? AppColors.error
              : (value < 0 ? AppColors.success : null),
        );
      },
    );
  }
}

class _WarehouseField extends ConsumerWidget {
  const _WarehouseField();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final warehouses = ref.watch(allWarehousesProvider);
    return warehouses.when(
      loading: () => const _Field(
        icon: PhosphorIconsBold.warehouse,
        label: 'المستودع',
        value: '...',
        muted: true,
      ),
      error: (error, stack) => const _Field(
        icon: PhosphorIconsBold.warehouse,
        label: 'المستودع',
        value: 'غير متاح',
        muted: true,
      ),
      data: (list) => _Field(
        icon: PhosphorIconsBold.warehouse,
        label: 'المستودع',
        value: list.isEmpty ? '—' : list.first.name,
      ),
    );
  }
}
