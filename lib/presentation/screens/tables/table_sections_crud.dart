part of '../tables_screen.dart';

// ═══════════════════════════════════════════════════════════════════════════
// SECTION MANAGEMENT — Add, Edit, Delete sections + Table CRUD
// ═══════════════════════════════════════════════════════════════════════════

mixin _TableSectionsMixin on ConsumerState<TablesScreen> {
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
            title: const Row(
              children: [
                Icon(PhosphorIconsBold.layout, color: AppColors.primary),
                SizedBox(width: 8),
                Text('إضافة قسم جديد'),
              ],
            ),
            content: TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'اسم القسم (مثلاً: الصالة)',
                prefixIcon: Icon(PhosphorIconsBold.textT),
              ),
              autofocus: true,
            ),
            actions: [
              TextButton(
                onPressed: _savingSection ? null : () => Navigator.pop(ctx),
                child: const Text('إلغاء'),
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
                            userName: user?.displayName ?? 'مجهول',
                            action: 'add_section',
                            entityType: 'table_section',
                            description: 'إضافة قسم: ${nameController.text.trim()}',
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
                    : const Text('إضافة'),
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
          title: const Row(
            children: [
              Icon(PhosphorIconsBold.pencilSimple, color: AppColors.primary),
              SizedBox(width: 8),
              Text('إدارة الأقسام'),
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
                  return const Center(child: Text('لا توجد أقسام'));
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
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إغلاق'),
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
            title: const Text('تعديل القسم'),
            content: TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'اسم القسم',
                prefixIcon: Icon(PhosphorIconsBold.textT),
              ),
              autofocus: true,
            ),
            actions: [
              TextButton(
                onPressed: _savingSection ? null : () => Navigator.pop(ctx),
                child: const Text('إلغاء'),
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
                            userName: user?.displayName ?? 'مجهول',
                            action: 'update_section',
                            entityType: 'table_section',
                            entityId: section.id,
                            description: 'تعديل قسم: ${nameController.text.trim()}',
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
                    : const Text('حفظ'),
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Row(
            children: [
              Icon(PhosphorIconsBold.warning, color: AppColors.error),
              SizedBox(width: 8),
              Text('حذف القسم'),
            ],
          ),
          content: Text('هل أنت متأكد من حذف قسم "${section.name}"؟'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
              child: const Text('حذف'),
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
          userName: user?.displayName ?? 'مجهول',
          action: 'delete_section',
          entityType: 'table_section',
          entityId: section.id,
          description: 'حذف قسم: ${section.name}',
        );
        if (context.mounted) {
          AppToast.show(context, 'تم حذف القسم بنجاح', type: ToastType.success);
        }
      } catch (e) {
        if (context.mounted) {
          AppToast.show(context, 'خطأ: $e', type: ToastType.error);
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
                Text(existingTable == null ? 'إضافة طاولة' : 'تعديل الطاولة'),
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
                        decoration: const InputDecoration(
                          labelText: 'القسم',
                          prefixIcon: Icon(PhosphorIconsBold.layout),
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
                    decoration: const InputDecoration(
                      labelText: 'اسم الطاولة *',
                      prefixIcon: Icon(PhosphorIconsBold.textT),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: capacityController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'السعة',
                      prefixIcon: Icon(PhosphorIconsBold.users),
                      suffixText: 'أشخاص',
                    ),
                  ),
                  if (existingTable == null) ...[
                    const SizedBox(height: 16),
                    TextField(
                      controller: countController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'عدد الطاولات',
                        prefixIcon: Icon(PhosphorIconsBold.stack),
                        hintText: 'أدخل 1 لطاولة واحدة أو أكثر لإضافة دفعة',
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: _savingTable ? null : () => Navigator.pop(ctx),
                child: const Text('إلغاء'),
              ),
              ElevatedButton(
                onPressed: _savingTable
                    ? null
                    : () async {
                        if (nameController.text.trim().isEmpty) {
                          AppToast.show(
                            ctx,
                            'يرجى إدخال اسم الطاولة',
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
                                sectionId: selectedSectionId!,
                                capacity: capacity,
                              );
                            }

                            await activityLogRepo.logActivity(
                              userId: user?.id,
                              userName: user?.displayName ?? 'مجهول',
                              action: 'add_table',
                              entityType: 'restaurant_table',
                              description: count > 1
                                  ? 'إضافة $count طاولات: $baseName (سعة: $capacity)'
                                  : 'إضافة طاولة: $baseName (سعة: $capacity)',
                            );
                          } else {
                            await restaurantRepo.updateTable(
                              id: existingTable.id,
                              name: nameController.text.trim(),
                              capacity: capacity,
                              sectionId: selectedSectionId!,
                            );
                            final user = ref.read(authProvider).user;
                            final activityLogRepo =
                                ref.read(activityLogRepositoryProvider);
                            await activityLogRepo.logActivity(
                              userId: user?.id,
                              userName: user?.displayName ?? 'مجهول',
                              action: 'update_table',
                              entityType: 'restaurant_table',
                              entityId: existingTable.id,
                              description: 'تعديل طاولة: ${nameController.text.trim()}',
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
                    : Text(existingTable == null ? 'إضافة' : 'حفظ'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDeleteTable(
    IRestaurantRepository restaurantRepo,
    RestaurantTable table,
  ) async {
    if (table.status != 'available' && table.status != 'reserved') {
      AppToast.show(
        context,
        table.status == 'billing'
            ? 'لا يمكن حذف طاولة بانتظار الدفع'
            : 'لا يمكن حذف طاولة مشغولة',
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
        AppToast.show(
          // ignore: use_build_context_synchronously
          context,
          'لا يمكن حذف طاولة بها طلبات نشطة',
          type: ToastType.error,
        );
        return;
      }
    }

    if (!context.mounted) return;

    final confirmed = await showDialog<bool>(
      // ignore: use_build_context_synchronously
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Row(
            children: [
              Icon(PhosphorIconsBold.warning, color: AppColors.error),
              SizedBox(width: 8),
              Text('حذف الطاولة'),
            ],
          ),
          content: Text('هل أنت متأكد من حذف "${table.name}"؟'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
              child: const Text('حذف'),
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
        userName: user?.displayName ?? 'مجهول',
        action: 'delete_table',
        entityType: 'restaurant_table',
        entityId: table.id,
        description: 'حذف طاولة: ${table.name}',
      );
      if (context.mounted) {
        // ignore: use_build_context_synchronously
        AppToast.show(context, 'تم حذف الطاولة', type: ToastType.success);
      }
    }
  }
}
