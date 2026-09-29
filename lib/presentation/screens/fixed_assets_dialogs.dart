// =======================================================================
// FIXED ASSETS DIALOGS — Phase 7 God File Splitting
// Extracted from fixed_assets_screen.dart (lines 577-1540)
// =======================================================================
part of 'fixed_assets_screen.dart';

/// Extension on _FixedAssetsScreenState for all dialog/action methods.
/// This keeps the main screen file focused on build/layout logic only.
extension _FixedAssetsDialogs on _FixedAssetsScreenState {
  // ═══════════════════════════════════════════════════════════════════
  // CATEGORY DIALOGS
  // ═══════════════════════════════════════════════════════════════════

  void showCreateCategoryDialog(IFixedAssetsRepository repo, IAccountingRepository accountingRepo) {
    final nameCtrl = TextEditingController();
    final usefulLifeCtrl = TextEditingController();
    double usefulLife = 0;
    String method = 'straight_line';
    Account? selectedAssetAccount;
    Account? selectedDeprecAccount;
    bool saving = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(tr('فئة أصول جديدة'),
              style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameCtrl,
                    decoration: InputDecoration(
                      labelText: tr('اسم الفئة *'),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8)),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: tr('العمر الافتراضي (سنوات) — اختياري'),
                      hintText: tr('اتركه فارغاً إذا غير محدد'),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8)),
                      isDense: true,
                    ),
                    controller: usefulLifeCtrl,
                    onChanged: (v) =>
                        usefulLife = double.tryParse(v) ?? 0,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: method,
                    decoration: InputDecoration(
                      labelText: tr('طريقة الإهلاك'),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8)),
                      isDense: true,
                    ),
                    items:  [
                      DropdownMenuItem(
                          value: 'straight_line', child: Text(tr('القسط الثابت'))),
                      DropdownMenuItem(
                          value: 'declining_balance',
                          child: Text(tr('القسط المتناقص'))),
                    ],
                    onChanged: (v) =>
                        setDialogState(() => method = v ?? 'straight_line'),
                  ),
                  const SizedBox(height: 12),
                  FutureBuilder<List<Account>>(
                    future: accountingRepo.getAllAccounts().then((all) {
                      final parentIds = all.where((a) => a.parentId != null).map((a) => a.parentId!).toSet();
                      return all.where((a) => !parentIds.contains(a.id) && !a.isHiddenFromEntries).toList();
                    }),
                    builder: (ctx, snap) {
                      final accs = snap.data ?? [];
                      return Column(
                        children: [
                          Autocomplete<Account>(
                            optionsBuilder: (tv) {
                              if (tv.text.isEmpty) return accs.where((a) => a.code.startsWith('12')).take(20);
                              final q = tv.text.toLowerCase();
                              return accs.where((a) => a.name.toLowerCase().contains(q) || a.code.contains(q));
                            },
                            displayStringForOption: (a) => '${a.code} - ${a.name}',
                            fieldViewBuilder: (ctx, ctrl, fn, _) => TextField(
                              controller: ctrl,
                              focusNode: fn,
                              decoration: InputDecoration(
                                labelText: tr('حساب الأصل (قيد الاقتناء)'),
                                hintText: tr('ابحث: مركبات، آلات...'),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                isDense: true,
                              ),
                            ),
                            onSelected: (a) => setDialogState(() => selectedAssetAccount = a),
                          ),
                          if (selectedAssetAccount != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text('✓ ${selectedAssetAccount!.code} - ${selectedAssetAccount!.name}',
                                  style: const TextStyle(fontSize: 11, color: AppColors.success)),
                            )
                          else
                            // Feature 050: inline hint instead of throwing
                            // MissingCategoryAccountException at end of long
                            // asset-creation form. Save is gated on these
                            // selections being present (see button below).
                             Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                tr('اختر حساب الأصل من دليل الحسابات.'),
                                style: const TextStyle(
                                    fontSize: 11, color: AppColors.error),
                              ),
                            ),
                          const SizedBox(height: 12),
                          Autocomplete<Account>(
                            optionsBuilder: (tv) {
                              if (tv.text.isEmpty) return accs.where((a) => a.code.startsWith('12')).take(20);
                              final q = tv.text.toLowerCase();
                              return accs.where((a) => a.name.toLowerCase().contains(q) || a.code.contains(q));
                            },
                            displayStringForOption: (a) => '${a.code} - ${a.name}',
                            fieldViewBuilder: (ctx, ctrl, fn, _) => TextField(
                              controller: ctrl,
                              focusNode: fn,
                              decoration: InputDecoration(
                                labelText: tr('حساب مجمع الإهلاك'),
                                hintText: tr('ابحث: مجمع إهلاك...'),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                isDense: true,
                              ),
                            ),
                            onSelected: (a) => setDialogState(() => selectedDeprecAccount = a),
                          ),
                          if (selectedDeprecAccount != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text('✓ ${selectedDeprecAccount!.code} - ${selectedDeprecAccount!.name}',
                                  style: const TextStyle(fontSize: 11, color: AppColors.success)),
                            )
                          else
                             Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                tr('اختر حساب مجمع الإهلاك من دليل الحسابات.'),
                                style: const TextStyle(
                                    fontSize: 11, color: AppColors.error),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child:  Text(tr('إلغاء')),
            ),
            ElevatedButton(
              // Feature 050: gate save on both account selections. The name
              // check stays inside onPressed (toast on empty) — the name
              // field doesn't trigger setDialogState rebuilds, so wiring
              // it into the gate would leave the button stuck disabled
              // even after typing. The DAO also rejects null accountId /
              // depreciationAccountId as defense-in-depth.
              onPressed: (saving ||
                      selectedAssetAccount == null ||
                      selectedDeprecAccount == null)
                  ? null
                  : () async {
                if (nameCtrl.text.trim().isEmpty) {
                  AppToast.show(ctx, tr('الرجاء إدخال اسم الفئة'));
                  return;
                }
                setDialogState(() => saving = true);
                try {
                  await repo.createAssetCategory(
                    name: nameCtrl.text.trim(),
                    defaultUsefulLife: usefulLife,
                    defaultDepreciationMethod: method,
                    accountId: selectedAssetAccount?.id,
                    depreciationAccountId: selectedDeprecAccount?.id,
                  );
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (mounted) {
                    AppToast.show(context, tr('تمت إضافة الفئة'),
                        type: ToastType.success);
                  }
                } catch (e) {
                  if (ctx.mounted) setDialogState(() => saving = false);
                  if (!ctx.mounted) return;
                  AppToast.show(ctx, tr('خطأ: {e}', {'e': e}), type: ToastType.error);
                }
              },
              child:  Text(tr('حفظ')),
            ),
          ],
        ),
      ),
    );
  }

  // Returns a Future so callers (Feature 050: the "ربط حساب الآن" button
  // in showCreateAssetDialog) can `await` the edit before refreshing
  // their own state. The existing void caller in fixed_assets_screen.dart
  // ignores the result, which is fine — Dart's implicit-await rules allow
  // dropping the Future.
  Future<void> showEditCategoryDialog(IFixedAssetsRepository repo, IAccountingRepository accountingRepo, AssetCategory cat) async {
    final nameCtrl = TextEditingController(text: cat.name);
    final usefulLifeCtrl =
        TextEditingController(text: cat.defaultUsefulLife.toString());
    // Feature 052 (v132): pre-resolve the current asset + deprec accounts
    // so the Autocomplete fields open already populated. Previously the
    // dialog appeared blank-ish and the user read it as "edit isn't
    // working" — they had no way to see the category's existing GL
    // linkage without leaving the dialog and going to the accounts
    // screen. We do the lookups once before showDialog so the dialog
    // renders synchronously with the resolved labels.
    final currentAssetAccount = cat.accountId != null
        ? await accountingRepo.getAccountById(cat.accountId!)
        : null;
    final currentDeprecAccount = cat.depreciationAccountId != null
        ? await accountingRepo.getAccountById(cat.depreciationAccountId!)
        : null;
    if (!mounted) return;
    Account? selectedAssetAccount = currentAssetAccount;
    Account? selectedDeprecAccount = currentDeprecAccount;
    String method = cat.defaultDepreciationMethod;
    bool saving = false;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(tr('تعديل الفئة — {p0}', {'p0': cat.name}),
              style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameCtrl,
                    decoration: InputDecoration(
                      labelText: tr('اسم الفئة'),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Feature 052: useful life + depreciation method are
                  // safe to edit. They only seed defaults for newly-created
                  // assets under this category; past assets keep whatever
                  // values they were created with.
                  TextField(
                    controller: usefulLifeCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: tr('العمر الافتراضي (سنوات) — اختياري'),
                      hintText: tr('اتركه فارغاً إذا غير محدد'),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: method,
                    decoration: InputDecoration(
                      labelText: tr('طريقة الإهلاك'),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      isDense: true,
                    ),
                    items:  [
                      DropdownMenuItem(
                          value: 'straight_line', child: Text(tr('القسط الثابت'))),
                      DropdownMenuItem(
                          value: 'declining_balance',
                          child: Text(tr('القسط المتناقص'))),
                    ],
                    onChanged: (v) =>
                        setDialogState(() => method = v ?? 'straight_line'),
                  ),
                  const SizedBox(height: 12),
                  FutureBuilder<List<Account>>(
                    future: accountingRepo.getAllAccounts().then((all) {
                      final parentIds = all.where((a) => a.parentId != null).map((a) => a.parentId!).toSet();
                      return all.where((a) => !parentIds.contains(a.id) && !a.isHiddenFromEntries).toList();
                    }),
                    builder: (ctx, snap) {
                      final accs = snap.data ?? [];
                      return Column(
                        children: [
                          Autocomplete<Account>(
                            // Feature 052: Autocomplete now opens with the
                            // category's existing asset account already
                            // displayed. Previous behavior left the field
                            // blank with the hint "اتركه فارغاً للإبقاء
                            // على الحالي", which the user reasonably read
                            // as "the dialog isn't loading my data".
                            initialValue: currentAssetAccount != null
                                ? TextEditingValue(
                                    text:
                                        '${currentAssetAccount.code} - ${currentAssetAccount.name}',
                                  )
                                : const TextEditingValue(),
                            optionsBuilder: (tv) {
                              if (tv.text.isEmpty) return accs.where((a) => a.code.startsWith('12')).take(20);
                              final q = tv.text.toLowerCase();
                              return accs.where((a) => a.name.toLowerCase().contains(q) || a.code.contains(q));
                            },
                            displayStringForOption: (a) => '${a.code} - ${a.name}',
                            fieldViewBuilder: (ctx, ctrl, fn, _) => TextField(
                              controller: ctrl,
                              focusNode: fn,
                              decoration: InputDecoration(
                                labelText: tr('حساب الأصل'),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                isDense: true,
                              ),
                            ),
                            onSelected: (a) => setDialogState(() => selectedAssetAccount = a),
                          ),
                          if (selectedAssetAccount != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text('✓ ${selectedAssetAccount!.code} - ${selectedAssetAccount!.name}',
                                  style: const TextStyle(fontSize: 11, color: AppColors.success)),
                            ),
                          const SizedBox(height: 12),
                          Autocomplete<Account>(
                            initialValue: currentDeprecAccount != null
                                ? TextEditingValue(
                                    text:
                                        '${currentDeprecAccount.code} - ${currentDeprecAccount.name}',
                                  )
                                : const TextEditingValue(),
                            optionsBuilder: (tv) {
                              if (tv.text.isEmpty) return accs.where((a) => a.code.startsWith('12')).take(20);
                              final q = tv.text.toLowerCase();
                              return accs.where((a) => a.name.toLowerCase().contains(q) || a.code.contains(q));
                            },
                            displayStringForOption: (a) => '${a.code} - ${a.name}',
                            fieldViewBuilder: (ctx, ctrl, fn, _) => TextField(
                              controller: ctrl,
                              focusNode: fn,
                              decoration: InputDecoration(
                                labelText: tr('حساب مجمع الإهلاك'),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                isDense: true,
                              ),
                            ),
                            onSelected: (a) => setDialogState(() => selectedDeprecAccount = a),
                          ),
                          if (selectedDeprecAccount != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text('✓ ${selectedDeprecAccount!.code} - ${selectedDeprecAccount!.name}',
                                  style: const TextStyle(fontSize: 11, color: AppColors.success)),
                            ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child:  Text(tr('إلغاء'))),
            ElevatedButton(
              onPressed: saving ? null : () async {
                setDialogState(() => saving = true);
                try {
                  await repo.updateAssetCategoryById(
                    cat.id,
                    name: nameCtrl.text.trim(),
                    accountId: selectedAssetAccount?.id,
                    depreciationAccountId: selectedDeprecAccount?.id,
                    defaultUsefulLife:
                        double.tryParse(usefulLifeCtrl.text.trim()),
                    defaultDepreciationMethod: method,
                  );
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (mounted) {
                    AppToast.show(context, tr('تم التعديل'), type: ToastType.success);
                  }
                } catch (e) {
                  if (ctx.mounted) setDialogState(() => saving = false);
                  if (!ctx.mounted) return;
                  AppToast.show(ctx, tr('خطأ: {e}', {'e': e}), type: ToastType.error);
                }
              },
              child:  Text(tr('حفظ')),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // ASSET DIALOGS
  // ═══════════════════════════════════════════════════════════════════

  void showCreateAssetDialog(IFixedAssetsRepository repo, IAccountingRepository accountingRepo) {
    final codeCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    final priceCtrl = TextEditingController();
    final lifetimeCtrl = TextEditingController(text: '5');
    final salvageCtrl = TextEditingController(text: '0');
    final locationCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    int? selectedCategoryId;
    int? selectedCostCenterId;
    Account? selectedAccount; // Item 8: COA selector
    DateTime purchaseDate = DateTime.now();
    String method = 'straight_line';
    bool saving = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(tr('أصل ثابت جديد'),
              style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
          content: SizedBox(
            width: 450,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      SizedBox(
                        width: 120,
                        child: TextField(
                          controller: codeCtrl,
                          decoration: InputDecoration(
                            labelText: tr('الكود *'),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8)),
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: nameCtrl,
                          decoration: InputDecoration(
                            labelText: tr('اسم الأصل *'),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8)),
                            isDense: true,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  FutureBuilder<List<AssetCategory>>(
                    future: repo.getAssetCategoriesList(),
                    builder: (ctx, snap) {
                      final allCats = snap.data ?? [];
                      // Feature 050: only categories with both GL links can
                      // back a fixed-asset creation — `createFixedAsset`
                      // throws MissingCategoryAccountException for the
                      // others (fixed_assets_dao_ext.dart:128). Hide them
                      // from the dropdown rather than letting the user
                      // fill the whole form and lose it on a final throw.
                      final validCats = allCats
                          .where((c) => c.accountId != null)
                          .toList();
                      final orphanCats = allCats
                          .where((c) => c.accountId == null)
                          .toList();
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          DropdownButtonFormField<int>(
                            decoration: InputDecoration(
                              labelText: tr('الفئة *'),
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8)),
                              isDense: true,
                            ),
                            items: validCats
                                .map((c) => DropdownMenuItem(
                                    value: c.id, child: Text(c.name)))
                                .toList(),
                            onChanged: (v) {
                              setDialogState(() => selectedCategoryId = v);
                              if (v != null) {
                                final cat =
                                    validCats.firstWhere((c) => c.id == v);
                                lifetimeCtrl.text =
                                    cat.defaultUsefulLife.toString();
                                method = cat.defaultDepreciationMethod;
                              }
                            },
                          ),
                          if (orphanCats.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      tr('يوجد {p0} فئة بدون حسابات مرتبطة — اربط حساب الأصل وحساب مجمع الإهلاك لتظهر فى القائمة.', {'p0': orphanCats.length}),
                                      style: const TextStyle(
                                          fontSize: 11,
                                          color: AppColors.warning),
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: () async {
                                      await showEditCategoryDialog(
                                          repo,
                                          accountingRepo,
                                          orphanCats.first);
                                      // FutureBuilder re-fetches on
                                      // rebuild (its `future:` argument is
                                      // a fresh call each pass), so a
                                      // setDialogState is enough to pick
                                      // up the now-linked category.
                                      setDialogState(() {});
                                    },
                                    child:  Text(tr('ربط حساب الآن')),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: priceCtrl,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: tr('سعر الشراء *'),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8)),
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: InkWell(
                          onTap: () async {
                            final d = await showDatePicker(
                              context: ctx,
                              initialDate: purchaseDate,
                              firstDate: DateTime(2010),
                              lastDate: DateTime(2030),
                            );
                            if (d != null) {
                              setDialogState(() => purchaseDate = d);
                            }
                          },
                          child: InputDecorator(
                            decoration: InputDecoration(
                              labelText: tr('تاريخ الشراء'),
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8)),
                              isDense: true,
                            ),
                            child: Text(_dateFormat.format(purchaseDate)),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: lifetimeCtrl,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: tr('العمر (سنوات) *'),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8)),
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: salvageCtrl,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: tr('قيمة النفاية'),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8)),
                            isDense: true,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: method,
                    decoration: InputDecoration(
                      labelText: tr('طريقة الإهلاك'),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8)),
                      isDense: true,
                    ),
                    items:  [
                      DropdownMenuItem(
                          value: 'straight_line',
                          child: Text(tr('القسط الثابت'))),
                      DropdownMenuItem(
                          value: 'declining_balance',
                          child: Text(tr('القسط المتناقص'))),
                    ],
                    onChanged: (v) =>
                        setDialogState(() => method = v ?? 'straight_line'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: locationCtrl,
                    decoration: InputDecoration(
                      labelText: tr('الموقع'),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8)),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: notesCtrl,
                    maxLines: 2,
                    decoration: InputDecoration(
                      labelText: tr('ملاحظات'),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8)),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  FutureBuilder<List<CostCenter>>(
                    future: accountingRepo.getActiveCostCenters(),
                    builder: (ctx, snap) {
                      final centers = snap.data ?? [];
                      if (centers.isEmpty) return const SizedBox.shrink();
                      return DropdownButtonFormField<int?>(
                        initialValue: selectedCostCenterId,
                        decoration: InputDecoration(
                          labelText: tr('مركز التكلفة'),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          isDense: true,
                          prefixIcon: const Icon(PhosphorIconsBold.target),
                        ),
                        items: [
                           DropdownMenuItem<int?>(value: null, child: Text(tr('بدون'))),
                          ...centers.map((c) => DropdownMenuItem<int?>(value: c.id, child: Text(c.name))),
                        ],
                        onChanged: (v) => setDialogState(() => selectedCostCenterId = v),
                      );
                    },
                  ),
                  // حساب الدفع عند الاقتناء: الطرف الدائن في قيد الشراء
                  // (ليس حساب الإهلاك — الإهلاك يُعيَّن على مستوى الفئة)
                  const SizedBox(height: 12),
                  FutureBuilder<List<Account>>(
                    future: accountingRepo.getAllAccounts().then((all) {
                      final parentIds = all.where((a) => a.parentId != null).map((a) => a.parentId!).toSet();
                      return all.where((a) => !parentIds.contains(a.id) && !a.isHiddenFromEntries).toList();
                    }),
                    builder: (ctx, snap) {
                      final accounts = snap.data ?? [];
                      if (accounts.isEmpty) return const SizedBox.shrink();
                      return Autocomplete<Account>(
                        optionsBuilder: (textValue) {
                          if (textValue.text.isEmpty) return accounts.take(20);
                          final q = textValue.text.toLowerCase();
                          return accounts.where((a) =>
                              a.name.toLowerCase().contains(q) ||
                              a.code.toLowerCase().contains(q));
                        },
                        displayStringForOption: (a) => '${a.code} - ${a.name}',
                        fieldViewBuilder: (ctx, controller, focusNode, onSubmitted) {
                          return TextField(
                            controller: controller,
                            focusNode: focusNode,
                            decoration: InputDecoration(
                              labelText: tr('حساب الدفع عند الاقتناء (الطرف الدائن)'),
                              hintText: tr('ابحث بالاسم أو الرمز...'),
                              prefixIcon: const Icon(PhosphorIconsBold.magnifyingGlass, size: 18),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                              isDense: true,
                            ),
                          );
                        },
                        onSelected: (a) => setDialogState(() => selectedAccount = a),
                      );
                    },
                  ),
                  if (selectedAccount != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Row(
                        children: [
                          const Icon(PhosphorIconsBold.checkCircle, size: 14, color: AppColors.success),
                          const SizedBox(width: 4),
                          Text('${selectedAccount!.code} - ${selectedAccount!.name}',
                              style: const TextStyle(fontSize: 11, color: AppColors.success)),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child:  Text(tr('إلغاء')),
            ),
            ElevatedButton.icon(
              icon: const Icon(PhosphorIconsBold.floppyDisk, size: 16),
              label:  Text(tr('حفظ')),
              onPressed: saving ? null : () async {
                if (codeCtrl.text.isEmpty ||
                    nameCtrl.text.isEmpty ||
                    priceCtrl.text.isEmpty ||
                    selectedCategoryId == null) {
                  AppToast.show(ctx, tr('الرجاء تعبئة الحقول المطلوبة'));
                  return;
                }

                final price = double.tryParse(priceCtrl.text);
                final lifetime = double.tryParse(lifetimeCtrl.text);
                if (price == null || price <= 0 || lifetime == null || lifetime <= 0) {
                  AppToast.show(ctx, tr('الرجاء إدخال قيم صحيحة'));
                  return;
                }

                setDialogState(() => saving = true);
                try {
                  await repo.createFixedAsset(
                    code: codeCtrl.text.trim(),
                    name: nameCtrl.text.trim(),
                    categoryId: selectedCategoryId!,
                    purchasePrice: price,
                    purchaseDate: purchaseDate,
                    usefulLifeYears: lifetime,
                    salvageValue:
                        double.tryParse(salvageCtrl.text) ?? 0,
                    depreciationMethod: method,
                    location: locationCtrl.text.isNotEmpty
                        ? locationCtrl.text
                        : null,
                    notes: notesCtrl.text.isNotEmpty
                        ? notesCtrl.text
                        : null,
                    costCenterId: selectedCostCenterId,
                    contraAccountId: selectedAccount?.id,
                  );
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (mounted) {
                    AppToast.show(context, tr('تمت إضافة الأصل'),
                        type: ToastType.success);
                  }
                } catch (e) {
                  if (ctx.mounted) setDialogState(() => saving = false);
                  if (!ctx.mounted) return;
                  AppToast.show(ctx, tr('خطأ: {e}', {'e': e}), type: ToastType.error);
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> showEditAssetDialog(IFixedAssetsRepository repo, IAccountingRepository accountingRepo, FixedAssetData asset) async {
    final nameCtrl = TextEditingController(text: asset.name);
    final locationCtrl = TextEditingController(text: asset.location ?? '');
    final salvageCtrl = TextEditingController(text: asset.salvageValue.toStringAsFixed(AppConstants.decimalPlaces));
    final notesCtrl = TextEditingController(text: asset.notes ?? '');
    int? selectedCostCenterId = asset.costCenterId;
    bool saving = false;

    // Feature 052 (v132): read-only display section needs the category
    // name and the linked GL sub-account label. Pre-resolve once before
    // building the dialog so they render synchronously.
    final categories = await repo.getAssetCategoriesList();
    final categoryName = categories
        .where((c) => c.id == asset.categoryId)
        .map((c) => c.name)
        .firstOrNull;
    final linkedAccount = asset.linkedAccountId != null
        ? await accountingRepo.getAccountById(asset.linkedAccountId!)
        : null;
    if (!mounted) return;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(tr('تعديل أصل — {p0}', {'p0': asset.name}), style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── Read-only: acquisition data (immutable) ──
                  //
                  // Feature 052: surfaced because users were confused that
                  // the edit dialog had far fewer fields than the create
                  // dialog ("شاشة التعديل غير شاشة الانشاء"). These fields
                  // CANNOT be edited in place — see spec.md §"Why not allow
                  // editing the 7 immutable asset fields?" — but they
                  // should be visible so the operator can verify the
                  // record they're touching.
                  _ImmutableFieldRow(label: tr('الكود'), value: asset.code),
                  _ImmutableFieldRow(
                      label: tr('الفئة'), value: categoryName ?? '—'),
                  _ImmutableFieldRow(
                      label: tr('سعر الشراء'),
                      value: asset.purchasePrice.toStringAsFixed(
                          AppConstants.decimalPlaces)),
                  _ImmutableFieldRow(
                      label: tr('تاريخ الشراء'),
                      value: _dateFormat.format(asset.purchaseDate)),
                  _ImmutableFieldRow(
                      label: tr('العمر الافتراضي'),
                      value: tr('{p0} سنة', {'p0': asset.usefulLifeYears})),
                  _ImmutableFieldRow(
                      label: tr('طريقة الإهلاك'),
                      value: getDepreciationMethodLabel(
                          asset.depreciationMethod)),
                  if (linkedAccount != null)
                    _ImmutableFieldRow(
                        label: tr('الحساب المربوط'),
                        value:
                            '${linkedAccount.code} - ${linkedAccount.name}'),
                   Padding(
                    padding: const EdgeInsets.only(top: 4, bottom: 8),
                    child: Text(
                      tr('الحقول أعلاه غير قابلة للتعديل — تغيير القيمة أو التاريخ بعد الإنشاء يتطلب إنشاء قيد عكسي عبر المحاسب.'),
                      style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.warning,
                          fontStyle: FontStyle.italic),
                    ),
                  ),
                  const Divider(),
                  const SizedBox(height: 4),
                  TextField(
                    controller: nameCtrl,
                    decoration: InputDecoration(
                      labelText: tr('اسم الأصل'),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      isDense: true,
                    ),
                  ),
                const SizedBox(height: 12),
                TextField(
                  controller: locationCtrl,
                  decoration: InputDecoration(
                    labelText: tr('الموقع'),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: salvageCtrl,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: tr('قيمة الخردة'),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: notesCtrl,
                  maxLines: 2,
                  decoration: InputDecoration(
                    labelText: tr('ملاحظات'),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 12),
                  FutureBuilder<List<CostCenter>>(
                    future: accountingRepo.getActiveCostCenters(),
                    builder: (ctx2, snap) {
                      final centers = snap.data ?? [];
                      if (centers.isEmpty) return const SizedBox.shrink();
                      final ids = centers.map((c) => c.id).toSet();
                      final safeVal = ids.contains(selectedCostCenterId) ? selectedCostCenterId : null;
                      return DropdownButtonFormField<int?>(
                        initialValue: safeVal,
                        decoration: InputDecoration(
                          labelText: tr('مركز التكلفة'),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          isDense: true,
                          prefixIcon: const Icon(PhosphorIconsBold.target),
                        ),
                        items: [
                           DropdownMenuItem<int?>(value: null, child: Text(tr('بدون'))),
                          ...centers.map((c) => DropdownMenuItem<int?>(value: c.id, child: Text(c.name))),
                        ],
                        onChanged: (v) => setDialogState(() => selectedCostCenterId = v),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child:  Text(tr('إلغاء'))),
            ElevatedButton(
              onPressed: saving ? null : () async {
                setDialogState(() => saving = true);
                try {
                  await repo.updateFixedAsset(
                    asset.id,
                    name: nameCtrl.text.isNotEmpty ? nameCtrl.text : null,
                    location: locationCtrl.text.isNotEmpty ? locationCtrl.text : null,
                    salvageValue: double.tryParse(salvageCtrl.text),
                    notes: notesCtrl.text.isNotEmpty ? notesCtrl.text : null,
                    costCenterId: selectedCostCenterId,
                    clearCostCenter: selectedCostCenterId == null,
                  );
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (mounted) AppToast.show(context, tr('تم تعديل الأصل'), type: ToastType.success);
                } catch (e) {
                  if (ctx.mounted) setDialogState(() => saving = false);
                  if (mounted) AppToast.show(context, tr('خطأ: {e}', {'e': e}), type: ToastType.error);
                }
              },
              child:  Text(tr('حفظ')),
            ),
          ],
        ),
      ),
    );
  }

  void showRevalueDialog(IFixedAssetsRepository repo, FixedAssetData asset) {
    final bookValue = asset.purchasePrice - asset.accumulatedDepreciation;
    final fairValueCtrl = TextEditingController(text: bookValue.toStringAsFixed(AppConstants.decimalPlaces));
    bool saving = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(tr('إعادة تقييم — {p0}', {'p0': asset.name}), style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                tr('القيمة الدفترية الحالية: {p0}', {'p0': _currencyFormat.format(bookValue)}),
                style: GoogleFonts.cairo(fontWeight: FontWeight.w600, color: Colors.blue),
              ),
              const SizedBox(height: 4),
              Text(
                tr('IAS 16.31 — نموذج إعادة التقييم'),
                style: GoogleFonts.cairo(fontSize: 10, color: Colors.grey),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: fairValueCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: tr('القيمة العادلة الجديدة *'),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  isDense: true,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child:  Text(tr('إلغاء'))),
            ElevatedButton(
              onPressed: saving ? null : () async {
                final fairValue = double.tryParse(fairValueCtrl.text);
                if (fairValue == null || fairValue <= 0) {
                  AppToast.show(ctx, tr('الرجاء إدخال قيمة صحيحة'));
                  return;
                }
                setDialogState(() => saving = true);
                try {
                  await repo.revalueAsset(asset.id, newFairValue: fairValue);
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (mounted) AppToast.show(context, tr('تم إعادة تقييم الأصل'), type: ToastType.success);
                } catch (e) {
                  if (ctx.mounted) setDialogState(() => saving = false);
                  if (mounted) AppToast.show(context, tr('خطأ: {e}', {'e': e}), type: ToastType.error);
                }
              },
              child:  Text(tr('تأكيد التقييم')),
            ),
          ],
        ),
      ),
    );
  }

  void showDisposeDialog(IFixedAssetsRepository repo, FixedAssetData asset) {
    final valueCtrl = TextEditingController();
    DateTime disposalDate = DateTime.now();
    bool saving = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(tr('استبعاد الأصل'),
              style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                tr('استبعاد "{p0}" ({p1})', {'p0': asset.name, 'p1': asset.code}),
                style: GoogleFonts.cairo(fontSize: 13),
              ),
              const SizedBox(height: 12),
              Text(
                tr('القيمة الدفترية الحالية: {p0}', {'p0': _currencyFormat.format(asset.purchasePrice - asset.accumulatedDepreciation)}),
                style: GoogleFonts.cairo(
                    fontSize: 12, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: valueCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: tr('قيمة البيع / التخريد'),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8)),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              InkWell(
                onTap: () async {
                  final d = await showDatePicker(
                    context: ctx,
                    initialDate: disposalDate,
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2030),
                  );
                  if (d != null) setDialogState(() => disposalDate = d);
                },
                child: InputDecorator(
                  decoration: InputDecoration(
                    labelText: tr('تاريخ الاستبعاد'),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8)),
                    isDense: true,
                  ),
                  child: Text(_dateFormat.format(disposalDate)),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child:  Text(tr('إلغاء'))),
            ElevatedButton(
              style:
                  ElevatedButton.styleFrom(backgroundColor: AppColors.error),
              onPressed: saving ? null : () async {
                setDialogState(() => saving = true);
                try {
                  final disposalValue =
                      double.tryParse(valueCtrl.text) ?? 0;
                  await repo.disposeAsset(
                    asset.id,
                    disposalValue: disposalValue,
                    disposalDate: disposalDate,
                  );
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (mounted) {
                    AppToast.show(context, tr('تم استبعاد الأصل'),
                        type: ToastType.success);
                  }
                } catch (e) {
                  if (ctx.mounted) setDialogState(() => saving = false);
                  if (!ctx.mounted) return;
                  AppToast.show(ctx, tr('خطأ: {e}', {'e': e}), type: ToastType.error);
                }
              },
              child:  Text(tr('تأكيد الاستبعاد')),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // DETAIL & HISTORY DIALOGS
  // ═══════════════════════════════════════════════════════════════════

  void showAssetDetails(FixedAssetData asset) {
    final bookValue = asset.purchasePrice - asset.accumulatedDepreciation;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(PhosphorIconsBold.buildings, color: AppColors.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text('${asset.code} - ${asset.name}',
                  style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
            ),
          ],
        ),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _detailRowWidget(tr('الحالة'), getAssetStatusInfo(asset.status).label),
              _detailRowWidget(tr('تكلفة الشراء'), _currencyFormat.format(asset.purchasePrice)),
              _detailRowWidget(tr('الإهلاك المتراكم'),
                  _currencyFormat.format(asset.accumulatedDepreciation)),
              _detailRowWidget(tr('القيمة الدفترية'), _currencyFormat.format(bookValue)),
              _detailRowWidget(tr('تاريخ الشراء'), _dateFormat.format(asset.purchaseDate)),
              _detailRowWidget(tr('العمر الافتراضي'), tr('{p0} سنة', {'p0': asset.usefulLifeYears})),
              _detailRowWidget(tr('قيمة النفاية'), _currencyFormat.format(asset.salvageValue)),
              _detailRowWidget(tr('طريقة الإهلاك'),
                  getDepreciationMethodLabel(asset.depreciationMethod)),
              if (asset.location != null)
                _detailRowWidget(tr('الموقع'), asset.location!),
              if (asset.notes != null)
                _detailRowWidget(tr('ملاحظات'), asset.notes!),
              if (asset.disposalDate != null)
                _detailRowWidget(tr('تاريخ الاستبعاد'),
                    _dateFormat.format(asset.disposalDate!)),
              if (asset.disposalValue != null)
                _detailRowWidget(tr('قيمة الاستبعاد'),
                    _currencyFormat.format(asset.disposalValue!)),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child:  Text(tr('إغلاق')),
          ),
        ],
      ),
    );
  }

  Widget _detailRowWidget(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(label,
                style: GoogleFonts.cairo(
                    fontSize: 12, color: Colors.grey.shade600)),
          ),
          Expanded(
            child: Text(value,
                style: GoogleFonts.cairo(
                    fontSize: 12, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  void showDepreciationHistory(IFixedAssetsRepository repo, FixedAssetData asset) async {
    final history = await repo.getAssetDepreciationSchedule(asset.id);
    if (!mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('سجل إهلاك: {p0}', {'p0': asset.name}),
            style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
        content: SizedBox(
          width: 400,
          height: 300,
          child: history.isEmpty
              ? Center(
                  child: Text(tr('لا يوجد سجل'),
                      style: GoogleFonts.cairo(color: Colors.grey)))
              : ListView.builder(
                  itemCount: history.length,
                  itemBuilder: (ctx, i) {
                    final e = history[i];
                    return ListTile(
                      dense: true,
                      title: Text(
                        '${_dateFormat.format(e.periodDate)} | -${_currencyFormat.format(e.depreciationAmount)}',
                        style: GoogleFonts.cairo(fontSize: 12),
                      ),
                      subtitle: Text(
                        tr('متراكم: {p0} | دفتري: {p1}', {'p0': _currencyFormat.format(e.accumulatedDepreciation), 'p1': _currencyFormat.format(e.bookValue)}),
                        style: GoogleFonts.cairo(
                            fontSize: 10, color: Colors.grey),
                      ),
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
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // DEPRECIATION & SUMMARY ACTIONS
  // ═══════════════════════════════════════════════════════════════════

  Future<void> runDepreciation(IFixedAssetsRepository repo) async {
    DateTime selectedDate = DateTime.now();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(tr('تنفيذ الإهلاك الشهري'),
              style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                tr('اختر فترة الإهلاك ثم اضغط تنفيذ لاحتساب الإهلاك لجميع الأصول الثابتة النشطة.'),
                style: GoogleFonts.cairo(fontSize: 13),
              ),
              const SizedBox(height: 16),
              InkWell(
                onTap: () async {
                  final d = await showDatePicker(
                    context: ctx,
                    initialDate: selectedDate,
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now(),
                  );
                  if (d != null) setDialogState(() => selectedDate = d);
                },
                child: InputDecorator(
                  decoration: InputDecoration(
                    labelText: tr('فترة الإهلاك (الشهر/السنة)'),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    prefixIcon: const Icon(PhosphorIconsBold.calendarBlank),
                    isDense: true,
                  ),
                  child: Text(
                    '${selectedDate.month}/${selectedDate.year}',
                    style: GoogleFonts.cairo(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child:  Text(tr('إلغاء'))),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child:  Text(tr('تنفيذ')),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true) {
      try {
        final depDate = DateTime(selectedDate.year, selectedDate.month, 1);
        final count = await repo.runMonthlyDepreciation(depDate);
        if (mounted) {
          AppToast.show(
            context,
            count > 0
                ? tr('تم احتساب الإهلاك لـ {count} أصل لشهر {p0}/{p1}', {'count': count, 'p0': selectedDate.month, 'p1': selectedDate.year})
                : tr('لا توجد أصول تحتاج إهلاك لهذا الشهر'),
            type: count > 0 ? ToastType.success : ToastType.info,
          );
        }
      } catch (e) {
        if (mounted) {
          AppToast.show(context, tr('خطأ: {e}', {'e': e}), type: ToastType.error);
        }
      }
    }
  }

  void showSummary(IFixedAssetsRepository repo) async {
    final summary = await repo.getAssetsSummary();
    if (!mounted) return;

    final totalCost = summary['totalCost'] ?? 0.0;
    final totalDepreciation = summary['totalDepreciation'] ?? 0.0;
    final totalBookValue = summary['totalBookValue'] ?? 0.0;
    final assetCount = (summary['assetCount'] ?? 0.0).toInt();

    bool saving = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(tr('ملخص الأصول الثابتة'),
              style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
          content: SizedBox(
            width: 350,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                summaryTile(tr('عدد الأصول النشطة'), '$assetCount',
                    PhosphorIconsBold.buildings, AppColors.primary),
                const SizedBox(height: 8),
                summaryTile(tr('إجمالي التكلفة'),
                    _currencyFormat.format(totalCost),
                    PhosphorIconsBold.currencyCircleDollar, Colors.blue),
                const SizedBox(height: 8),
                summaryTile(tr('إجمالي الإهلاك المتراكم'),
                    _currencyFormat.format(totalDepreciation),
                    PhosphorIconsBold.trendDown, Colors.orange),
                const SizedBox(height: 8),
                summaryTile(tr('إجمالي القيمة الدفترية'),
                    _currencyFormat.format(totalBookValue),
                    PhosphorIconsBold.chartBar, AppColors.success),
              ],
            ),
          ),
          actions: [
            ElevatedButton.icon(
              icon: const Icon(PhosphorIconsBold.printer, size: 16),
              label:  Text(tr('طباعة السجل')),
              onPressed: saving ? null : () async {
                setDialogState(() => saving = true);
                try {
                  final assets = await repo.getFixedAssetsList();
                  await ReportPdfGenerator.printFixedAssetsRegister(
                    assets: assets,
                    totalCost: totalCost,
                    totalDepreciation: totalDepreciation,
                    totalBookValue: totalBookValue,
                  );
                } catch (e) {
                  if (ctx.mounted) AppToast.show(ctx, tr('خطأ: {e}', {'e': e}), type: ToastType.error);
                } finally {
                  if (ctx.mounted) setDialogState(() => saving = false);
                }
              },
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child:  Text(tr('إغلاق')),
            ),
          ],
        ),
      ),
    );
  }

  Widget summaryTile(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.15)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(label,
                style: GoogleFonts.cairo(fontSize: 12, color: Colors.grey.shade700)),
          ),
          Text(value,
              style: GoogleFonts.jetBrainsMono(
                  fontSize: 13, fontWeight: FontWeight.w700, color: color)),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // HELPERS
  // ═══════════════════════════════════════════════════════════════════

  String getDepreciationMethodLabel(String method) {
    switch (method) {
      case 'straight_line':
        return tr('القسط الثابت');
      case 'declining_balance':
        return tr('القسط المتناقص');
      default:
        return method;
    }
  }

  _AssetStatusInfo getAssetStatusInfo(String status) {
    switch (status) {
      case 'active':
        return _AssetStatusInfo(tr('نشط'), AppColors.success);
      case 'disposed':
        return _AssetStatusInfo(tr('مستبعد'), AppColors.error);
      case 'sold':
        return _AssetStatusInfo(tr('مباع'), Colors.orange);
      default:
        return _AssetStatusInfo(status, Colors.grey);
    }
  }
}

/// Feature 052: small read-only "label : value" row used by the asset edit
/// dialog to display immutable acquisition data (code, category, purchase
/// price/date, useful life, depreciation method, linked GL account). Kept
/// tight (≤ ~26px tall) so the edit form doesn't grow into a wall of text.
class _ImmutableFieldRow extends StatelessWidget {
  final String label;
  final String value;
  const _ImmutableFieldRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: const TextStyle(
                  fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
