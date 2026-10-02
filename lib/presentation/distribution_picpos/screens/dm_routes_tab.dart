// تبويبُ «المسارات» — المسارُ بمندوبه الواحد ومنطقته وأيّام زيارته، وعملاؤه
// مرتَّبين يدويّاً (سحبٌ أو أعلى/أسفل)، وإضافةُ عميلٍ ونقلُه وإزالتُه.
//
// ⚠️ إضافةُ عميلٍ على مسارٍ آخرَ **تنقله** — قاعدةُ «مسارٌ واحدٌ للعميل»
//    في المحرّك ([assignCustomerToRoute]) لا هنا.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/i18n/tr.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../data/providers/providers.dart';
import '../../../domain/models/distribution_model.dart';
import '../../picpos_shell/picpos_empty_state.dart';
import '../../picpos_shell/picpos_surface.dart';
import '../distribution_picpos_providers.dart';
import 'dm_areas_tab.dart' show dmCanManage;

class DmRoutesTab extends ConsumerStatefulWidget {
  const DmRoutesTab({super.key});

  @override
  ConsumerState<DmRoutesTab> createState() => _DmRoutesTabState();
}

class _DmRoutesTabState extends ConsumerState<DmRoutesTab> {
  int? _selected;

  @override
  Widget build(BuildContext context) {
    final routes = ref.watch(dmRoutesProvider).value ?? const [];
    final canManage = dmCanManage(ref);
    final selected = routes.where((r) => r.id == _selected).firstOrNull ??
        routes.firstOrNull;
    final list = _routeList(context, routes, selected, canManage);
    final detail = selected == null
        ? PicPosEmptyState(
            icon: PhosphorIconsBold.path,
            title: tr('لا مسارات بعد'),
            hint: tr('أنشئ مساراً وحدّد مندوبه ومنطقته'),
          )
        : _RouteDetail(route: selected, canManage: canManage);
    return LayoutBuilder(builder: (context, c) {
      if (c.maxWidth < 820) {
        return Column(children: [
          SizedBox(height: 220, child: list),
          const SizedBox(height: 8),
          Expanded(child: detail),
        ]);
      }
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(width: 340, child: list),
            const SizedBox(width: 12),
            Expanded(child: detail),
          ],
        ),
      );
    });
  }

  Widget _routeList(BuildContext context, List<DistributionRoute> routes,
      DistributionRoute? selected, bool canManage) {
    return _DmPanel(
      title: tr('المسارات'),
      action: canManage
          ? IconButton(
              key: const Key('dm_route_new'),
              tooltip: tr('مسار جديد'),
              onPressed: () => showDmRouteDialog(context, ref),
              icon: const Icon(PhosphorIconsBold.plus, size: 18),
            )
          : null,
      child: ListView(
        children: [
          for (final r in routes)
            ListTile(
              key: Key('dm_route_${r.id}'),
              selected: r.id == selected?.id,
              selectedTileColor:
                  AppColors.primary.withValues(alpha: context.picposIsDark ? .22 : .08),
              leading: const Icon(PhosphorIconsBold.path, size: 20),
              title: Text(r.name,
                  style: TextStyle(
                      fontWeight: FontWeight.w700, color: context.picposText)),
              subtitle: Text(
                '${r.repName ?? tr('بلا مندوب')} · ${r.areaName ?? r.legacyArea ?? tr('بلا منطقة')}',
                style: TextStyle(color: context.picposMuted, fontSize: 12),
              ),
              trailing: _CountBadge(count: r.customerCount),
              onTap: () => setState(() => _selected = r.id),
            ),
        ],
      ),
    );
  }
}

