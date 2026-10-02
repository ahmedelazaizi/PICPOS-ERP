// تبويبُ «المناديب» — المندوبُ ومخزنُ سيارته وخزنةُ عهدته ودفاترُ سنداته
// ومساراتُه وعملاؤه، وإجراءاتٌ سريعة: تحميل · تفريغ · تسليم عهدة.
//
// التحميلُ والتفريغُ تحويلُ مخزونٍ ([repLoadVan] / [repUnloadVan] فوق
// `transferStock`)، والتسليمُ تحويلٌ بين الخزائن بقيده ([handoverCustodyCash]).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/i18n/tr.dart';
import '../../../core/permissions/permission_codes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../data/providers/providers.dart';
import '../../../domain/models/distribution_model.dart';
import '../../picpos_shell/picpos_empty_state.dart';
import '../../picpos_shell/picpos_surface.dart';
import '../distribution_picpos_providers.dart';
import 'dm_areas_tab.dart' show dmCanManage;

class DmRepsTab extends ConsumerWidget {
  const DmRepsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final employees = ref.watch(dmEmployeesProvider).value ?? const [];
    final routes = ref.watch(dmRoutesProvider).value ?? const [];
    final resources = {
      for (final r in ref.watch(dmRepResourcesProvider).value ??
          const <RepResources>[])
        r.employeeId: r,
    };
    final repIds = {
      ...resources.keys,
      for (final r in routes) ?r.repEmployeeId,
    };
    final reps = employees.where((e) => repIds.contains(e.id)).toList();
    final canManage = dmCanManage(ref);
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 12),
      children: [
        Row(children: [
          Expanded(
            child: Text(tr('المناديب ومواردهم'),
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: context.picposText)),
          ),
          if (canManage)
            FilledButton.icon(
              key: const Key('dm_rep_new'),
              onPressed: () => showDmRepResourcesDialog(context, ref),
              icon: const Icon(PhosphorIconsBold.plus, size: 16),
              label: Text(tr('تعيين موارد مندوب')),
            ),
        ]),
        const SizedBox(height: 10),
        if (reps.isEmpty)
          PicPosEmptyState(
            icon: PhosphorIconsBold.userCircle,
            title: tr('لا مناديب بعد'),
            hint: tr('عيّن مندوباً لمسار أو حدّد له مخزن سيارة وخزنة عهدة'),
          )
        else
          Wrap(spacing: 12, runSpacing: 12, children: [
            for (final e in reps)
              _RepCard(
                employee: e,
                resources: resources[e.id],
                routes: routes.where((r) => r.repEmployeeId == e.id).toList(),
                canManage: canManage,
              ),
          ]),
      ],
    );
  }
}

class _RepCard extends ConsumerWidget {
  const _RepCard({
    required this.employee,
    required this.resources,
    required this.routes,
    required this.canManage,
  });
  final Employee employee;
  final RepResources? resources;
  final List<DistributionRoute> routes;
  final bool canManage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final warehouses = {
      for (final w in ref.watch(dmWarehousesProvider).value ?? const <Warehouse>[])
        w.id: w,
    };
    final safes = {
      for (final s in ref.watch(dmSafesProvider).value ?? const <Safe>[]) s.id: s,
    };
    final books = (ref.watch(dmVoucherBooksProvider).value ?? const [])
        .where((b) => b.holderEmployeeId == employee.id)
        .toList();
    final van = warehouses[resources?.vanWarehouseId];
    final custody = safes[resources?.custodySafeId];
    final canTransfer =
        ref.watch(hasPermissionProvider(PermissionCodes.inventoryTransfer)).value ??
            false;
    final canHandover =
        ref.watch(hasPermissionProvider(PermissionCodes.treasuryTransfer)).value ??
            false;
    final customers = routes.fold<int>(0, (s, r) => s + r.customerCount);

