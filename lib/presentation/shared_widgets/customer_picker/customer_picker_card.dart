import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:picpos_erp/core/i18n/tr.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/permissions/permission_codes.dart';
import '../../../core/navigation/screen_id.dart';
import '../../../data/providers/customer_picker_providers.dart';
import '../../../data/providers/financial_figures_providers.dart';
import '../../widgets/permission_guard.dart';

/// بطاقةُ العميل المختار: الهاتف (مقنَّعٌ بلا `customers_view`) والعنوان
/// والرصيدُ مع شارة «عليه دين»/تجاوز الحد، وعددُ الحجوزات وآخرُ 3 منها.
/// طرفٌ محذوفٌ ⇒ «عميل محذوف» واللقطةُ [snapshotName] تبقى.
class CustomerPickerCard extends ConsumerWidget {
  const CustomerPickerCard({
    super.key,
    required this.partyId,
    required this.snapshotName,
    required this.onClear,
    this.onOpenProfile,
  });

  final int partyId;
  final String snapshotName;
  final VoidCallback onClear;
  final ValueChanged<int>? onOpenProfile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final party = ref.watch(customerPickerPartyProvider(partyId)).value;
    final deleted =
        party != null && (party.deletedAt != null || !party.isActive);
    final count = ref.watch(customerReservationCountProvider(partyId)).value;
    final recent = (ref.watch(partyReservationsProvider(partyId)).value ??
            const [])
        .take(3)
        .toList();
    final decimals = AppConstants.decimalPlaces;
    // RPT-006: balance / credit-limit hint only with the customers view code.
    final canSeeFigures =
        ref.watch(screenFiguresVisibilityProvider(ScreenId.customers)).value ??
            false;

    return Container(
      key: const ValueKey('customer_picker_card'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: .5),
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(PhosphorIconsBold.userCheck, size: 18, color: scheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  deleted ? snapshotName : (party?.name ?? snapshotName),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w800),
                ),
              ),
              if (deleted)
                _chip(context, tr('عميل محذوف'), scheme.error)
              else if (canSeeFigures && party != null && party.balance > 0)
                _chip(context, tr('عليه دين'), scheme.tertiary),
              IconButton(
                key: const ValueKey('customer_picker_clear'),
                tooltip: tr('تغيير العميل'),
                visualDensity: VisualDensity.compact,
                icon: const Icon(PhosphorIconsBold.x, size: 16),
                onPressed: onClear,
              ),
            ],
          ),
          if (party != null && !deleted) ...[
            const SizedBox(height: 6),
            if ((party.phone ?? '').isNotEmpty)
              _line(
                context,
                PhosphorIconsBold.phone,
                Directionality(
                  textDirection: TextDirection.ltr,
                  child: PermissionMaskedText(
                    permission: PermissionCodes.customersView,
                    text: party.phone!,
                    style: const TextStyle(fontSize: 12.5),
                  ),
                ),
              ),
            if ((party.address ?? '').isNotEmpty)
              _line(context, PhosphorIconsBold.mapPin,
                  Text(party.address!, style: const TextStyle(fontSize: 12.5))),
            _line(
              context,
              PhosphorIconsBold.wallet,
              Text(
                canSeeFigures
                    ? '${tr('الرصيد')}: ${party.balance.toStringAsFixed(decimals)} '
                        '${AppConstants.currencySymbol}'
                        '${party.creditLimit > 0 && party.balance > party.creditLimit ? '  ·  ${tr('تجاوز الحد الائتماني')}' : ''}'
                    : '${tr('الرصيد')}: $kMaskedValuePlaceholder',
                style: const TextStyle(fontSize: 12.5),
              ),
            ),
          ],
          const SizedBox(height: 4),
          Text(
            count == null || count == 0
                ? tr('لا حجوزات سابقة')
                : '${tr('الحجوزات')}: $count',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
          if (recent.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(tr('آخر الزيارات'),
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurfaceVariant)),
            for (final r in recent)
              Text(
                '${r.at.year}/${r.at.month.toString().padLeft(2, '0')}/'
                '${r.at.day.toString().padLeft(2, '0')} · ${r.place}',
                style: const TextStyle(fontSize: 11.5),
              ),
          ],
          if (onOpenProfile != null && !deleted)
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton(
                onPressed: () => onOpenProfile!(partyId),
                child: Text(tr('الملف الكامل')),
              ),
            ),
        ],
      ),
    );
  }

  Widget _line(BuildContext context, IconData icon, Widget child) => Padding(
        padding: const EdgeInsets.only(bottom: 3),
        child: Row(
          children: [
            Icon(icon, size: 14,
                color: Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(width: 8),
            Flexible(child: child),
          ],
        ),
      );

  Widget _chip(BuildContext context, String text, Color color) => Container(
        margin: const EdgeInsetsDirectional.only(end: 6),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(text,
            style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w800, color: color)),
      );
}
