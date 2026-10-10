import 'package:ural_erp/core/i18n/tr.dart';
// ═══════════════════════════════════════════════════════════════════════════
// PARTY GROUPS TAB — Phase 2
// ═══════════════════════════════════════════════════════════════════════════
//
// Management UI for party groups, mounted as the third tab of
// `PartiesScreen`. Displays groups with their member counts, exposes
// CRUD via small dialogs, and offers a "view members" drill-down.
//
// Bulk-operation hooks (apply discount, settle balance, financial
// close) are deliberately stubbed as "Coming soon" popups — the user
// asked for the grouping infrastructure only; the accounting behaviour
// will be wired up in a later phase once the domain rules are pinned.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../data/database/database.dart';
import '../../../web/web_write_guard.dart';
import 'providers/party_groups_controller.dart';

class PartyGroupsTab extends ConsumerWidget {
  const PartyGroupsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groupsAsync = ref.watch(partyGroupsWithCountsProvider);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _showEditDialog(context, ref, group: null),
          icon: const Icon(PhosphorIconsBold.plus),
          label:  Text(tr('مجموعة جديدة')),
          backgroundColor: AppColors.primary,
        ),
        body: groupsAsync.when(
          data: (groups) {
            if (groups.isEmpty) {
              return _EmptyState(
                onCreate: () => _showEditDialog(context, ref, group: null),
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: groups.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final row = groups[i];
                return _GroupCard(
                  group: row.group,
                  memberCount: row.memberCount,
                  onEdit: () =>
                      _showEditDialog(context, ref, group: row.group),
                  onDelete: () => _confirmDelete(
                    context,
                    ref,
                    group: row.group,
                    memberCount: row.memberCount,
                  ),
                  onViewMembers: () =>
                      _showMembersDialog(context, ref, group: row.group),
                  onToggleActive: () async {
                    if (!WebWriteGuard.allow(context,
                        feature: tr('مجموعات العملاء'))) {
                      return;
                    }
                    final ok = await ref
                        .read(partyGroupsControllerProvider.notifier)
                        .setActive(row.group.id, !row.group.isActive);
                    if (!context.mounted) return;
                    AppToast.show(
                      context,
                      ok
                          ? (row.group.isActive
                              ? tr('تم تعطيل المجموعة')
                              : tr('تم تفعيل المجموعة'))
                          : tr('فشل تعديل الحالة'),
                      type:
                          ok ? ToastType.success : ToastType.error,
                    );
                  },
                );
              },
            );
          },
          loading: () =>
              const Center(child: CircularProgressIndicator()),
          error: (err, _) => Center(
            child: Text(tr('خطأ فى تحميل المجموعات: {err}', {'err': err})),
          ),
        ),
      ),
    );
  }

  // ── Edit / Create dialog ────────────────────────────────────────

  Future<void> _showEditDialog(
    BuildContext context,
    WidgetRef ref, {
    required PartyGroup? group,
  }) async {
    final nameCtl = TextEditingController(text: group?.name ?? '');
    final descCtl = TextEditingController(text: group?.description ?? '');
    final discountCtl = TextEditingController(
      text: (group?.defaultDiscount ?? 0).toString(),
    );
    final termsCtl =
        TextEditingController(text: group?.defaultPaymentTerms ?? '');
    final notesCtl = TextEditingController(text: group?.notes ?? '');
    String type = group?.type ?? 'both';
    String? priceLevel = group?.priceLevel;
    bool isSaving = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: StatefulBuilder(
          builder: (ctx, setSt) => AlertDialog(
            title: Row(
              children: [
                Icon(
                  group == null
                      ? PhosphorIconsBold.plus
                      : PhosphorIconsBold.pencil,
                  color: AppColors.primary,
                ),
                const SizedBox(width: 8),
                Text(group == null ? tr('مجموعة جديدة') : tr('تعديل المجموعة')),
              ],
            ),
            content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                     Text(
                      tr('نوع المجموعة'),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    SegmentedButton<String>(
                      segments:  [
                        ButtonSegment(
                          value: 'customer',
                          label: Text(tr('عملاء')),
                          icon: const Icon(PhosphorIconsBold.user, size: 16),
                        ),
                        ButtonSegment(
                          value: 'supplier',
                          label: Text(tr('موردين')),
                          icon: const Icon(PhosphorIconsBold.truck, size: 16),
                        ),
                        ButtonSegment(
                          value: 'both',
                          label: Text(tr('الاثنين')),
                          icon:
                              const Icon(PhosphorIconsBold.usersThree, size: 16),
                        ),
                      ],
                      selected: {type},
                      onSelectionChanged: (s) =>
                          setSt(() => type = s.first),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: nameCtl,
                      decoration:  InputDecoration(
                        labelText: tr('اسم المجموعة *'),
                        prefixIcon: const Icon(PhosphorIconsBold.tag),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: descCtl,
                      maxLines: 2,
                      decoration:  InputDecoration(
                        labelText: tr('الوصف'),
                        prefixIcon:
                            const Icon(PhosphorIconsBold.textAlignLeft),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Divider(),
                    const SizedBox(height: 4),
                     Text(
                      tr('الافتراضيات التجارية (للاستخدام اليدوى)'),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 4),
                     Text(
                      tr('هذه الحقول مرجعية فقط — تُطبَّق يدوياً عبر العمليات المجمعة ولا تُفرض تلقائياً على كل فاتورة.'),
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textMuted,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: discountCtl,
                            keyboardType: TextInputType.number,
                            decoration:  InputDecoration(
                              labelText: tr('خصم افتراضى %'),
                              prefixIcon:
                                  const Icon(PhosphorIconsBold.percent),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: termsCtl,
                            decoration:  InputDecoration(
                              labelText: tr('شروط الدفع'),
                              hintText: tr('مثال: 30 يوم'),
                              prefixIcon:
                                  const Icon(PhosphorIconsBold.calendar),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String?>(
                      initialValue: priceLevel,
                      decoration:  InputDecoration(
                        labelText: tr('مستوى السعر الافتراضى'),
                        prefixIcon: const Icon(PhosphorIconsBold.tag),
                      ),
                      items:  [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('—'),
                        ),
                        DropdownMenuItem(
                          value: 'default',
                          child: Text(tr('عادى')),
                        ),
                        DropdownMenuItem(
                          value: 'talabat',
                          child: Text(tr('طلبات')),
                        ),
                        DropdownMenuItem(
                          value: 'careem',
                          child: Text(tr('كريم')),
                        ),
                        DropdownMenuItem(
                          value: 'ashyae',
                          child: Text(tr('أشيائى')),
                        ),
                      ],
                      onChanged: (v) => setSt(() => priceLevel = v),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: notesCtl,
                      maxLines: 2,
                      decoration:  InputDecoration(
                        labelText: tr('ملاحظات'),
                        prefixIcon: const Icon(PhosphorIconsBold.note),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed:
                    isSaving ? null : () => Navigator.pop(ctx),
                child:  Text(tr('إلغاء')),
              ),
              ElevatedButton.icon(
                onPressed: isSaving
                    ? null
                    : () async {
                        if (nameCtl.text.trim().isEmpty) {
                          AppToast.show(
                            ctx,
                            tr('يرجى إدخال اسم المجموعة'),
                            type: ToastType.error,
                          );
                          return;
                        }
                        setSt(() => isSaving = true);
                        final discount =
                            double.tryParse(discountCtl.text) ?? 0;
                        final controller = ref.read(
                            partyGroupsControllerProvider.notifier);
                        final ok = group == null
                            ? (await controller.createGroup(
                                  name: nameCtl.text.trim(),
                                  type: type,
                                  description: descCtl.text.isEmpty
                                      ? null
                                      : descCtl.text,
                                  defaultDiscount: discount,
                                  defaultPaymentTerms:
                                      termsCtl.text.isEmpty
                                          ? null
                                          : termsCtl.text,
                                  priceLevel: priceLevel,
                                  notes: notesCtl.text.isEmpty
                                      ? null
                                      : notesCtl.text,
                                )) !=
                                null
                            : await controller.updateGroup(
                                id: group.id,
                                name: nameCtl.text.trim(),
                                type: type,
                                description: descCtl.text,
                                defaultDiscount: discount,
                                defaultPaymentTerms: termsCtl.text,
                                priceLevel: priceLevel,
                                notes: notesCtl.text,
                              );
                        if (!ctx.mounted) return;
                        Navigator.pop(ctx);
                        if (!context.mounted) return;
                        AppToast.show(
                          context,
                          ok
                              ? (group == null
                                  ? tr('تم إنشاء المجموعة')
                                  : tr('تم تعديل المجموعة'))
                              : tr('فشل الحفظ'),
                          type: ok
                              ? ToastType.success
                              : ToastType.error,
                        );
                      },
                icon: isSaving
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(PhosphorIconsBold.floppyDisk),
                label:  Text(tr('حفظ')),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Delete confirmation ─────────────────────────────────────────

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref, {
    required PartyGroup group,
    required int memberCount,
  }) async {
    if (memberCount > 0) {
      // Fast-path: skip the confirmation entirely — deleting will fail
      // in the DAO, so we explain up front and nudge the user to
      // archive/reassign.
      await showDialog<void>(
        context: context,
        builder: (ctx) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            icon: const Icon(
              PhosphorIconsBold.warning,
              color: AppColors.warning,
              size: 40,
            ),
            title:  Text(tr('لا يمكن الحذف')),
            content: Text(
              tr('المجموعة "{p0}" بها {memberCount} طرف. انقل الأطراف لمجموعة أخرى أولاً، أو قم بتعطيلها بدلاً من الحذف.', {'p0': group.name, 'memberCount': memberCount}),
              textAlign: TextAlign.center,
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child:  Text(tr('موافق')),
              ),
            ],
          ),
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title:  Text(tr('تأكيد الحذف')),
          content: Text(tr('هل تريد حذف المجموعة "{p0}"؟', {'p0': group.name})),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child:  Text(tr('إلغاء')),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error,
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child:  Text(tr('حذف')),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;

    final ok = await ref
        .read(partyGroupsControllerProvider.notifier)
        .deleteGroup(group.id);
    if (!context.mounted) return;
    AppToast.show(
      context,
      ok ? tr('تم حذف المجموعة') : tr('فشل الحذف'),
      type: ok ? ToastType.success : ToastType.error,
    );
  }

  // ── Members drill-down ──────────────────────────────────────────

  Future<void> _showMembersDialog(
    BuildContext context,
    WidgetRef ref, {
    required PartyGroup group,
  }) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Row(
            children: [
              const Icon(
                PhosphorIconsBold.usersThree,
                color: AppColors.primary,
              ),
              const SizedBox(width: 8),
              Text(tr('أعضاء: {p0}', {'p0': group.name})),
            ],
          ),
          content: SizedBox(
            width: 500,
            height: 400,
            child: Consumer(
              builder: (context, ref, _) {
                final membersAsync = ref.watch(
                  partyGroupMembersProvider(group.id),
                );
                return membersAsync.when(
                  data: (members) {
                    if (members.isEmpty) {
                      return  Center(
                        child: Text(
                          tr('لا توجد أطراف فى هذه المجموعة حتى الآن.\nمن شاشة العملاء أو الموردين، افتح تعديل أى طرف واختر هذه المجموعة من قائمة "المجموعة".'),
                          textAlign: TextAlign.center,
                        ),
                      );
                    }
                    return ListView.separated(
                      itemCount: members.length,
                      separatorBuilder: (_, _) =>
                          const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final p = members[i];
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor:
                                AppColors.primary.withValues(alpha: 0.1),
                            child: Text(
                              p.name.isNotEmpty
                                  ? p.name[0].toUpperCase()
                                  : '?',
                              style: const TextStyle(
                                color: AppColors.primary,
                              ),
                            ),
                          ),
                          title: Text(p.name),
                          subtitle: Text(
                            '${p.code ?? '—'}  ·  '
                            '${p.isCustomer ? "عميل " : ""}'
                            '${p.isSupplier ? "مورد" : ""}',
                          ),
                          trailing: IconButton(
                            icon: const Icon(
                              PhosphorIconsBold.x,
                              size: 16,
                              color: AppColors.error,
                            ),
                            tooltip: tr('إزالة من المجموعة'),
                            onPressed: WebWriteGuard.wrap(context, () => ref
                                .read(partyGroupsControllerProvider
                                    .notifier)
                                .assignParty(p.id, null),
                                feature: tr('مجموعات العملاء')),
                          ),
                        );
                      },
                    );
                  },
                  loading: () => const Center(
                      child: CircularProgressIndicator()),
                  error: (e, _) =>
                      Center(child: Text(tr('خطأ: {e}', {'e': e}))),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child:  Text(tr('إغلاق')),
            ),
          ],
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════
// Empty state
// ═════════════════════════════════════════════════════════════════════

class _EmptyState extends StatelessWidget {
  final VoidCallback onCreate;
  const _EmptyState({required this.onCreate});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            PhosphorIconsBold.usersThree,
            size: 64,
            color: AppColors.textMuted,
          ),
          const SizedBox(height: 12),
           Text(
            tr('لا توجد مجموعات بعد'),
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
           Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              tr('المجموعات تُمكّنك من تقسيم العملاء والموردين لفئات (جملة، VIP، تجزئة، ...) ثم تطبيق خصومات أو تسويات مالية مجمّعة عليهم دفعة واحدة.'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textMuted,
              ),
            ),
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: onCreate,
            icon: const Icon(PhosphorIconsBold.plus),
            label:  Text(tr('إنشاء أول مجموعة')),
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════
// Group card
// ═════════════════════════════════════════════════════════════════════

class _GroupCard extends StatelessWidget {
  final PartyGroup group;
  final int memberCount;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onViewMembers;
  final VoidCallback onToggleActive;

  const _GroupCard({
    required this.group,
    required this.memberCount,
    required this.onEdit,
    required this.onDelete,
    required this.onViewMembers,
    required this.onToggleActive,
  });

  String get _typeLabel => switch (group.type) {
        'customer' => tr('عملاء'),
        'supplier' => tr('موردين'),
        _ => tr('عملاء وموردين'),
      };

  Color get _typeColor => switch (group.type) {
        'customer' => AppColors.primary,
        'supplier' => AppColors.warning,
        _ => AppColors.info,
      };

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: group.isActive
              ? AppColors.border
              : AppColors.warning.withValues(alpha: 0.4),
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onViewMembers,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: _typeColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      PhosphorIconsBold.usersThree,
                      color: _typeColor,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                group.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            if (!group.isActive)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.warning
                                      .withValues(alpha: 0.15),
                                  borderRadius:
                                      BorderRadius.circular(4),
                                ),
                                child:  Text(
                                  tr('معطّلة'),
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: AppColors.warning,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: _typeColor.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                _typeLabel,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: _typeColor,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Icon(
                              PhosphorIconsBold.user,
                              size: 12,
                              color: AppColors.textMuted,
                            ),
                            const SizedBox(width: 2),
                            Text(
                              tr('{memberCount} عضو', {'memberCount': memberCount}),
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    tooltip: tr('إجراءات'),
                    icon: const Icon(PhosphorIconsBold.dotsThreeVertical),
                    onSelected: (v) {
                      switch (v) {
                        case 'edit':
                          onEdit();
                          break;
                        case 'members':
                          onViewMembers();
                          break;
                        case 'toggle':
                          onToggleActive();
                          break;
                        case 'delete':
                          onDelete();
                          break;
                      }
                    },
                    itemBuilder: (_) => [
                       PopupMenuItem(
                        value: 'members',
                        child: ListTile(
                          leading: const Icon(PhosphorIconsBold.users),
                          title: Text(tr('عرض الأعضاء')),
                          dense: true,
                        ),
                      ),
                       PopupMenuItem(
                        value: 'edit',
                        child: ListTile(
                          leading: const Icon(PhosphorIconsBold.pencil),
                          title: Text(tr('تعديل')),
                          dense: true,
                        ),
                      ),
                      PopupMenuItem(
                        value: 'toggle',
                        child: ListTile(
                          leading: Icon(group.isActive
                              ? PhosphorIconsBold.pause
                              : PhosphorIconsBold.play),
                          title: Text(group.isActive
                              ? tr('تعطيل')
                              : tr('تفعيل')),
                          dense: true,
                        ),
                      ),
                       PopupMenuItem(
                        value: 'delete',
                        child: ListTile(
                          leading: const Icon(
                            PhosphorIconsBold.trash,
                            color: AppColors.error,
                          ),
                          title: Text(
                            tr('حذف'),
                            style:
                                const TextStyle(color: AppColors.error),
                          ),
                          dense: true,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              if ((group.description ?? '').isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  group.description!,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
              if (group.defaultDiscount > 0 ||
                  (group.defaultPaymentTerms ?? '').isNotEmpty ||
                  (group.priceLevel ?? '').isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    if (group.defaultDiscount > 0)
                      _MiniChip(
                        icon: PhosphorIconsBold.percent,
                        label: tr('خصم {p0}%', {'p0': group.defaultDiscount}),
                      ),
                    if ((group.defaultPaymentTerms ?? '').isNotEmpty)
                      _MiniChip(
                        icon: PhosphorIconsBold.calendar,
                        label: group.defaultPaymentTerms!,
                      ),
                    if ((group.priceLevel ?? '').isNotEmpty)
                      _MiniChip(
                        icon: PhosphorIconsBold.tag,
                        label: group.priceLevel!,
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _MiniChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: AppColors.textMuted),
          const SizedBox(width: 3),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}