    Widget line(IconData icon, String label, String value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [
            Icon(icon, size: 15, color: context.picposMuted),
            const SizedBox(width: 6),
            Text('$label: ',
                style: TextStyle(fontSize: 12, color: context.picposMuted)),
            Expanded(
              child: Text(value,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: context.picposText)),
            ),
          ]),
        );

    return Container(
      key: Key('dm_rep_${employee.id}'),
      width: 400,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.picposCard,
        border: Border.all(color: context.picposHairline),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            CircleAvatar(
              backgroundColor: AppColors.primary.withValues(alpha: .14),
              child: const Icon(PhosphorIconsBold.userCircle,
                  color: AppColors.primary),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(employee.name,
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: context.picposText)),
            ),
            if (canManage)
              IconButton(
                tooltip: tr('تعديل الموارد'),
                onPressed: () => showDmRepResourcesDialog(context, ref,
                    employeeId: employee.id),
                icon: const Icon(PhosphorIconsBold.gear, size: 18),
              ),
          ]),
          const SizedBox(height: 8),
          line(PhosphorIconsBold.truck, tr('مخزن السيارة'),
              van?.name ?? tr('غير محدد')),
          line(
              PhosphorIconsBold.vault,
              tr('خزنة العهدة'),
              custody == null
                  ? tr('غير محدد')
                  : '${custody.name} (${custody.balance.toStringAsFixed(2)})'),
          line(
              PhosphorIconsBold.books,
              tr('دفاتر السندات'),
              books.isEmpty
                  ? '—'
                  : books.map((b) => b.displayName).join('، ')),
          line(
              PhosphorIconsBold.path,
              tr('المسارات'),
              routes.isEmpty
                  ? '—'
                  : '${routes.map((r) => r.name).join('، ')} · ${tr('{p0} عميل', {'p0': customers})}'),
          const SizedBox(height: 10),
          Wrap(spacing: 6, runSpacing: 6, children: [
            OutlinedButton.icon(
              key: Key('dm_rep_load_${employee.id}'),
              onPressed: van == null || !canTransfer
                  ? null
                  : () => showDmVanTransferDialog(context, ref,
                      repEmployeeId: employee.id, load: true),
              icon: const Icon(PhosphorIconsBold.arrowSquareIn, size: 16),
              label: Text(tr('تحميل')),
            ),
            OutlinedButton.icon(
              key: Key('dm_rep_unload_${employee.id}'),
              onPressed: van == null || !canTransfer
                  ? null
                  : () => showDmVanTransferDialog(context, ref,
                      repEmployeeId: employee.id, load: false),
              icon: const Icon(PhosphorIconsBold.arrowSquareOut, size: 16),
              label: Text(tr('تفريغ')),
            ),
            FilledButton.tonalIcon(
              key: Key('dm_rep_handover_${employee.id}'),
              onPressed: custody == null || !canHandover
                  ? null
                  : () => showDmHandoverDialog(context, ref,
                      repEmployeeId: employee.id),
              icon: const Icon(PhosphorIconsBold.handCoins, size: 16),
              label: Text(tr('تسليم العهدة')),
            ),
          ]),
        ],
      ),
    );
  }
}

