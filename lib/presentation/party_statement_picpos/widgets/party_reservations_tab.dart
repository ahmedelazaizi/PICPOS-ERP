import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:picpos_erp/core/i18n/tr.dart';

import '../../../core/constants/app_constants.dart';
import '../../../data/providers/customer_picker_providers.dart';
import '../../../domain/models/party_reservation_entry.dart';

/// تسميةُ حالةِ حجزٍ (خدمات وطاولات معاً).
String reservationStatusLabel(String status) => switch (status) {
      'pending' => tr('قيد الانتظار'),
      'confirmed' => tr('مؤكد'),
      'seated' => tr('تم الحضور'),
      'in_service' => tr('قيد الخدمة'),
      'completed' => tr('مكتمل'),
      'cancelled' => tr('ملغي'),
      'no_show' => tr('لم يحضر'),
      _ => status,
    };

/// تبويبُ «الحجوزات» في ملف العميل: حجوزاتُ الخدمات وحجوزاتُ الطاولات معاً
/// (الأحدثُ أولاً) بالحالة والعربون ورقم الفاتورة.
class PartyReservationsTab extends ConsumerWidget {
  const PartyReservationsTab({super.key, required this.partyId});

  final int partyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final async = ref.watch(partyReservationsProvider(partyId));
    return async.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Padding(
        padding: const EdgeInsets.all(16),
        child: Text(tr('خطأ: {e}', {'e': e})),
      ),
      data: (rows) {
        if (rows.isEmpty) {
          return Padding(
            key: const ValueKey('party_reservations_empty'),
            padding: const EdgeInsets.all(24),
            child: Center(
              child: Text(tr('لا حجوزات سابقة'),
                  style: TextStyle(color: scheme.onSurfaceVariant)),
            ),
          );
        }
        return Column(
          key: const ValueKey('party_reservations_list'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [for (final r in rows) _Row(entry: r)],
        );
      },
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.entry});

  final PartyReservationEntry entry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final at = entry.at;
    final when = '${at.year}/${at.month.toString().padLeft(2, '0')}/'
        '${at.day.toString().padLeft(2, '0')} '
        '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
    final detail = [
      entry.isTable ? tr('حجز طاولة') : tr('حجز خدمة'),
      if (entry.place.isNotEmpty) entry.place,
      if (entry.partySize != null)
        tr('{p0} أشخاص', {'p0': entry.partySize}),
      if (entry.amount > 0)
        '${tr('العربون')}: ${entry.amount.toStringAsFixed(AppConstants.decimalPlaces)}',
      if (entry.invoiceNumber != null) '#${entry.invoiceNumber}',
    ].join(' · ');
    return Container(
      key: ValueKey('party_reservation_${entry.kind}_${entry.id}'),
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(
            entry.isTable
                ? PhosphorIconsBold.forkKnife
                : PhosphorIconsBold.calendarCheck,
            size: 18,
            color: scheme.primary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(when,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w800)),
                Text(detail,
                    style: TextStyle(
                        fontSize: 12, color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
          Text(reservationStatusLabel(entry.status),
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}