class _RouteDetail extends ConsumerWidget {
  const _RouteDetail({required this.route, required this.canManage});
  final DistributionRoute route;
  final bool canManage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final customers =
        ref.watch(dmRouteCustomersProvider(route.id)).value ?? const [];
    final days = dmWeekdayLabels();
    return _DmPanel(
      title: route.name,
      subtitle: [
        '${tr('المندوب')}: ${route.repName ?? '—'}',
        '${tr('المنطقة')}: ${route.areaName ?? route.legacyArea ?? '—'}',
        '${tr('أيام الزيارة')}: ${route.visitDays.isEmpty ? '—' : route.visitDays.map((d) => days[d]).join('، ')}',
      ].join('   ·   '),
      action: canManage
          ? Wrap(spacing: 6, children: [
              OutlinedButton.icon(
                key: const Key('dm_route_edit'),
                onPressed: () => showDmRouteDialog(context, ref, route: route),
                icon: const Icon(PhosphorIconsBold.pencilSimple, size: 16),
                label: Text(tr('تعديل')),
              ),
              FilledButton.icon(
                key: const Key('dm_route_add_customer'),
                onPressed: () => showDmAssignCustomerDialog(context, ref,
                    routeId: route.id),
                icon: const Icon(PhosphorIconsBold.userPlus, size: 16),
                label: Text(tr('إضافة عميل')),
              ),
            ])
          : null,
      child: customers.isEmpty
          ? PicPosEmptyState(
              icon: PhosphorIconsBold.users,
              title: tr('لا عملاء على هذا المسار'),
              hint: tr('أضف العملاء ورتّبهم بترتيب الزيارة'),
            )
          : ReorderableListView.builder(
              buildDefaultDragHandles: canManage,
              itemCount: customers.length,
              onReorder: (from, to) async {
                final ids = [for (final c in customers) c.customerId];
                final moved = ids.removeAt(from);
                ids.insert(to > from ? to - 1 : to, moved);
                await ref
                    .read(databaseProvider)
                    .reorderRouteCustomers(route.id, ids);
                ref.invalidate(dmRouteCustomersProvider(route.id));
              },
              itemBuilder: (context, i) {
                final c = customers[i];
                Future<void> move(int delta) async {
                  final ids = [for (final x in customers) x.customerId];
                  final j = i + delta;
                  if (j < 0 || j >= ids.length) return;
                  ids[i] = ids[j];
                  ids[j] = c.customerId;
                  await ref
                      .read(databaseProvider)
                      .reorderRouteCustomers(route.id, ids);
                  ref.invalidate(dmRouteCustomersProvider(route.id));
                }

                return ListTile(
                  key: ValueKey('dm_rc_${c.customerId}'),
                  leading: CircleAvatar(
                    radius: 14,
                    backgroundColor: AppColors.primary.withValues(alpha: .14),
                    child: Text('${i + 1}',
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: AppColors.primary)),
                  ),
                  title: Text(c.customerName,
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: context.picposText)),
                  subtitle: Text(
                    '${c.phone ?? ''}  ${tr('الرصيد')}: ${c.balance.toStringAsFixed(2)}',
                    style: TextStyle(color: context.picposMuted, fontSize: 12),
                  ),
                  trailing: canManage
                      ? Row(mainAxisSize: MainAxisSize.min, children: [
                          IconButton(
                            tooltip: tr('أعلى'),
                            onPressed: i == 0 ? null : () => move(-1),
                            icon: const Icon(PhosphorIconsBold.arrowUp,
                                size: 16),
                          ),
                          IconButton(
                            tooltip: tr('أسفل'),
                            onPressed: i == customers.length - 1
                                ? null
                                : () => move(1),
                            icon: const Icon(PhosphorIconsBold.arrowDown,
                                size: 16),
                          ),
                          IconButton(
                            tooltip: tr('إزالة من المسار'),
                            onPressed: () async {
                              await ref
                                  .read(databaseProvider)
                                  .removeCustomerFromRoute(c.customerId);
                              refreshDistribution(ref);
                            },
                            icon: const Icon(PhosphorIconsBold.x,
                                size: 16, color: AppColors.error),
                          ),
                          const SizedBox(width: 24),
                        ])
                      : null,
                );
              },
            ),
    );
  }
}

/// لوحةٌ بعنوانٍ وإجراء — بطاقةُ PicPos الموحّدة.
class _DmPanel extends StatelessWidget {
  const _DmPanel(
      {required this.title, required this.child, this.subtitle, this.action});
  final String title;
  final String? subtitle;
  final Widget? action;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.picposCard,
        border: Border.all(color: context.picposHairline),
        borderRadius: BorderRadius.circular(14),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
            child: Row(children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: context.picposText)),
                    if (subtitle != null)
                      Text(subtitle!,
                          style: TextStyle(
                              fontSize: 12, color: context.picposMuted)),
                  ],
                ),
              ),
              ?action,
            ]),
          ),
          Divider(height: 1, color: context.picposHairline),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.info.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.info.withValues(alpha: .4)),
      ),
      child: Text('$count',
          style: const TextStyle(
              fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.info)),
    );
  }
}