Future<void> showDmRepResourcesDialog(BuildContext context, WidgetRef ref,
    {int? employeeId}) async {
  final employees = await ref.read(dmEmployeesProvider.future);
  final warehouses = await ref.read(dmWarehousesProvider.future);
  final safes = await ref.read(dmSafesProvider.future);
  final current = employeeId == null
      ? null
      : await ref.read(databaseProvider).getRepResources(employeeId);
  if (!context.mounted) return;
  int? rep = employeeId;
  int? van = current?.vanWarehouseId;
  int? custody = current?.custodySafeId;
  final saved = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text(tr('موارد المندوب')),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<int>(
                initialValue: rep,
                isExpanded: true,
                decoration: InputDecoration(labelText: tr('المندوب')),
                items: [
                  for (final e in employees)
                    DropdownMenuItem(value: e.id, child: Text(e.name)),
                ],
                onChanged: employeeId != null
                    ? null
                    : (v) => setState(() => rep = v),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<int?>(
                initialValue: warehouses.any((w) => w.id == van) ? van : null,
                isExpanded: true,
                decoration: InputDecoration(labelText: tr('مخزن السيارة')),
                items: [
                  DropdownMenuItem(value: null, child: Text(tr('غير محدد'))),
                  for (final w in warehouses)
                    DropdownMenuItem(value: w.id, child: Text(w.name)),
                ],
                onChanged: (v) => setState(() => van = v),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<int?>(
                initialValue: safes.any((s) => s.id == custody) ? custody : null,
                isExpanded: true,
                decoration: InputDecoration(labelText: tr('خزنة العهدة')),
                items: [
                  DropdownMenuItem(value: null, child: Text(tr('غير محدد'))),
                  for (final s in safes)
                    DropdownMenuItem(value: s.id, child: Text(s.name)),
                ],
                onChanged: (v) => setState(() => custody = v),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr('إلغاء'))),
          FilledButton(
            onPressed: rep == null
                ? null
                : () async {
                    try {
                      await ref.read(databaseProvider).saveRepResources(
                          employeeId: rep!,
                          vanWarehouseId: van,
                          custodySafeId: custody);
                      if (ctx.mounted) Navigator.pop(ctx, true);
                    } catch (e) {
                      if (ctx.mounted) {
                        AppToast.show(ctx, '$e', type: ToastType.error);
                      }
                    }
                  },
            child: Text(tr('حفظ')),
          ),
        ],
      ),
    ),
  );
  if (saved == true) refreshDistribution(ref);
}

/// تحميلٌ ([load]) من مخزنٍ رئيسٍ إلى السيارة، أو تفريغٌ منها إليه.
Future<void> showDmVanTransferDialog(BuildContext context, WidgetRef ref,
    {required int repEmployeeId, required bool load}) async {
  final warehouses = await ref.read(dmWarehousesProvider.future);
  final products = await ref.read(dmProductsProvider.future);
  final res = await ref.read(databaseProvider).getRepResources(repEmployeeId);
  if (!context.mounted) return;
  final others = warehouses.where((w) => w.id != res?.vanWarehouseId).toList();
  int? main = others.firstOrNull?.id;
  final lines = <({int productId, TextEditingController qty})>[];
  int? pickProduct;
  final userId = ref.read(authProvider).effectiveUser?.id;
  final done = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text(load ? tr('تحميل سيارة المندوب') : tr('تفريغ سيارة المندوب')),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<int>(
                initialValue: main,
                isExpanded: true,
                decoration: InputDecoration(
                    labelText:
                        load ? tr('من المخزن') : tr('إلى المخزن')),
                items: [
                  for (final w in others)
                    DropdownMenuItem(value: w.id, child: Text(w.name)),
                ],
                onChanged: (v) => setState(() => main = v),
              ),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    initialValue: pickProduct,
                    isExpanded: true,
                    decoration: InputDecoration(labelText: tr('الصنف')),
                    items: [
                      for (final p in products)
                        DropdownMenuItem(value: p.id, child: Text(p.name)),
                    ],
                    onChanged: (v) => setState(() => pickProduct = v),
                  ),
                ),
                IconButton(
                  tooltip: tr('إضافة'),
                  onPressed: pickProduct == null ||
                          lines.any((l) => l.productId == pickProduct)
                      ? null
                      : () => setState(() => lines.add((
                            productId: pickProduct!,
                            qty: TextEditingController(text: '1'),
                          ))),
                  icon: const Icon(PhosphorIconsBold.plusCircle),
                ),
              ]),
              for (final l in lines)
                Row(children: [
                  Expanded(
                    child: Text(products
                            .where((p) => p.id == l.productId)
                            .firstOrNull
                            ?.name ??
                        ''),
                  ),
                  SizedBox(
                    width: 90,
                    child: TextField(
                      controller: l.qty,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(labelText: tr('الكمية')),
                    ),
                  ),
                  IconButton(
                    onPressed: () => setState(() => lines.remove(l)),
                    icon: const Icon(PhosphorIconsBold.x, size: 16),
                  ),
                ]),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr('إلغاء'))),
          FilledButton(
            onPressed: main == null || lines.isEmpty
                ? null
                : () async {
                    final items = [
                      for (final l in lines)
                        if ((double.tryParse(l.qty.text) ?? 0) > 0)
                          {
                            'productId': l.productId,
                            'quantity': double.parse(l.qty.text),
                          },
                    ];
                    try {
                      final db = ref.read(databaseProvider);
                      if (load) {
                        await db.repLoadVan(
                            repEmployeeId: repEmployeeId,
                            fromWarehouseId: main!,
                            items: items,
                            userId: userId);
                      } else {
                        await db.repUnloadVan(
                            repEmployeeId: repEmployeeId,
                            toWarehouseId: main!,
                            items: items,
                            userId: userId);
                      }
                      if (ctx.mounted) Navigator.pop(ctx, true);
                    } catch (e) {
                      if (ctx.mounted) {
                        AppToast.show(ctx, '$e', type: ToastType.error);
                      }
                    }
                  },
            child: Text(tr('تنفيذ')),
          ),
        ],
      ),
    ),
  );
  if (done == true && context.mounted) {
    AppToast.show(context, tr('تم تنفيذ التحويل'), type: ToastType.success);
  }
}

