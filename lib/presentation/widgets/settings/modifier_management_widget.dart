import 'package:picpos_erp/core/i18n/tr.dart';
import 'package:picpos_erp/core/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../core/permissions/permission_codes.dart';
import '../../../data/providers/providers.dart';
import '../../../domain/repositories/modifier_repository.dart';
import '../permission_guard.dart';

/// Modifier Groups Management Screen — Settings section (#15)
///
/// Allows creating, editing, and deleting modifier groups and their items.
/// Types: 'addon' (adds price) or 'option' (no price change).
///
/// ── دالة بناء مستخرجة (Task 6b) ───────────────────────────────────────────
/// زرار «مجموعة جديدة» كان بيوصل للشاشة دي من غير أي فحص صلاحية أصلاً —
/// الـ`ListTile` اللي بيفتحها في شاشتَي الإعدادات مالوش `PermissionGuard`
/// (بعكس `kdsSettings` جنبه بالظبط في نفس الملفين). مستخرج كدالة top-level
/// عشان يتبنى في اختبار widget خفيف من غير شاشة/قاعدة بيانات.
@visibleForTesting
Widget buildModifiersManageAddGroupButton({required VoidCallback onPressed}) {
  return PermissionGuard(
    permission: PermissionCodes.modifiersManage,
    allowManagerOverride: true,
    actionName: tr('مجموعة إضافات جديدة'),
    onGranted: onPressed,
    child: FilledButton.icon(
      onPressed: onPressed,
      icon: const Icon(PhosphorIconsBold.plus, size: 16),
      label:  Text(tr('مجموعة جديدة')),
    ),
  );
}

/// ٦‑٢ — كلُّ عمليّاتِ التعديل في هذه الشاشة كانت **بلا `try`**.
///
/// مسارُ القراءة (`_loadGroups`) وحدَه كان محروساً؛ أمّا الإضافةُ والحذفُ
/// والربطُ فتُنادى عاريةً بعد `Navigator.pop`. فحين كان `createModifierGroup`
/// ينهار على PostgreSQL — والجدولُ هناك كان ناقصَ خمسةِ أعمدة — كان الحوارُ
/// يُغلَق ولا يُضاف صفٌّ **ولا تظهر رسالة**: المستخدمُ يرى نجاحاً وهماً.
///
/// عطبُ المخطَّط عولج في مصدره ([AppDatabase.ensureModifierTables])، وهذا
/// حارسٌ ثانٍ: أيُّ إخفاقٍ لاحقٍ يظهر للمستخدم بدل أن يُبتلَع.
///
/// ويعود `true` عند النجاح فيبني المُنادي عليه قرارَ إعادة التحميل — فلا
/// تُعاد بناءُ القائمة على عمليّةٍ لم تقع.
@visibleForTesting
Future<bool> runModifierMutation(
  BuildContext context,
  Future<void> Function() action, {
  required String failureMessage,
}) async {
  try {
    await action();
    return true;
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$failureMessage: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
    return false;
  }
}

class ModifierManagementWidget extends ConsumerStatefulWidget {
  const ModifierManagementWidget({super.key});

  @override
  ConsumerState<ModifierManagementWidget> createState() => _ModifierManagementWidgetState();
}

