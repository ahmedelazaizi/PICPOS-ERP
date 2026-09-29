import 'package:ural_erp/core/i18n/tr.dart';
// ignore_for_file: avoid_dynamic_calls
import 'package:flutter/material.dart';
import 'package:ural_erp/core/utils/number_utils.dart';
import 'package:ural_erp/core/widgets/app_toast.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:drift/drift.dart' hide Column;
import '../../../core/theme/app_colors.dart';
import '../../../core/constants/app_constants.dart';
import '../../../data/providers/providers.dart';
import '../../../services/client_write_interceptor.dart';
import '../../../data/database/sync_interceptor.dart';
import 'party_helpers.dart';
import 'providers/party_groups_controller.dart';

// ═══════════════════════════════════════════════════════════════════════════
// PARTY DIALOGS — Add, Edit, Delete
// ═══════════════════════════════════════════════════════════════════════════

/// Shows the Add Party dialog.
void showAddPartyDialog(BuildContext context, WidgetRef ref) {
  final nameController = TextEditingController();
  final codeController = TextEditingController();
  final phoneController = TextEditingController();
  final openingBalanceController = TextEditingController(text: '0');
  final creditLimitController = TextEditingController(text: '0');
  String selectedType = 'customer';
  String selectedPriceLevel = 'default';
  int? selectedGroupId;
  List<int> selectedBranchIds = [];
  int? selectedCostCenterId;

  // Auto-populate the party code using the DAO's sequence generator.
  // Recomputed whenever the selected type changes so the prefix stays
  // in sync (CUST-/SUP-/CS-/DLV-). The user may overwrite the field
  // before saving — uniqueness is enforced inside insertParty.
  Future<void> refreshCodeSuggestion() async {
    try {
      final db = ref.read(databaseProvider);
      final next = await db.getNextPartyCode(
        isCustomer: selectedType == 'customer' || selectedType == 'both',
        isSupplier: selectedType == 'supplier' || selectedType == 'both',
        isDeliveryCompany: selectedType == 'delivery',
      );
      codeController.text = next;
    } catch (_) {
      // Fall back silently to empty — the DAO will auto-generate on save.
    }
  }
  // Seed the code once the dialog's first frame is ready.
  WidgetsBinding.instance.addPostFrameCallback((_) => refreshCodeSuggestion());

  bool saving = false;

  showDialog(
    context: context,
    builder: (context) => Directionality(
      textDirection: TextDirection.rtl,
      child: StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title:  Row(
            children: [
              const Icon(PhosphorIconsBold.userPlus, color: AppColors.primary),
              const SizedBox(width: 8),
              Text(tr('إضافة طرف جديد')),
            ],
          ),
          content: SizedBox(
            width: 500,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                   Text(
                    tr('نوع الطرف *'),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  SegmentedButton<String>(
                    segments:  [
                      ButtonSegment(
                        value: 'customer',
                        label: Text(tr('عميل')),
                        icon: const Icon(PhosphorIconsBold.user, size: 16),
                      ),
                      ButtonSegment(
                        value: 'supplier',
                        label: Text(tr('مورد')),
                        icon: const Icon(PhosphorIconsBold.truck, size: 16),
                      ),
                      ButtonSegment(
                        value: 'delivery',
                        label: Text(tr('توصيل')),
                        icon: const Icon(PhosphorIconsBold.moped, size: 16),
                      ),
                      ButtonSegment(
                        value: 'both',
                        label: Text(tr('عميل مورد')),
                        icon: const Icon(PhosphorIconsBold.usersThree, size: 16),
                      ),
                    ],
                    selected: {selectedType},
                    onSelectionChanged: (val) {
                      setDialogState(() => selectedType = val.first);
                      // Refresh the code suggestion so the prefix follows
                      // the newly-selected role (CUST↔SUP↔CS↔DLV).
                      refreshCodeSuggestion().then((_) {
                        if (context.mounted) setDialogState(() {});
                      });
                    },
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: TextField(
                          controller: nameController,
                          decoration:  InputDecoration(
                            labelText: tr('الاسم *'),
                            prefixIcon: const Icon(PhosphorIconsBold.identificationCard),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 2,
                        child: TextField(
                          controller: codeController,
                          decoration:  InputDecoration(
                            labelText: tr('الكود'),
                            prefixIcon: const Icon(PhosphorIconsBold.hash),
                            helperText: tr('يُولَّد تلقائياً — قابل للتعديل'),
                            helperMaxLines: 2,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: phoneController,
                    decoration:  InputDecoration(
                      labelText: tr('رقم الهاتف'),
                      prefixIcon: const Icon(PhosphorIconsBold.phone),
                    ),
                    keyboardType: TextInputType.phone,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: openingBalanceController,
                          decoration: InputDecoration(
                            labelText: tr('الرصيد الافتتاحي'),
                            prefixIcon: const Icon(PhosphorIconsBold.wallet),
                            suffixText: AppConstants.currencySymbolEn,
                          ),
                          keyboardType: TextInputType.number,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: creditLimitController,
                          decoration: InputDecoration(
                            labelText: tr('الحد الائتماني'),
                            prefixIcon: const Icon(PhosphorIconsBold.creditCard),
                            suffixText: AppConstants.currencySymbolEn,
                          ),
                          keyboardType: TextInputType.number,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (selectedType == 'customer' || selectedType == 'both')
                    DropdownButtonFormField<String>(
                      initialValue: selectedPriceLevel,
                      decoration:  InputDecoration(
                        labelText: tr('تصنيف السعر'),
                        prefixIcon: const Icon(PhosphorIconsBold.tag),
                      ),
                      items: kPriceLevels.entries
                          .map(
                            (e) => DropdownMenuItem(
                              value: e.key,
                              child: Text(e.value),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        setDialogState(
                          () => selectedPriceLevel = value ?? 'default',
                        );
                      },
                    ),
                  const SizedBox(height: 12),
                  // Group picker — filters by the selected role so a
                  // "Suppliers wholesale" group only appears for suppliers.
                  // A group tagged type=both is always shown.
                  Consumer(builder: (ctx, ref, _) {
                    final groupsAsync =
                        ref.watch(activePartyGroupsProvider);
                    return groupsAsync.maybeWhen(
                      data: (groups) {
                        final filtered = groups.where((g) {
                          if (g.type == 'both') return true;
                          if (selectedType == 'both') return true;
                          return g.type == selectedType ||
                              (selectedType == 'delivery' &&
                                  g.type == 'supplier');
                        }).toList();
                        return DropdownButtonFormField<int?>(
                          initialValue: selectedGroupId,
                          decoration:  InputDecoration(
                            labelText: tr('المجموعة'),
                            prefixIcon:
                                const Icon(PhosphorIconsBold.usersThree),
                            helperText: tr('اختيارى — يمكن تركها فارغة'),
                          ),
                          items: [
                             DropdownMenuItem<int?>(
                              value: null,
                              child: Text(tr('— بدون مجموعة —')),
                            ),
                            ...filtered.map(
                              (g) => DropdownMenuItem<int?>(
                                value: g.id,
                                child: Text(g.name),
                              ),
                            ),
                          ],
                          onChanged: (v) => setDialogState(
                              () => selectedGroupId = v),
                        );
                      },
                      orElse: () => const SizedBox.shrink(),
                    );
                  }),
                  const SizedBox(height: 12),
                  // Branch assignment — always shown so the admin can
                  // decide global vs branch-specific from the start
                  // (still hidden when zero branches exist, which only
                  // happens before the seeder has run).
                  Consumer(builder: (ctx, ref, _) {
                    final branchesAsync = ref.watch(allBranchesProvider);
                    return branchesAsync.maybeWhen(
                      data: (branches) {
                        if (branches.isEmpty) return const SizedBox.shrink();
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                             Text(tr('تحديد الفروع'),
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                            const SizedBox(height: 2),
                             Text(tr('اتركها فارغة لإتاحة الطرف لكل الفروع'),
                                style: const TextStyle(fontSize: 11, color: Colors.grey)),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 6, runSpacing: 4,
                              children: branches.map((b) {
                                final sel = selectedBranchIds.contains(b.id);
                                return FilterChip(
                                  label: Text(b.name, style: const TextStyle(fontSize: 12)),
                                  selected: sel,
                                  onSelected: (v) => setDialogState(() {
                                    if (v) selectedBranchIds.add(b.id);
                                    else selectedBranchIds.remove(b.id);
                                  }),
                                );
                              }).toList(),
                            ),
                          ],
                        );
                      },
                      orElse: () => const SizedBox.shrink(),
                    );
                  }),
                  const SizedBox(height: 12),
                  // Cost center — always rendered (with a "— بدون —" option)
                  // so the admin can leave it empty deliberately rather
                  // than silently inheriting nothing.
                  Consumer(builder: (ctx, ref, _) {
                    final accountingRepo = ref.watch(accountingRepositoryProvider);
                    return FutureBuilder<List<CostCenter>>(
                      future: accountingRepo.getActiveCostCenters(),
                      builder: (context, snap) {
                        final ccList = snap.data ?? const <CostCenter>[];
                        return DropdownButtonFormField<int?>(
                          value: selectedCostCenterId,
                          decoration:  InputDecoration(
                            labelText: tr('مركز التكلفة (اختياري)'),
                            prefixIcon: const Icon(PhosphorIconsBold.treeStructure),
                          ),
                          items: [
                             DropdownMenuItem<int?>(value: null, child: Text(tr('— بدون —'))),
                            ...ccList.map((cc) => DropdownMenuItem<int?>(value: cc.id, child: Text(cc.name))),
                          ],
                          onChanged: (v) => setDialogState(() => selectedCostCenterId = v),
                        );
                      },
                    );
                  }),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child:  Text(tr('إلغاء')),
            ),
            ElevatedButton.icon(
              onPressed: saving ? null : () async {
                setDialogState(() => saving = true);
                if (nameController.text.isEmpty) {
                  AppToast.show(
                    context,
                    tr('يرجى إدخال الاسم'),
                    type: ToastType.error,
                  );
                  if (context.mounted) setDialogState(() => saving = false);
                  return;
                }

                // BUG-U10/U14: accept Arabic-locale numbers (comma / Arabic digits).
                final openingBalance =
                    NumberUtils.tryParseLocale(openingBalanceController.text) ?? 0;
                final creditLimit =
                    NumberUtils.tryParseLocale(creditLimitController.text) ?? 0;

                // Honour an explicit code if the cashier overrode the
                // auto-suggestion; otherwise pass null and let the DAO
                // auto-generate on save (works for both client & server).
                final enteredCode = codeController.text.trim();
                final partyCode = enteredCode.isEmpty ? null : enteredCode;

                try {
                  // R9 / Feature 010 issue 6: gate must be `isClientMode`
                  // (true for BOTH client AND mirror). The legacy
                  // `NetworkService.instance.isClient` predicate is false
                  // in mirror mode, so mirror admins' parties never reach
                  // HQ. The interceptor short-circuits to null on
                  // server/standalone, so the else branch below still
                  // covers those modes correctly.
                  if (SyncInterceptor.isClientMode) {
                    await ClientWriteInterceptor.createParty(
                      name: nameController.text,
                      code: partyCode,
                      phone: phoneController.text.isEmpty
                          ? null
                          : phoneController.text,
                      isCustomer:
                          selectedType == 'customer' || selectedType == 'both',
                      isSupplier:
                          selectedType == 'supplier' || selectedType == 'both',
                      isDeliveryCompany: selectedType == 'delivery',
                      balance: openingBalance,
                      creditLimit: creditLimit,
                      priceLevel: selectedPriceLevel,
                      groupId: selectedGroupId,
                      branchIds: selectedBranchIds,
                      costCenterId: selectedCostCenterId,
                    );
                  } else {
                    final partiesRepo = ref.read(partiesRepositoryProvider);
                    final isGlobal = selectedBranchIds.isEmpty;
                    await partiesRepo.insertParty(
                      PartiesCompanion.insert(
                        name: nameController.text,
                        code: partyCode != null
                            ? Value(partyCode)
                            : const Value.absent(),
                        phone: Value(phoneController.text.isEmpty
                            ? null
                            : phoneController.text),
                        isCustomer: Value(selectedType == 'customer' ||
                            selectedType == 'both'),
                        isSupplier: Value(selectedType == 'supplier' ||
                            selectedType == 'both'),
                        isDeliveryCompany: Value(selectedType == 'delivery'),
                        isActive: const Value(true),
                        balance: Value(openingBalance),
                        creditLimit: Value(creditLimit),
                        priceLevel: Value(selectedPriceLevel),
                        groupId: selectedGroupId != null
                            ? Value(selectedGroupId)
                            : const Value.absent(),
                        isGlobal: Value(isGlobal),
                        branchIds: !isGlobal
                            ? Value(selectedBranchIds.join(','))
                            : const Value.absent(),
                        costCenterId: selectedCostCenterId != null
                            ? Value(selectedCostCenterId)
                            : const Value.absent(),
                      ),
                    );
                  }
                } catch (e) {
                  // Typical cause: duplicate code (manual override). Show
                  // the cashier an explicit error and leave the dialog
                  // open so they can correct.
                  if (context.mounted) {
                    setDialogState(() => saving = false);
                    AppToast.show(
                      context,
                      tr('فشل حفظ الطرف: {e}', {'e': e}),
                      type: ToastType.error,
                    );
                  }
                  return;
                }

                try {
                  final auth = ref.read(authProvider);
                  final actionKey = (selectedType == 'supplier')
                      ? 'add_supplier'
                      : 'add_customer';
                  final activityLogRepo = ref.read(activityLogRepositoryProvider);
                  await activityLogRepo.logActivity(
                    userId: auth.user?.id,
                    userName: auth.user?.displayName ?? tr('مستخدم'),
                    action: actionKey,
                    entityType: 'party',
                    description:
                        tr('إضافة {p0}: {p1}', {'p0': getTypeArabicName(selectedType), 'p1': nameController.text}),
                  );
                } catch (_) {}

                if (context.mounted) {
                  Navigator.pop(context);
                  AppToast.show(
                    context,
                    tr('تم إضافة {p0} بنجاح', {'p0': getTypeArabicName(selectedType)}),
                    type: ToastType.success,
                  );
                }
              },
              icon: const Icon(PhosphorIconsBold.floppyDisk),
              label:  Text(tr('حفظ')),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Shows the Edit Party dialog.
void showEditPartyDialog(BuildContext context, WidgetRef ref, Party party) {
  final nameController = TextEditingController(text: party.name);
  final phoneController = TextEditingController(text: party.phone ?? '');
  final creditLimitController = TextEditingController(
    text: party.creditLimit.toString(),
  );
  String selectedType = party.isCustomer && party.isSupplier
      ? 'both'
      : party.isCustomer
      ? 'customer'
      : 'supplier';
  String selectedPriceLevel = party.priceLevel;
  int? selectedGroupId = party.groupId;

  // Issue 5: branch assignment + cost center were available when CREATING
  // a party but absent from the EDIT dialog, so an admin could never
  // change a customer's branch scope or move them between cost centers
  // after the fact. Hydrate from the party row so the UI reflects the
  // current state, then write back through the same channels the
  // create dialog uses.
  final List<int> selectedBranchIds = party.isGlobal
      ? <int>[]
      : (party.branchIds ?? '')
          .split(',')
          .map((s) => int.tryParse(s.trim()))
          .whereType<int>()
          .toList();
  int? selectedCostCenterId = party.costCenterId;

  bool saving = false;

  showDialog(
    context: context,
    builder: (context) => Directionality(
      textDirection: TextDirection.rtl,
      child: StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Row(
            children: [
              const Icon(PhosphorIconsBold.pencil, color: AppColors.primary),
              const SizedBox(width: 8),
              Text(tr('تعديل بيانات {p0}', {'p0': party.name})),
            ],
          ),
          content: SizedBox(
            width: 500,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                   Text(
                    tr('نوع الطرف *'),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  SegmentedButton<String>(
                    segments:  [
                      ButtonSegment(
                        value: 'customer',
                        label: Text(tr('عميل')),
                        icon: const Icon(PhosphorIconsBold.user, size: 16),
                      ),
                      ButtonSegment(
                        value: 'supplier',
                        label: Text(tr('مورد')),
                        icon: const Icon(PhosphorIconsBold.truck, size: 16),
                      ),
                      ButtonSegment(
                        value: 'both',
                        label: Text(tr('عميل مورد')),
                        icon: const Icon(PhosphorIconsBold.usersThree, size: 16),
                      ),
                    ],
                    selected: {selectedType},
                    onSelectionChanged: (val) {
                      setDialogState(() => selectedType = val.first);
                    },
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: TextField(
                          controller: nameController,
                          decoration:  InputDecoration(
                            labelText: tr('الاسم *'),
                            prefixIcon: const Icon(PhosphorIconsBold.identificationCard),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 2,
                        // Code is read-only in edit mode to preserve the
                        // link with the Chart-of-Accounts sub-account
                        // created at insert time. Changing it after the
                        // fact would desync the two identifiers.
                        child: TextField(
                          readOnly: true,
                          controller: TextEditingController(
                            text: party.code ?? '—',
                          ),
                          decoration:  InputDecoration(
                            labelText: tr('الكود'),
                            prefixIcon: const Icon(PhosphorIconsBold.hash),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: phoneController,
                    decoration:  InputDecoration(
                      labelText: tr('رقم الهاتف'),
                      prefixIcon: const Icon(PhosphorIconsBold.phone),
                    ),
                    keyboardType: TextInputType.phone,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: creditLimitController,
                    decoration: InputDecoration(
                      labelText: tr('الحد الائتماني'),
                      prefixIcon: const Icon(PhosphorIconsBold.creditCard),
                      suffixText: AppConstants.currencySymbolEn,
                    ),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 12),
                  if (selectedType == 'customer' || selectedType == 'both')
                    DropdownButtonFormField<String>(
                      initialValue: selectedPriceLevel,
                      decoration:  InputDecoration(
                        labelText: tr('تصنيف السعر'),
                        prefixIcon: const Icon(PhosphorIconsBold.tag),
                      ),
                      items: kPriceLevels.entries
                          .map(
                            (e) => DropdownMenuItem(
                              value: e.key,
                              child: Text(e.value),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        setDialogState(
                          () => selectedPriceLevel = value ?? 'default',
                        );
                      },
                    ),
                  const SizedBox(height: 12),
                  // Edit-time group picker — same type-filtering logic as
                  // the Add dialog so the list mirrors the party's role.
                  Consumer(builder: (ctx, ref, _) {
                    final groupsAsync =
                        ref.watch(activePartyGroupsProvider);
                    return groupsAsync.maybeWhen(
                      data: (groups) {
                        final filtered = groups.where((g) {
                          if (g.type == 'both') return true;
                          if (selectedType == 'both') return true;
                          return g.type == selectedType;
                        }).toList();
                        // If the party's current group was filtered out
                        // (role changed, or the group is archived), still
                        // include it so the user can switch intentionally.
                        if (selectedGroupId != null &&
                            !filtered.any(
                                (g) => g.id == selectedGroupId)) {
                          final orphan = groups.firstWhere(
                            (g) => g.id == selectedGroupId,
                            orElse: () => PartyGroup(
                              id: selectedGroupId!,
                              name: tr('مجموعة #{selectedGroupId}', {'selectedGroupId': selectedGroupId}),
                              type: 'both',
                              defaultDiscount: 0,
                              isActive: false,
                              createdAt: DateTime.now(),
                              rowVersion: 0,
                            ),
                          );
                          filtered.insert(0, orphan);
                        }
                        return DropdownButtonFormField<int?>(
                          initialValue: selectedGroupId,
                          decoration:  InputDecoration(
                            labelText: tr('المجموعة'),
                            prefixIcon:
                                const Icon(PhosphorIconsBold.usersThree),
                          ),
                          items: [
                             DropdownMenuItem<int?>(
                              value: null,
                              child: Text(tr('— بدون مجموعة —')),
                            ),
                            ...filtered.map(
                              (g) => DropdownMenuItem<int?>(
                                value: g.id,
                                child: Text(g.name),
                              ),
                            ),
                          ],
                          onChanged: (v) => setDialogState(
                              () => selectedGroupId = v),
                        );
                      },
                      orElse: () => const SizedBox.shrink(),
                    );
                  }),
                  const SizedBox(height: 12),
                  // Branch assignment — same widget the CREATE dialog uses.
                  // Empty selection = global (visible everywhere); a non-
                  // empty list scopes the party to the listed branches.
                  Consumer(builder: (ctx, ref, _) {
                    final branchesAsync = ref.watch(allBranchesProvider);
                    return branchesAsync.maybeWhen(
                      data: (branches) {
                        if (branches.isEmpty) return const SizedBox.shrink();
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                             Text(tr('تحديد الفروع'),
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                            const SizedBox(height: 2),
                             Text(tr('اتركها فارغة لإتاحة الطرف لكل الفروع'),
                                style: const TextStyle(fontSize: 11, color: Colors.grey)),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 6, runSpacing: 4,
                              children: branches.map((b) {
                                final sel = selectedBranchIds.contains(b.id);
                                return FilterChip(
                                  label: Text(b.name, style: const TextStyle(fontSize: 12)),
                                  selected: sel,
                                  onSelected: (v) => setDialogState(() {
                                    if (v) {
                                      selectedBranchIds.add(b.id);
                                    } else {
                                      selectedBranchIds.remove(b.id);
                                    }
                                  }),
                                );
                              }).toList(),
                            ),
                          ],
                        );
                      },
                      orElse: () => const SizedBox.shrink(),
                    );
                  }),
                  const SizedBox(height: 12),
                  // Cost center — mirrors the CREATE dialog. "— بدون —"
                  // option lets the admin clear an inherited assignment
                  // explicitly rather than only being able to switch.
                  Consumer(builder: (ctx, ref, _) {
                    final accountingRepo = ref.watch(accountingRepositoryProvider);
                    return FutureBuilder<List<CostCenter>>(
                      future: accountingRepo.getActiveCostCenters(),
                      builder: (context, snap) {
                        final ccList = snap.data ?? const <CostCenter>[];
                        return DropdownButtonFormField<int?>(
                          value: selectedCostCenterId,
                          decoration:  InputDecoration(
                            labelText: tr('مركز التكلفة (اختياري)'),
                            prefixIcon: const Icon(PhosphorIconsBold.treeStructure),
                          ),
                          items: [
                             DropdownMenuItem<int?>(value: null, child: Text(tr('— بدون —'))),
                            ...ccList.map((cc) => DropdownMenuItem<int?>(value: cc.id, child: Text(cc.name))),
                          ],
                          onChanged: (v) => setDialogState(() => selectedCostCenterId = v),
                        );
                      },
                    );
                  }),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child:  Text(tr('إلغاء')),
            ),
            ElevatedButton.icon(
              onPressed: saving ? null : () async {
                setDialogState(() => saving = true);
                if (nameController.text.isEmpty) {
                  AppToast.show(
                    context,
                    tr('يرجى إدخال الاسم'),
                    type: ToastType.error,
                  );
                  if (context.mounted) setDialogState(() => saving = false);
                  return;
                }

                try {
                  final partiesRepo = ref.read(partiesRepositoryProvider);
                  final isGlobal = selectedBranchIds.isEmpty;
                  final branchIdsCsv =
                      isGlobal ? null : selectedBranchIds.join(',');
                  final updatedParty = party.copyWith(
                    name: nameController.text,
                    phone: Value(
                      phoneController.text.isEmpty
                          ? null
                          : phoneController.text,
                    ),
                    isCustomer:
                        selectedType == 'customer' || selectedType == 'both',
                    isSupplier:
                        selectedType == 'supplier' || selectedType == 'both',
                    creditLimit:
                        double.tryParse(creditLimitController.text) ??
                        party.creditLimit,
                    priceLevel: selectedPriceLevel,
                    groupId: Value(selectedGroupId),
                    isGlobal: isGlobal,
                    branchIds: Value(branchIdsCsv),
                    costCenterId: Value(selectedCostCenterId),
                  );

                  final updated = await ClientWriteInterceptor.updateParty(
                    party.id,
                    {
                      'name': nameController.text,
                      'phone': phoneController.text.isEmpty
                          ? null
                          : phoneController.text,
                      'isCustomer':
                          selectedType == 'customer' || selectedType == 'both',
                      'isSupplier':
                          selectedType == 'supplier' || selectedType == 'both',
                      'creditLimit':
                          double.tryParse(creditLimitController.text) ??
                          party.creditLimit,
                      'priceLevel': selectedPriceLevel,
                      'groupId': selectedGroupId,
                      'isGlobal': isGlobal,
                      'branchIds': branchIdsCsv,
                      'costCenterId': selectedCostCenterId,
                    },
                  );
                  if (!updated) {
                    await partiesRepo.updateParty(updatedParty);
                  }
                } catch (e) {
                  if (context.mounted) {
                    setDialogState(() => saving = false);
                    AppToast.show(
                      context,
                      tr('فشل تحديث البيانات: {e}', {'e': e}),
                      type: ToastType.error,
                    );
                  }
                  return;
                }

                try {
                  final auth = ref.read(authProvider);
                  final actionKey = party.isSupplier
                      ? 'update_supplier'
                      : 'update_customer';
                  final activityLogRepo = ref.read(activityLogRepositoryProvider);
                  await activityLogRepo.logActivity(
                    userId: auth.user?.id,
                    userName: auth.user?.displayName ?? tr('مستخدم'),
                    action: actionKey,
                    entityType: 'party',
                    entityId: party.id,
                    description: tr('تعديل بيانات: {p0}', {'p0': party.name}),
                  );
                } catch (_) {}

                if (context.mounted) {
                  Navigator.pop(context);
                  AppToast.show(
                    context,
                    tr('تم تحديث البيانات بنجاح'),
                    type: ToastType.success,
                  );
                }
              },
              icon: const Icon(PhosphorIconsBold.floppyDisk),
              label:  Text(tr('حفظ')),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Shows the Delete Party confirmation dialog.
void showDeletePartyDialog(BuildContext context, WidgetRef ref, Party party) {
  bool saving = false;

  showDialog(
    context: context,
    builder: (context) => Directionality(
      textDirection: TextDirection.rtl,
      child: StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
        title:  Row(
          children: [
            const Icon(PhosphorIconsBold.warning, color: AppColors.error),
            const SizedBox(width: 8),
            Text(tr('تأكيد الحذف')),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tr('هل أنت متأكد من حذف "{p0}"؟', {'p0': party.name})),
            if (party.balance != 0)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        PhosphorIconsBold.warning,
                        color: AppColors.warning,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          tr('لديه رصيد: {p0} {p1}', {'p0': party.balance.toStringAsFixed(AppConstants.decimalPlaces), 'p1': AppConstants.currencySymbolEn}),
                          style: const TextStyle(color: AppColors.warning),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child:  Text(tr('إلغاء')),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: saving ? null : () async {
              setDialogState(() => saving = true);
              try {
                final partiesRepo = ref.read(partiesRepositoryProvider);
                final deleted = await ClientWriteInterceptor.deleteParty(
                  party.id,
                );
                if (!deleted) {
                  final deactivated = party.copyWith(isActive: false);
                  await partiesRepo.updateParty(deactivated);
                }
              } catch (e) {
                if (context.mounted) {
                  setDialogState(() => saving = false);
                  AppToast.show(
                    context,
                    tr('فشل حذف الطرف: {e}', {'e': e}),
                    type: ToastType.error,
                  );
                }
                return;
              }

              try {
                final auth = ref.read(authProvider);
                final actionKey = party.isSupplier
                    ? 'delete_supplier'
                    : 'delete_customer';
                final activityLogRepo = ref.read(activityLogRepositoryProvider);
                await activityLogRepo.logActivity(
                  userId: auth.user?.id,
                  userName: auth.user?.displayName ?? tr('مستخدم'),
                  action: actionKey,
                  entityType: 'party',
                  entityId: party.id,
                  description: tr('حذف: {p0}', {'p0': party.name}),
                );
              } catch (_) {}

              if (context.mounted) {
                Navigator.pop(context);
                AppToast.show(
                  context,
                  tr('تم إلغاء تفعيل الطرف'),
                  type: ToastType.warning,
                );
              }
            },
            child:  Text(tr('حذف')),
          ),
        ],
        ),
      ),
    ),
  );
}

/// Shows the Excel import/export options dialog.
void showExcelOptionsDialog(
  BuildContext context,
  WidgetRef ref, {
  required bool isExport,
}) {
  showDialog(
    context: context,
    builder: (context) => Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: Row(
          children: [
            Icon(
              isExport
                  ? PhosphorIconsBold.fileArrowUp
                  : PhosphorIconsBold.fileArrowDown,
              color: AppColors.primary,
            ),
            const SizedBox(width: 8),
            Text(isExport ? tr('تصدير قالب Excel') : tr('استيراد من Excel')),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(
                PhosphorIconsBold.user,
                color: AppColors.primary,
              ),
              title:  Text(tr('العملاء')),
              onTap: () {
                Navigator.pop(context);
                if (isExport) {
                  _exportTemplate(context, ref, isSupplier: false);
                } else {
                  _importData(context, ref, isSupplier: false);
                }
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(
                PhosphorIconsBold.truck,
                color: AppColors.warning,
              ),
              title:  Text(tr('الموردين')),
              onTap: () {
                Navigator.pop(context);
                if (isExport) {
                  _exportTemplate(context, ref, isSupplier: true);
                } else {
                  _importData(context, ref, isSupplier: true);
                }
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child:  Text(tr('إلغاء')),
          ),
        ],
      ),
    ),
  );
}

Future<void> _exportTemplate(BuildContext context, WidgetRef ref, {bool isSupplier = false}) async {
  final service = ref.read(excelServiceProvider);
  final path = await service.exportPartiesTemplate(isSupplier);
  if (path != null && context.mounted) {
    AppToast.show(
      context,
      tr('تم تصدير النموذج بنجاح: {path}', {'path': path}),
      type: ToastType.success,
    );
    try {
      final auth = ref.read(authProvider);
      final activityLogRepo = ref.read(activityLogRepositoryProvider);
      await activityLogRepo.logActivity(
        userId: auth.user?.id,
        userName: auth.user?.displayName ?? tr('مستخدم'),
        action: 'export_template',
        entityType: 'party',
        description: tr('تصدير قالب {p0}', {'p0': isSupplier ? "موردين" : "عملاء"}),
      );
    } catch (_) {}
  }
}

Future<void> _importData(BuildContext context, WidgetRef ref, {bool isSupplier = false}) async {
  final service = ref.read(excelServiceProvider);
  final result = await service.importParties(isSupplier);
  if (context.mounted) {
    AppToast.show(
      context,
      result.message,
      type: result.success == true ? ToastType.success : ToastType.error,
    );
    if (result.success) {
      ref.invalidate(allPartiesProvider);
      try {
        final auth = ref.read(authProvider);
        final activityLogRepo = ref.read(activityLogRepositoryProvider);
        await activityLogRepo.logActivity(
          userId: auth.user?.id,
          userName: auth.user?.displayName ?? tr('مستخدم'),
          action: 'import_data',
          entityType: 'party',
          description:
              tr('استيراد بيانات {p0} من Excel', {'p0': isSupplier ? "موردين" : "عملاء"}),
        );
      } catch (_) {}
    }
  }
}