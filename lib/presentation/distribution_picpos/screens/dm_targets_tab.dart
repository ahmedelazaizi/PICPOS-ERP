// تبويبُ «الأهداف والتحصيلات» — على منطق تبويبَي التوزيع القائمَين
// (‏`distributionControllerProvider`: الأهدافُ الشهريّة والتحصيلات)، والمحقَّقُ
// من **الختم** (مبيعاتُ المندوب المختومةُ في الشهر) لا من مسارٍ حاليّ.

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/i18n/tr.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../data/providers/providers.dart';
import '../../../domain/models/distribution_model.dart';
import '../../picpos_shell/picpos_data_table.dart';
import '../../screens/providers/distribution_controller.dart';
import '../distribution_picpos_providers.dart';
import 'dm_areas_tab.dart' show dmCanManage;

DateTime _monthStart() {
  final now = DateTime.now();
  return DateTime(now.year, now.month, 1);
}

final dmMonthTargetsProvider = StreamProvider.autoDispose<List<SalesRepTarget>>(
    (ref) {
  final m = _monthStart();
  return ref
      .watch(distributionControllerProvider)
      .watchMonthlyTargets(m.year, m.month);
});

final dmMonthCollectionsProvider =
    StreamProvider.autoDispose<List<SalesRepCollection>>((ref) {
  final m = _monthStart();
  return ref
      .watch(distributionControllerProvider)
      .watchAllCollections(m, DateTime(m.year, m.month + 1, 1));
});

final dmMonthSummaryProvider =
    FutureProvider.autoDispose<List<RepSalesSummaryRow>>((ref) {
  final m = _monthStart();
  return ref
      .watch(databaseProvider)
      .repSalesSummary(from: m, to: DateTime(m.year, m.month + 1, 1));
});