class _ModifierManagementWidgetState extends ConsumerState<ModifierManagementWidget> {
  List<ModifierGroupData> _groups = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadGroups();
  }

  Future<void> _loadGroups() async {
    setState(() => _loading = true);
    final repo = ref.read(modifierRepositoryProvider);
    try {
      final groups = await repo.getAllGroups();
      if (mounted) setState(() { _groups = groups; _loading = false; });
    } catch (_) {
      // Tables may not exist if DB was created before v70 migration — create them
      try {
        await repo.ensureTables();
        final groups = await repo.getAllGroups();
        if (mounted) setState(() { _groups = groups; _loading = false; });
      } catch (e2) {
        if (mounted) setState(() { _groups = []; _loading = false; });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title:  Text(tr('إدارة الإضافات والخيارات')),
        actions: [
          buildModifiersManageAddGroupButton(onPressed: _showAddGroupDialog),
          const SizedBox(width: 12),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _groups.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(PhosphorIconsBold.forkKnife, size: 64, color: theme.colorScheme.outline),
                      const SizedBox(height: 16),
                      Text(tr('لا توجد مجموعات إضافات'), style: theme.textTheme.titleMedium),
                      const SizedBox(height: 8),
                      Text(tr('أضف مجموعة إضافات مثل "الصوصات" أو "الأحجام"'),
                          style: theme.textTheme.bodySmall),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _groups.length,
                  itemBuilder: (ctx, i) => _ModifierGroupCard(
                    group: _groups[i],
                    repo: ref.read(modifierRepositoryProvider),
                    onRefresh: _loadGroups,
                  ),
                ),
    );
  }

  Future<void> _showAddGroupDialog() async {
    final nameCtrl = TextEditingController();
    String type = 'addon';
    int minSelect = 0;
    int maxSelect = 1;
    bool isRequired = false;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title:  Text(tr('مجموعة إضافات جديدة')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration:  InputDecoration(
                    labelText: tr('اسم المجموعة'),
                    hintText: tr('مثال: الصوصات، الأحجام'),
                  ),
                ),
                const SizedBox(height: 12),
                SegmentedButton<String>(
                  segments:  [
                    ButtonSegment(value: 'addon', label: Text(tr('إضافة (بسعر)')), icon: const Icon(PhosphorIconsBold.plusCircle, size: 16)),
                    ButtonSegment(value: 'option', label: Text(tr('خيار (بدون سعر)')), icon: const Icon(PhosphorIconsBold.listBullets, size: 16)),
                  ],
                  selected: {type},
                  onSelectionChanged: (v) => setDialogState(() => type = v.first),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        decoration:  InputDecoration(labelText: tr('أقل اختيار')),
                        keyboardType: TextInputType.number,
                        controller: TextEditingController(text: '$minSelect'),
                        onChanged: (v) => minSelect = int.tryParse(v) ?? 0,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        decoration:  InputDecoration(labelText: tr('أكثر اختيار')),
                        keyboardType: TextInputType.number,
                        controller: TextEditingController(text: '$maxSelect'),
                        onChanged: (v) => maxSelect = int.tryParse(v) ?? 1,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  title:  Text(tr('مطلوب')),
                  subtitle:  Text(tr('يجب اختيار عنصر واحد على الأقل')),
                  value: isRequired,
                  onChanged: (v) => setDialogState(() => isRequired = v),
                  contentPadding: EdgeInsets.zero,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child:  Text(tr('إلغاء'))),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child:  Text(tr('إضافة')),
            ),
          ],
        ),
      ),
    );

    if (result == true && nameCtrl.text.isNotEmpty) {
      if (!mounted) return;
      final repo = ref.read(modifierRepositoryProvider);
      final ok = await runModifierMutation(
        context,
        () => repo.createGroup(
          name: nameCtrl.text,
          type: type,
          minSelect: minSelect,
          maxSelect: maxSelect,
          isRequired: isRequired,
        ),
        failureMessage: tr('تعذّرت إضافة المجموعة'),
      );
      if (ok) await _loadGroups();
    }
  }
}

class _ModifierGroupCard extends StatefulWidget {
  final ModifierGroupData group;
  final IModifierRepository repo;
  final VoidCallback onRefresh;

  const _ModifierGroupCard({required this.group, required this.repo, required this.onRefresh});

  @override
  State<_ModifierGroupCard> createState() => _ModifierGroupCardState();
}

class _ModifierGroupCardState extends State<_ModifierGroupCard> {
  List<ModifierItemData> _items = [];
  bool _expanded = false;

  Future<void> _loadItems() async {
    final items = await widget.repo.getItems(widget.group.id);
    if (mounted) setState(() => _items = items);
  }

