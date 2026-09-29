part of '../tables_screen.dart';

// ═══════════════════════════════════════════════════════════════════════════
// SECTION MANAGEMENT — Add, Edit, Delete sections + Table CRUD
// ═══════════════════════════════════════════════════════════════════════════

/// القيدُ موسَّعٌ للسبب المشروح فوق `_TableOrderDialogsMixin`.
mixin _TableSectionsMixin<T extends ConsumerStatefulWidget>
    on ConsumerState<T> {
  bool _savingSection = false;
  bool _savingTable = false;

  void _showAddSectionDialog(
    BuildContext context,
    IRestaurantRepository restaurantRepo,
  ) {
    final nameController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: StatefulBuilder(
          builder: (ctx, setDialogState) => AlertDialog(
            title:  Row(
              children: [
                const Icon(PhosphorIconsBold.layout, color: AppColors.primary),
                const SizedBox(width: 8),
                Text(tr('إضافة قسم جديد')),
              ],
            ),
            content: TextField(
              controller: nameController,
              decoration:  InputDecoration(
                labelText: tr('اسم القسم (مثلاً: الصالة)'),
                prefixIcon: const Icon(PhosphorIconsBold.textT),
              ),
              autofocus: true,
            ),
            actions: [
              TextButton(
                onPressed: _savingSection ? null : () => Navigator.pop(ctx),
                child:  Text(tr('إلغاء')),
              ),
              ElevatedButton(
                onPressed: _savingSection
                    ? null
                    : () async {
                        if (nameController.text.trim().isEmpty) return;
                        setDialogState(() => _savingSection = true);
                        try {
                          await restaurantRepo.createSection(nameController.text.trim());
                          final user = ref.read(authProvider).user;
                          final activityLogRepo =
                              ref.read(activityLogRepositoryProvider);
                          await activityLogRepo.logActivity(
                            userId: user?.id,
                            userName: user?.displayName ?? tr('مجهول'),
                            action: 'add_section',
                            entityType: 'table_section',
                            description: tr('إضافة قسم: {p0}', {'p0': nameController.text.trim()}),
                          );
                          if (ctx.mounted) Navigator.pop(ctx);
                        } finally {
                          if (ctx.mounted) setDialogState(() => _savingSection = false);
                        }
                      },
                child: _savingSection
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    :  Text(tr('إضافة')),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showManageSectionsDialog(IRestaurantRepository restaurantRepo) {
    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title:  Row(
            children: [
              const Icon(PhosphorIconsBold.pencilSimple, color: AppColors.primary),
              const SizedBox(width: 8),
              Text(tr('إدارة الأقسام')),
            ],
          ),
          content: SizedBox(
            width: 400,
            height: 300,
            child: StreamBuilder<List<TableSection>>(
              stream: restaurantRepo.watchAllSections(),
              builder: (context, snapshot) {
                final sections = snapshot.data ?? [];
                if (sections.isEmpty) {
                  return  Center(child: Text(tr('لا توجد أقسام')));
                }
                return ListView.separated(
                  itemCount: sections.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final section = sections[index];
                    return ListTile(
                      title: Text(section.name),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(
                              PhosphorIconsBold.pencil,
                              size: 18,
                              color: AppColors.primary,
                            ),
                            onPressed: () => _showEditSectionDialog(
                              context,
                              restaurantRepo,
                              section,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(
                              PhosphorIconsBold.trash,
                              size: 18,
                              color: AppColors.error,
                            ),
                            onPressed: () => _confirmDeleteSection(
                              context,
                              restaurantRepo,
                              section,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
          actions: [
            // بلا `PermissionGuard`: بابُ هذه النافذة نفسِه (`manageSections`)
            // محروسٌ بـ`tables_manage` في نداءَيه بشاشتَي PicPos والقديمة —
            // فمن وصل هنا يملكها أصلاً، تماماً كزرَّي التعديل والحذف أسفلَ
            // القائمة اللذين لا يحملان حراسةً إضافيّةً للسبب نفسه.
            TextButton.icon(
              onPressed: () => _showAddSectionDialog(ctx, restaurantRepo),
              icon: const Icon(PhosphorIconsBold.plus, size: 18),
              label:  Text(tr('إضافة قسم')),
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

  void _showEditSectionDialog(
    BuildContext context,
    IRestaurantRepository restaurantRepo,
    TableSection section,
  ) {
    final nameController = TextEditingController(text: section.name);
    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: StatefulBuilder(
          builder: (ctx, setDialogState) => AlertDialog(
            title:  Text(tr('تعديل القسم')),
            content: TextField(
              controller: nameController,
              decoration:  InputDecoration(
                labelText: tr('اسم القسم'),
                prefixIcon: const Icon(PhosphorIconsBold.textT),
              ),
              autofocus: true,
            ),
            actions: [
              TextButton(
                onPressed: _savingSection ? null : () => Navigator.pop(ctx),
                child:  Text(tr('إلغاء')),
              ),
              ElevatedButton(
                onPressed: _savingSection
                    ? null
                    : () async {
                        if (nameController.text.trim().isEmpty) return;
                        setDialogState(() => _savingSection = true);
                        try {
                          final oldName = section.name;
                          await restaurantRepo.updateSection(
                            section.id,
                            nameController.text.trim(),
                          );
                          final user = ref.read(authProvider).user;
                          final activityLogRepo =
                              ref.read(activityLogRepositoryProvider);
                          await activityLogRepo.logActivity(
                            userId: user?.id,
                            userName: user?.displayName ?? tr('مجهول'),
                            action: 'update_section',
                            entityType: 'table_section',
                            entityId: section.id,
                            description: tr('تعديل قسم: {p0}', {'p0': nameController.text.trim()}),
                            oldValue: oldName,
                            newValue: nameController.text.trim(),
                          );
                          if (ctx.mounted) Navigator.pop(ctx);
                        } finally {
                          if (ctx.mounted) setDialogState(() => _savingSection = false);
                        }
                      },
                child: _savingSection
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    :  Text(tr('حفظ')),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDeleteSection(
    BuildContext context,
    IRestaurantRepository restaurantRepo,
    TableSection section,
  ) async {
        if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title:  Row(
            children: [
              const Icon(PhosphorIconsBold.warning, color: AppColors.error),
              const SizedBox(width: 8),
              Text(tr('حذف القسم')),
            ],
          ),
          content: Text(tr('هل أنت متأكد من حذف قسم "{p0}"؟', {'p0': section.name})),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child:  Text(tr('إلغاء')),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
              child:  Text(tr('حذف')),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true && context.mounted) {
      try {
        await restaurantRepo.deleteSection(section.id);
        final user = ref.read(authProvider).user;
        final activityLogRepo = ref.read(activityLogRepositoryProvider);
        await activityLogRepo.logActivity(
          userId: user?.id,
          userName: user?.displayName ?? tr('مجهول'),
          action: 'delete_section',
          entityType: 'table_section',
          entityId: section.id,
          description: tr('حذف قسم: {p0}', {'p0': section.name}),
        );
        if (context.mounted) {
          AppToast.show(context, tr('تم حذف القسم بنجاح'), type: ToastType.success);
        }
      } catch (e) {
        if (context.mounted) {
          AppToast.show(context, tr('خطأ: {e}', {'e': e}), type: ToastType.error);
        }
      }
    }
  }

  void _showAddTableDialog(
    BuildContext context,
    IRestaurantRepository restaurantRepo, {
    int? sectionId,
  }) {
    _showTableFormDialog(context, restaurantRepo, null, sectionId: sectionId);
  }

  // ignore: unused_element
  void _showEditTableDialog(
    BuildContext context,
    IRestaurantRepository restaurantRepo,
    RestaurantTable table,
  ) {
    _showTableFormDialog(
      context,
      restaurantRepo,
      table,
      sectionId: table.sectionId,
    );
  }

  void _showTableFormDialog(
    BuildContext context,
    IRestaurantRepository restaurantRepo,
    RestaurantTable? existingTable, {
    int? sectionId,
  }) {
    final nameController = TextEditingController(
      text: existingTable?.name ?? '',
    );
    final capacityController = TextEditingController(
      text: (existingTable?.capacity ?? 4).toString(),
    );
    final countController = TextEditingController(text: '1');
    int? selectedSectionId = sectionId ?? existingTable?.sectionId;

    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: Row(
              children: [
                const Icon(
                  PhosphorIconsBold.circlesThree,
                  color: AppColors.info,
                ),
                const SizedBox(width: 8),
                Text(existingTable == null ? tr('إضافة طاولة') : tr('تعديل الطاولة')),
              ],
            ),
            content: SizedBox(
              width: 350,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  StreamBuilder<List<TableSection>>(
                    stream: restaurantRepo.watchAllSections(),
                    builder: (context, snapshot) {
                      final sections = snapshot.data ?? [];
                      return DropdownButtonFormField<int>(
                        initialValue: selectedSectionId,
                        decoration:  InputDecoration(
                          labelText: tr('القسم'),
                          prefixIcon: const Icon(PhosphorIconsBold.layout),
                        ),
                        items: sections
                            .map(
                              (s) => DropdownMenuItem(
                                value: s.id,
                                child: Text(s.name),
                              ),
                            )
                            .toList(),
                        onChanged: (val) =>
                            setDialogState(() => selectedSectionId = val),
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: nameController,
                    decoration:  InputDecoration(
                      labelText: tr('اسم الطاولة *'),
                      prefixIcon: const Icon(PhosphorIconsBold.textT),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: capacityController,
                    keyboardType: TextInputType.number,
                    decoration:  InputDecoration(
                      labelText: tr('السعة'),
                      prefixIcon: const Icon(PhosphorIconsBold.users),
                      suffixText: tr('أشخاص'),
                    ),
                  ),
                  if (existingTable == null) ...[
                    const SizedBox(height: 16),
                    TextField(
                      controller: countController,
                      keyboardType: TextInputType.number,
                      decoration:  InputDecoration(
                        labelText: tr('عدد الطاولات'),
                        prefixIcon: const Icon(PhosphorIconsBold.stack),
                        hintText: tr('أدخل 1 لطاولة واحدة أو أكثر لإضافة دفعة'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: _savingTable ? null : () => Navigator.pop(ctx),
                child:  Text(tr('إلغاء')),
              ),
              ElevatedButton(
                onPressed: _savingTable
                    ? null
                    : () async {
                        if (nameController.text.trim().isEmpty) {
                          AppToast.show(
                            ctx,
                            tr('يرجى إدخال اسم الطاولة'),
                            type: ToastType.warning,
                          );
                          return;
                        }
                        // ⚠️ **القسمُ محروسٌ كالاسم — وغيابُ حارسِه انهيارٌ
                        // مقيسٌ في الميدان** (لوج المالك 2026-09-18T06:47:05:
                        // `Null check operator used on a null value`).
                        //
                        // `selectedSectionId` يُهيَّأ بـ`sectionId ??
                        // existingTable?.sectionId`، فهو فارغٌ لطاولةٍ جديدةٍ
                        // حين لا تحمل الشاشةُ نطاقَ قسمٍ («كل المناطق») أو
                        // حين لا أقسامَ بعد. وكان يُفَضّ بـ`!` في موضعَين.
                        //
                        // ونسخةٌ محلّيّةٌ لا `!`: `selectedSectionId` متغيّرٌ
                        // يلتقطه الإغلاقُ ويكتبه `setDialogState`، فلا
                        // يُرقّيه المحلّلُ بعد الفحص مهما فُحص.
                        final chosenSectionId = selectedSectionId;
                        if (chosenSectionId == null) {
                          AppToast.show(
                            ctx,
                            tr('يرجى اختيار القسم'),
                            type: ToastType.warning,
                          );
                          return;
                        }
                        setDialogState(() => _savingTable = true);
                        try {
                          final capacity = int.tryParse(capacityController.text) ?? 4;
                          final count = int.tryParse(countController.text) ?? 1;

                          if (existingTable == null) {
                            final baseName = nameController.text.trim();
                            final user = ref.read(authProvider).user;
                            final activityLogRepo = ref.read(activityLogRepositoryProvider);

                            for (int i = 1; i <= count; i++) {
                              final tableName = count > 1 ? '$baseName $i' : baseName;
                              await restaurantRepo.createTable(
                                name: tableName,
                                sectionId: chosenSectionId,
                                capacity: capacity,
                              );
                            }

                            await activityLogRepo.logActivity(
                              userId: user?.id,
                              userName: user?.displayName ?? tr('مجهول'),
                              action: 'add_table',
                              entityType: 'restaurant_table',
                              description: count > 1
                                  ? tr('إضافة {count} طاولات: {baseName} (سعة: {capacity})', {'count': count, 'baseName': baseName, 'capacity': capacity})
                                  : tr('إضافة طاولة: {baseName} (سعة: {capacity})', {'baseName': baseName, 'capacity': capacity}),
                            );
                          } else {
                            await restaurantRepo.updateTable(
                              id: existingTable.id,
                              name: nameController.text.trim(),
                              capacity: capacity,
                              sectionId: chosenSectionId,
                            );
                            final user = ref.read(authProvider).user;
                            final activityLogRepo =
                                ref.read(activityLogRepositoryProvider);
                            await activityLogRepo.logActivity(
                              userId: user?.id,
                              userName: user?.displayName ?? tr('مجهول'),
                              action: 'update_table',
                              entityType: 'restaurant_table',
                              entityId: existingTable.id,
                              description: tr('تعديل طاولة: {p0}', {'p0': nameController.text.trim()}),
                              oldValue: existingTable.name,
                              newValue: nameController.text.trim(),
                            );
                          }

                          if (ctx.mounted) Navigator.pop(ctx);
                        } finally {
                          if (ctx.mounted) setDialogState(() => _savingTable = false);
                        }
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.info,
                ),
                child: _savingTable
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(existingTable == null ? tr('إضافة') : tr('حفظ')),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ignore: unused_element
  Future<void> _confirmDeleteTable(
    IRestaurantRepository restaurantRepo,
    RestaurantTable table,
  ) async {
    if (table.status != 'available' && table.status != 'reserved') {
              if (!mounted) return;
      AppToast.show(
        context,
        table.status == 'billing'
            ? tr('لا يمكن حذف طاولة بانتظار الدفع')
            : tr('لا يمكن حذف طاولة مشغولة'),
        type: ToastType.error,
      );
      return;
    }

    final activeOrder = await restaurantRepo.getActiveOrderForTable(table.id);
    if (!context.mounted) return;
    if (activeOrder != null) {
      final items = await restaurantRepo.getTableOrderItems(activeOrder.id);
      if (!context.mounted) return;
      if (items.isNotEmpty) {
                if (!mounted) return;
        AppToast.show(
                    context,
          tr('لا يمكن حذف طاولة بها طلبات نشطة'),
          type: ToastType.error,
        );
        return;
      }
    }

    if (!context.mounted) return;

        if (!mounted) return;

    final confirmed = await showDialog<bool>(
            context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title:  Row(
            children: [
              const Icon(PhosphorIconsBold.warning, color: AppColors.error),
              const SizedBox(width: 8),
              Text(tr('حذف الطاولة')),
            ],
          ),
          content: Text(tr('هل أنت متأكد من حذف "{p0}"؟', {'p0': table.name})),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child:  Text(tr('إلغاء')),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
              child:  Text(tr('حذف')),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true && context.mounted) {
      await restaurantRepo.deleteTable(table.id);
      if (!context.mounted) return;
      final user = ref.read(authProvider).user;
      final activityLogRepo = ref.read(activityLogRepositoryProvider);
      await activityLogRepo.logActivity(
        userId: user?.id,
        userName: user?.displayName ?? tr('مجهول'),
        action: 'delete_table',
        entityType: 'restaurant_table',
        entityId: table.id,
        description: tr('حذف طاولة: {p0}', {'p0': table.name}),
      );
            if (!mounted) return;
      if (context.mounted) {
                AppToast.show(context, tr('تم حذف الطاولة'), type: ToastType.success);
      }
    }
  }
}