class DmTargetsTab extends ConsumerWidget {
  const DmTargetsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final employees = {
      for (final e in ref.watch(dmEmployeesProvider).value ?? const <Employee>[])
        e.id: e.name,
    };
    final customers = {
      for (final c in ref.watch(dmCustomersProvider).value ?? const <Party>[])
        c.id: c.name,
    };
    final targets = ref.watch(dmMonthTargetsProvider).value ?? const [];
    final collections = ref.watch(dmMonthCollectionsProvider).value ?? const [];
    final summary = {
      for (final s in ref.watch(dmMonthSummaryProvider).value ??
          const <RepSalesSummaryRow>[])
        s.repEmployeeId: s,
    };
    final canManage = dmCanManage(ref);
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 12),
      children: [
        PicPosDataTable(
          title: tr('أهداف الشهر'),
          subtitle: tr('المحقق من مبيعات المندوب المختومة هذا الشهر'),
          emptyLabel: tr('لا أهداف لهذا الشهر'),
          headerAction: canManage
              ? FilledButton.icon(
                  key: const Key('dm_target_new'),
                  onPressed: () => _targetDialog(context, ref),
                  icon: const Icon(PhosphorIconsBold.target, size: 16),
                  label: Text(tr('تحديد هدف')),
                )
              : null,
          columns: [
            PicPosTableColumn(tr('المندوب'), flex: 2),
            PicPosTableColumn(tr('الهدف'), align: PicPosCellAlign.end),
            PicPosTableColumn(tr('المحقق'), align: PicPosCellAlign.end),
            PicPosTableColumn(tr('النسبة'), flex: 2),
          ],
          rows: [
            for (final t in targets)
              () {
                final achieved = summary[t.salesRepId]?.netSales ?? 0;
                final f = t.targetAmount <= 0 ? 0.0 : achieved / t.targetAmount;
                return PicPosTableRow(cells: [
                  PicPosTextCell(employees[t.salesRepId] ?? '#${t.salesRepId}',
                      icon: PhosphorIconsBold.userCircle,
                      tint: AppColors.primary),
                  PicPosTextCell(t.targetAmount.toStringAsFixed(2)),
                  PicPosTextCell(achieved.toStringAsFixed(2)),
                  PicPosBarCell('${(f * 100).toStringAsFixed(0)}%', f,
                      f >= 1 ? AppColors.success : AppColors.info),
                ]);
              }(),
          ],
        ),
        const SizedBox(height: 14),
        PicPosDataTable(
          title: tr('تحصيلات المناديب'),
          subtitle: tr('تحصيلات هذا الشهر مختومة بالمندوب والمسار'),
          emptyLabel: tr('لا تحصيلات هذا الشهر'),
          headerAction: canManage
              ? FilledButton.icon(
                  key: const Key('dm_collection_new'),
                  onPressed: () => _collectionDialog(context, ref),
                  icon: const Icon(PhosphorIconsBold.handCoins, size: 16),
                  label: Text(tr('تحصيل جديد')),
                )
              : null,
          columns: [
            PicPosTableColumn(tr('التاريخ')),
            PicPosTableColumn(tr('المندوب'), flex: 2),
            PicPosTableColumn(tr('العميل'), flex: 2),
            PicPosTableColumn(tr('الطريقة')),
            PicPosTableColumn(tr('المبلغ'), align: PicPosCellAlign.end),
          ],
          totals: [
            tr('الإجمالي'),
            '',
            '',
            '',
            collections
                .fold<double>(0, (s, c) => s + c.amount)
                .toStringAsFixed(2),
          ],
          rows: [
            for (final c in collections)
              PicPosTableRow(cells: [
                PicPosTextCell(
                    '${c.createdAt.year}-${c.createdAt.month.toString().padLeft(2, '0')}-${c.createdAt.day.toString().padLeft(2, '0')}'),
                PicPosTextCell(employees[c.salesRepId] ?? '#${c.salesRepId}'),
                PicPosTextCell(customers[c.customerId] ?? '#${c.customerId}'),
                PicPosPillCell(_method(c.paymentMethod), AppColors.info),
                PicPosTextCell(c.amount.toStringAsFixed(2)),
              ]),
          ],
        ),
      ],
    );
  }

  String _method(String m) => switch (m) {
        'check' => tr('شيك'),
        'transfer' => tr('تحويل'),
        _ => tr('نقدي'),
      };

  Future<void> _targetDialog(BuildContext context, WidgetRef ref) async {
    final reps = await ref.read(dmEmployeesProvider.future);
    if (!context.mounted) return;
    int? rep;
    final amount = TextEditingController();
    final visits = TextEditingController(text: '0');
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(tr('هدف الشهر')),
          content: SizedBox(
            width: 400,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              DropdownButtonFormField<int>(
                initialValue: rep,
                isExpanded: true,
                decoration: InputDecoration(labelText: tr('المندوب')),
                items: [
                  for (final e in reps)
                    DropdownMenuItem(value: e.id, child: Text(e.name)),
                ],
                onChanged: (v) => setState(() => rep = v),
              ),
              TextField(
                controller: amount,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: tr('الهدف')),
              ),
              TextField(
                controller: visits,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: tr('زيارات مستهدفة')),
              ),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(tr('إلغاء'))),
            FilledButton(
              onPressed: rep == null
                  ? null
                  : () async {
                      final m = _monthStart();
                      await ref
                          .read(distributionControllerProvider)
                          .setSalesRepTarget(
                            salesRepId: rep!,
                            year: m.year,
                            month: m.month,
                            targetAmount: double.tryParse(amount.text) ?? 0,
                            targetVisits: int.tryParse(visits.text) ?? 0,
                          );
                      if (ctx.mounted) Navigator.pop(ctx, true);
                    },
              child: Text(tr('حفظ')),
            ),
          ],
        ),
      ),
    );
    if (saved == true) ref.invalidate(dmMonthTargetsProvider);
  }

  Future<void> _collectionDialog(BuildContext context, WidgetRef ref) async {
    final reps = await ref.read(dmEmployeesProvider.future);
    final customers = await ref.read(dmCustomersProvider.future);
    final info = await ref.read(dmCustomerRouteInfoProvider.future);
    if (!context.mounted) return;
    int? rep;
    int? customer;
    var method = 'cash';
    final amount = TextEditingController();
    final reference = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(tr('تحصيل جديد')),
          content: SizedBox(
            width: 420,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              DropdownButtonFormField<int>(
                initialValue: customer,
                isExpanded: true,
                decoration: InputDecoration(labelText: tr('العميل')),
                items: [
                  for (final c in customers)
                    DropdownMenuItem(value: c.id, child: Text(c.name)),
                ],
                // مندوبُ العميل مشتقٌّ من مساره — يُقترَح ولا يُفرَض.
                onChanged: (v) => setState(() {
                  customer = v;
                  rep = info[v]?.repEmployeeId ?? rep;
                }),
              ),
              DropdownButtonFormField<int>(
                key: ValueKey('dm_col_rep_$rep'),
                initialValue: rep,
                isExpanded: true,
                decoration: InputDecoration(labelText: tr('المندوب')),
                items: [
                  for (final e in reps)
                    DropdownMenuItem(value: e.id, child: Text(e.name)),
                ],
                onChanged: (v) => setState(() => rep = v),
              ),
              DropdownButtonFormField<String>(
                initialValue: method,
                decoration: InputDecoration(labelText: tr('الطريقة')),
                items: [
                  DropdownMenuItem(value: 'cash', child: Text(tr('نقدي'))),
                  DropdownMenuItem(value: 'check', child: Text(tr('شيك'))),
                  DropdownMenuItem(value: 'transfer', child: Text(tr('تحويل'))),
                ],
                onChanged: (v) => setState(() => method = v ?? 'cash'),
              ),
              TextField(
                controller: amount,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: tr('المبلغ')),
              ),
              TextField(
                controller: reference,
                decoration: InputDecoration(labelText: tr('رقم المرجع')),
              ),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(tr('إلغاء'))),
            FilledButton(
              onPressed: rep == null || customer == null
                  ? null
                  : () async {
                      final value = double.tryParse(amount.text) ?? 0;
                      if (value <= 0) {
                        AppToast.show(ctx, tr('المبلغ غير صالح.'),
                            type: ToastType.error);
                        return;
                      }
                      await ref
                          .read(distributionControllerProvider)
                          .createCollection(SalesRepCollectionsCompanion.insert(
                            salesRepId: rep!,
                            customerId: customer!,
                            amount: value,
                            paymentMethod: Value(method),
                            referenceNumber: Value(reference.text.trim().isEmpty
                                ? null
                                : reference.text.trim()),
                          ));
                      if (ctx.mounted) Navigator.pop(ctx, true);
                    },
              child: Text(tr('حفظ')),
            ),
          ],
        ),
      ),
    );
    if (saved == true) ref.invalidate(dmMonthCollectionsProvider);
  }
}