  /// مستخرجة عشان `PermissionGuard.onGranted` و`IconButton.onPressed` ينادوا
  /// نفس المنطق بالظبط من غير تكرار — الحارس بيمرّر الفعل صراحة (مش بيخمّنه).
  Future<void> _confirmAndDeleteGroup(
    BuildContext context,
    ModifierGroupData g,
  ) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title:  Text(tr('حذف المجموعة')),
        content: Text(tr('هل تريد حذف "{p0}" وجميع عناصرها؟', {'p0': g.name})),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child:  Text(tr('إلغاء'))),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            child:  Text(tr('حذف')),
          ),
        ],
      ),
    );
    if (confirm == true) {
      if (!context.mounted) return;
      final ok = await runModifierMutation(
        context,
        () => widget.repo.deleteGroup(g.id),
        failureMessage: tr('تعذّر حذف المجموعة'),
      );
      if (ok) widget.onRefresh();
    }
  }

  /// مستخرجة لنفس السبب: `PermissionGuard.onGranted` و`IconButton.onPressed`
  /// ينادوا نفس الفعل صراحة.
  Future<void> _deleteItem(ModifierItemData item) async {
    final ok = await runModifierMutation(
      context,
      () => widget.repo.deleteItem(item.id),
      failureMessage: tr('تعذّر حذف العنصر'),
    );
    if (ok) _loadItems();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final g = widget.group;
    final typeLabel = g.type == 'addon' ? tr('إضافة') : tr('خيار');
    final typeColor = g.type == 'addon'
        ? theme.colorScheme.primary
        : theme.colorScheme.tertiary;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        children: [
          ListTile(
            leading: CircleAvatar(
              backgroundColor: typeColor.withValues(alpha: 0.15),
              child: Icon(
                g.type == 'addon' ? PhosphorIconsBold.plusCircle : PhosphorIconsBold.listBullets,
                color: typeColor,
                size: 20,
              ),
            ),
            title: Text(g.name, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
            subtitle: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: typeColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(typeLabel, style: TextStyle(fontSize: 10, color: typeColor)),
                ),
                const SizedBox(width: 8),
                if (g.isRequired) ...[
                  const Icon(PhosphorIconsBold.asteriskSimple, size: 12, color: AppColors.error),
                   Text(tr(' مطلوب'), style: const TextStyle(fontSize: 10, color: AppColors.error)),
                  const SizedBox(width: 8),
                ],
                Text(tr('{p0}-{p1} اختيار', {'p0': g.minSelect, 'p1': g.maxSelect}), style: theme.textTheme.bodySmall),
              ],
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                PermissionGuard(
                  permission: PermissionCodes.modifiersManage,
                  allowManagerOverride: true,
                  actionName: tr('ربط أصناف بمجموعة إضافات'),
                  onGranted: () => _showLinkProductsDialog(),
                  child: IconButton(
                    icon: const Icon(PhosphorIconsBold.link, size: 18),
                    tooltip: tr('ربط الأصناف'),
                    onPressed: () => _showLinkProductsDialog(),
                  ),
                ),
                PermissionGuard(
                  permission: PermissionCodes.modifiersManage,
                  allowManagerOverride: true,
                  actionName: tr('حذف مجموعة إضافات'),
                  onGranted: () => _confirmAndDeleteGroup(context, g),
                  child: IconButton(
                    icon: const Icon(PhosphorIconsBold.trash, size: 18),
                    onPressed: () => _confirmAndDeleteGroup(context, g),
                  ),
                ),
                IconButton(
                  icon: Icon(_expanded ? PhosphorIconsBold.caretUp : PhosphorIconsBold.caretDown, size: 18),
                  onPressed: () {
                    setState(() => _expanded = !_expanded);
                    if (_expanded) _loadItems();
                  },
                ),
              ],
            ),
          ),
          if (_expanded) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                children: [
                  ..._items.map((item) => ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          item.isDefault ? PhosphorIconsBold.checkCircle : PhosphorIconsBold.circle,
                          size: 18,
                          color: item.isDefault ? theme.colorScheme.primary : theme.colorScheme.outline,
                        ),
                        title: Text(item.name),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (item.extraPrice > 0)
                              Chip(
                                label: Text('+${item.extraPrice.toStringAsFixed(0)}', style: const TextStyle(fontSize: 11)),
                                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                visualDensity: VisualDensity.compact,
                              ),
                            PermissionGuard(
                              permission: PermissionCodes.modifiersManage,
                              allowManagerOverride: true,
                              actionName: tr('حذف عنصر إضافة'),
                              onGranted: () => _deleteItem(item),
                              child: IconButton(
                                icon: const Icon(PhosphorIconsBold.trash, size: 16),
                                onPressed: () => _deleteItem(item),
                              ),
                            ),
                          ],
                        ),
                      )),
                  PermissionGuard(
                    permission: PermissionCodes.modifiersManage,
                    allowManagerOverride: true,
                    actionName: tr('إضافة عنصر إضافة'),
                    onGranted: () => _showAddItemDialog(),
                    child: TextButton.icon(
                      onPressed: () => _showAddItemDialog(),
                      icon: const Icon(PhosphorIconsBold.plus, size: 14),
                      label:  Text(tr('إضافة عنصر')),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _showLinkProductsDialog() async {
    // Get all products and currently linked product IDs
    final repo = widget.repo;
    final allProducts = await repo.getAllProducts();
    final allCategories = await repo.getAllCategories();
    final categoryMap = {for (final c in allCategories) c.id: c.name};
    final linkedIds = await repo.getLinkedProductIdsForGroup(widget.group.id);
    final selected = Set<int>.from(linkedIds);
    String searchQuery = '';

    if (!mounted) return;

    final result = await showDialog<Set<int>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final filtered = searchQuery.isEmpty
              ? allProducts
              : allProducts.where((p) => p.name.contains(searchQuery)).toList();

          return AlertDialog(
            title: Row(
              children: [
                const Icon(PhosphorIconsBold.link, size: 20),
                const SizedBox(width: 8),
                Expanded(child: Text('\u0631\u0628\u0637 \u0627\u0644\u0623\u0635\u0646\u0627\u0641 \u0628\u0640 "${widget.group.name}"')),
              ],
            ),
            content: SizedBox(
              width: 450,
              height: 400,
              child: Column(
                children: [
                  TextField(
                    decoration:  InputDecoration(
                      hintText: tr('بحث عن صنف...'),
                      prefixIcon: const Icon(PhosphorIconsBold.magnifyingGlass, size: 18),
                      isDense: true,
                    ),
                    onChanged: (v) => setDialogState(() => searchQuery = v),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text('${selected.length} \u0635\u0646\u0641 \u0645\u062d\u062f\u062f',
                          style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.primary)),
                      const Spacer(),
                      TextButton(
                        onPressed: () => setDialogState(() => selected.addAll(filtered.map((p) => p.id))),
                        child:  Text(tr('تحديد الكل'), style: const TextStyle(fontSize: 12)),
                      ),
                      TextButton(
                        onPressed: () => setDialogState(() => selected.clear()),
                        child:  Text(tr('إلغاء الكل'), style: const TextStyle(fontSize: 12)),
                      ),
                    ],
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: ListView.builder(
                      itemCount: filtered.length,
                      itemBuilder: (ctx, i) {
                        final p = filtered[i];
                        return CheckboxListTile(
                          dense: true,
                          title: Text(p.name, style: const TextStyle(fontSize: 13)),
                          subtitle: p.categoryId != null && categoryMap.containsKey(p.categoryId)
                              ? Text(categoryMap[p.categoryId]!, style: const TextStyle(fontSize: 11))
                              : null,
                          value: selected.contains(p.id),
                          onChanged: (v) {
                            setDialogState(() {
                              if (v == true) {
                                selected.add(p.id);
                              } else {
                                selected.remove(p.id);
                              }
                            });
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child:  Text(tr('إلغاء'))),
              FilledButton(
                onPressed: () => Navigator.pop(context, selected),
                child:  Text(tr('حفظ')),
              ),
            ],
          );
        },
      ),
    );

    if (result != null) {
      if (!mounted) return;
      // Update links: for each product, set its modifier groups
      final groupId = widget.group.id;

      // Get currently linked product IDs
      final currentLinked = Set<int>.from(linkedIds);

      // Products to add link
      final toAdd = result.difference(currentLinked);
      // Products to remove link
      final toRemove = currentLinked.difference(result);

      final ok = await runModifierMutation(
        context,
        () async {
          for (final productId in toAdd) {
            await repo.linkModifierToProduct(
                productId: productId, modifierGroupId: groupId);
          }
          for (final productId in toRemove) {
            await repo.unlinkModifierFromProduct(
                productId: productId, modifierGroupId: groupId);
          }
        },
        failureMessage: tr('تعذّر ربط المجموعة بالأصناف'),
      );

      if (ok && mounted) {
        setState(() {}); // Refresh card
      }
    }
  }

  Future<void> _showAddItemDialog() async {
    final nameCtrl = TextEditingController();
    final priceCtrl = TextEditingController(text: '0');
    bool isDefault = false;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title:  Text(tr('عنصر جديد')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration:  InputDecoration(labelText: tr('الاسم'), hintText: tr('مثال: كاتشب، جبن إضافي')),
              ),
              if (widget.group.type == 'addon') ...[
                const SizedBox(height: 12),
                TextField(
                  controller: priceCtrl,
                  decoration:  InputDecoration(labelText: tr('السعر الإضافي')),
                  keyboardType: TextInputType.number,
                ),
              ],
              const SizedBox(height: 8),
              SwitchListTile(
                title:  Text(tr('افتراضي')),
                value: isDefault,
                onChanged: (v) => setDialogState(() => isDefault = v),
                contentPadding: EdgeInsets.zero,
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child:  Text(tr('إلغاء'))),
            FilledButton(onPressed: () => Navigator.pop(context, true), child:  Text(tr('إضافة'))),
          ],
        ),
      ),
    );

    if (result == true && nameCtrl.text.isNotEmpty) {
      if (!mounted) return;
      final ok = await runModifierMutation(
        context,
        () => widget.repo.createItem(
          groupId: widget.group.id,
          name: nameCtrl.text,
          extraPrice: double.tryParse(priceCtrl.text) ?? 0,
          isDefault: isDefault,
        ),
        failureMessage: tr('تعذّرت إضافة العنصر'),
      );
      if (ok) _loadItems();
    }
  }
}