Future<void> showDmRouteDialog(BuildContext context, WidgetRef ref,
    {DistributionRoute? route}) async {
  final areas = await ref.read(dmAreasProvider.future);
  final reps = await ref.read(dmEmployeesProvider.future);
  if (!context.mounted) return;
  final name = TextEditingController(text: route?.name);
  final description = TextEditingController(text: route?.description);
  int? areaId = route?.areaId;
  int? repId = route?.repEmployeeId;
  final days = {...?route?.visitDays};
  final labels = dmWeekdayLabels();
  final saved = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text(route == null ? tr('مسار جديد') : tr('تعديل المسار')),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                key: const Key('dm_route_name'),
                controller: name,
                decoration: InputDecoration(labelText: tr('اسم المسار')),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<int?>(
                initialValue: areas.any((a) => a.id == areaId) ? areaId : null,
                decoration: InputDecoration(labelText: tr('منطقة التوزيع')),
                items: [
                  DropdownMenuItem(value: null, child: Text(tr('بلا منطقة'))),
                  for (final a in areas)
                    DropdownMenuItem(value: a.id, child: Text(a.name)),
                ],
                onChanged: (v) => setState(() => areaId = v),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<int?>(
                initialValue: reps.any((e) => e.id == repId) ? repId : null,
                decoration:
                    InputDecoration(labelText: tr('المندوب المسؤول')),
                items: [
                  DropdownMenuItem(value: null, child: Text(tr('بلا مندوب'))),
                  for (final e in reps)
                    DropdownMenuItem(value: e.id, child: Text(e.name)),
                ],
                onChanged: (v) => setState(() => repId = v),
              ),
              const SizedBox(height: 12),
              Text(tr('أيام الزيارة'),
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final e in labels.entries)
                  FilterChip(
                    label: Text(e.value),
                    selected: days.contains(e.key),
                    onSelected: (v) => setState(
                        () => v ? days.add(e.key) : days.remove(e.key)),
                  ),
              ]),
              const SizedBox(height: 10),
              TextField(
                controller: description,
                decoration: InputDecoration(labelText: tr('الوصف')),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr('إلغاء'))),
          FilledButton(
            key: const Key('dm_route_save'),
            onPressed: () async {
              try {
                await ref.read(databaseProvider).saveDistributionRoute(
                      id: route?.id,
                      name: name.text,
                      description: description.text,
                      areaId: areaId,
                      repEmployeeId: repId,
                      visitDays: days.toList(),
                    );
                if (ctx.mounted) Navigator.pop(ctx, true);
              } catch (e) {
                if (ctx.mounted) AppToast.show(ctx, '$e', type: ToastType.error);
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

/// إسنادُ عميلٍ إلى مسار. [routeId] مثبَّتٌ من شاشة المسار؛ و[customerId]
/// مثبَّتٌ من شاشة العملاء. ما ليس مثبَّتاً يُختار.
Future<void> showDmAssignCustomerDialog(BuildContext context, WidgetRef ref,
    {int? routeId, int? customerId}) async {
  final customers = await ref.read(dmCustomersProvider.future);
  final routes = await ref.read(dmRoutesProvider.future);
  final info = await ref.read(dmCustomerRouteInfoProvider.future);
  if (!context.mounted) return;
  int? pickedCustomer = customerId;
  int? pickedRoute = routeId ?? info[customerId]?.routeId;
  final saved = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) {
        final current = pickedCustomer == null ? null : info[pickedCustomer];
        return AlertDialog(
          title: Text(tr('إسناد عميل إلى مسار')),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (customerId == null)
                  DropdownButtonFormField<int>(
                    key: const Key('dm_assign_customer'),
                    initialValue: pickedCustomer,
                    isExpanded: true,
                    decoration: InputDecoration(labelText: tr('العميل')),
                    items: [
                      for (final c in customers)
                        DropdownMenuItem(value: c.id, child: Text(c.name)),
                    ],
                    onChanged: (v) => setState(() => pickedCustomer = v),
                  ),
                if (routeId == null)
                  DropdownButtonFormField<int>(
                    key: const Key('dm_assign_route'),
                    initialValue: pickedRoute,
                    isExpanded: true,
                    decoration: InputDecoration(labelText: tr('المسار')),
                    items: [
                      for (final r in routes)
                        DropdownMenuItem(
                            value: r.id,
                            child: Text(
                                '${r.name} — ${r.repName ?? tr('بلا مندوب')}')),
                    ],
                    onChanged: (v) => setState(() => pickedRoute = v),
                  ),
                if (current != null && current.routeId != pickedRoute) ...[
                  const SizedBox(height: 10),
                  Text(
                    tr('العميل على مسار «{p0}» وسيُنقل منه — يبقى التاريخ محفوظاً.',
                        {'p0': current.routeName}),
                    style: const TextStyle(color: AppColors.warning),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            if (customerId != null && info[customerId] != null)
              TextButton(
                onPressed: () async {
                  await ref
                      .read(databaseProvider)
                      .removeCustomerFromRoute(customerId);
                  if (ctx.mounted) Navigator.pop(ctx, true);
                },
                child: Text(tr('إزالة من المسار'),
                    style: const TextStyle(color: AppColors.error)),
              ),
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(tr('إلغاء'))),
            FilledButton(
              key: const Key('dm_assign_save'),
              onPressed: pickedCustomer == null || pickedRoute == null
                  ? null
                  : () async {
                      try {
                        await ref.read(databaseProvider).assignCustomerToRoute(
                            customerId: pickedCustomer!,
                            routeId: pickedRoute!);
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
        );
      },
    ),
  );
  if (saved == true) refreshDistribution(ref);
}