/// تسليمُ العهدة — تحويلٌ من خزنة العهدة إلى خزينةٍ رئيسة.
Future<void> showDmHandoverDialog(BuildContext context, WidgetRef ref,
    {required int repEmployeeId}) async {
  final safes = await ref.read(dmSafesProvider.future);
  final res = await ref.read(databaseProvider).getRepResources(repEmployeeId);
  if (!context.mounted) return;
  final custody = safes.where((s) => s.id == res?.custodySafeId).firstOrNull;
  final targets = safes.where((s) => s.id != custody?.id).toList();
  int? to = targets.where((s) => s.isDefault).firstOrNull?.id ??
      targets.firstOrNull?.id;
  final amount = TextEditingController(
      text: (custody?.balance ?? 0).toStringAsFixed(2));
  final userId = ref.read(authProvider).effectiveUser?.id;
  final done = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text(tr('تسليم العهدة إلى الخزينة')),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '${tr('خزنة العهدة')}: ${custody?.name ?? '—'} '
                '(${(custody?.balance ?? 0).toStringAsFixed(2)})',
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<int>(
                initialValue: to,
                isExpanded: true,
                decoration: InputDecoration(labelText: tr('إلى الخزينة')),
                items: [
                  for (final s in targets)
                    DropdownMenuItem(value: s.id, child: Text(s.name)),
                ],
                onChanged: (v) => setState(() => to = v),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: amount,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: tr('المبلغ')),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr('إلغاء'))),
          FilledButton(
            onPressed: to == null
                ? null
                : () async {
                    try {
                      await ref.read(databaseProvider).handoverCustodyCash(
                            repEmployeeId: repEmployeeId,
                            toSafeId: to!,
                            amount: double.tryParse(amount.text) ?? 0,
                            userId: userId,
                          );
                      if (ctx.mounted) Navigator.pop(ctx, true);
                    } catch (e) {
                      if (ctx.mounted) {
                        AppToast.show(ctx, '$e', type: ToastType.error);
                      }
                    }
                  },
            child: Text(tr('تسليم')),
          ),
        ],
      ),
    ),
  );
  if (done == true) {
    refreshDistribution(ref);
    if (context.mounted) {
      AppToast.show(context, tr('تم تسليم العهدة'), type: ToastType.success);
    }
  }
}
