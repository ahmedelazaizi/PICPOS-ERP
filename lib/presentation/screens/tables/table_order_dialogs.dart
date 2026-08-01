part of '../tables_screen.dart';

// ═══════════════════════════════════════════════════════════════════════════
// TABLE ORDER DIALOGS — Open, View Order, Close, Merge, Kitchen Print
// ═══════════════════════════════════════════════════════════════════════════

/// فحص صريح قبل طباعة أمر شغل/مطبخ لطاولة — نفس الكود اللي بيحمي
/// `_printKitchenOrdersForInvoice` في `pos_main_operations.dart`، مكرَّر هنا
/// لأنهم مكتبتين مختلفتين (`part of` جذور مختلفة، مفيش نقطة مشتركة موجودة).
@visibleForTesting
bool canPrintPosWorkOrder(List<String> permissions) {
  final isAdmin =
      permissions.contains('system_admin') || permissions.contains('*');
  return isAdmin || permissions.contains(PermissionCodes.posWorkOrder);
}

/// نسخة أعلى مستوى بتقرا الصلاحيات من `ref` وتعرض توست الرفض — سطر واحد في
/// نقطة الاستدعاء (زي `pos_main_operations.dart`).
@visibleForTesting
Future<bool> ensurePosWorkOrderPermission(
  WidgetRef ref,
  BuildContext context,
) async {
  final permissions =
      ref.read(currentUserPermissionsProvider).asData?.value ??
          const <String>[];
  if (canPrintPosWorkOrder(permissions)) return true;
  if (context.mounted) {
    AppToast.show(context, 'ليس لديك صلاحية طباعة أوامر الشغل',
        type: ToastType.error);
  }
  return false;
}

mixin _TableOrderDialogsMixin on ConsumerState<TablesScreen> {
  bool _openingTable = false;
  bool _closingTable = false;
  bool _mergingTables = false;

  // Abstract — provided by main State class
  Future<TableOrder?> _getOpenOrder(
    IRestaurantRepository restaurantRepo,
    int tableId,
  );
  // ignore: unused_element
  void _confirmOpenTable(
    IRestaurantRepository restaurantRepo,
    RestaurantTable table,
  ) async {
    final hrRepo = ref.read(hrRepositoryProvider);
    final employeesList = await hrRepo.getAllEmployees();
    int? selectedEmployeeId =
        employeesList.isNotEmpty ? employeesList.first.id : null;
    if (!mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Row(
                children: [
                  const Icon(
                    PhosphorIconsBold.circlesThree,
                    color: AppColors.info,
                  ),
                  const SizedBox(width: 8),
                  Text('فتح ${table.name}'),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('هل تريد فتح طلب جديد لهذه الطاولة؟'),
                  const SizedBox(height: 16),
                  if (employeesList.isNotEmpty)
                    Autocomplete<Employee>(
                      optionsBuilder: (textValue) {
                        if (textValue.text.isEmpty) return employeesList;
                        return employeesList.where(
                          (e) =>
                              e.name.toLowerCase().contains(
                                textValue.text.toLowerCase(),
                              ) ||
                              (e.phone?.contains(textValue.text) ?? false),
                        );
                      },
                      displayStringForOption: (e) =>
                          '${e.name}${e.role == 'waiter' ? ' (نادل)' : ''}',
                      initialValue: selectedEmployeeId != null
                          ? TextEditingValue(
                              text:
                                  employeesList
                                      .where((e) => e.id == selectedEmployeeId)
                                      .firstOrNull
                                      ?.name ??
                                  '',
                            )
                          : null,
                      fieldViewBuilder:
                          (context, controller, focusNode, onFieldSubmitted) {
                            return TextField(
                              controller: controller,
                              focusNode: focusNode,
                              decoration: InputDecoration(
                                labelText: 'النادل (الويتر)',
                                prefixIcon: const Icon(PhosphorIconsBold.user),
                                border: const OutlineInputBorder(),
                                hintText: 'ابحث عن موظف...',
                                suffixIcon: selectedEmployeeId != null
                                    ? IconButton(
                                        icon: const Icon(
                                          PhosphorIconsBold.x,
                                          size: 16,
                                        ),
                                        onPressed: () {
                                          controller.clear();
                                          setState(
                                            () => selectedEmployeeId = null,
                                          );
                                        },
                                      )
                                    : null,
                              ),
                            );
                          },
                      onSelected: (employee) {
                        setState(() => selectedEmployeeId = employee.id);
                      },
                    )
                  else
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.warning.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(
                        children: [
                          Icon(
                            PhosphorIconsBold.warning,
                            color: AppColors.warning,
                            size: 20,
                          ),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'لا يوجد موظفين. أضف موظفين من شاشة الموارد البشرية.',
                              style: TextStyle(fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('إلغاء'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.success,
                  ),
                  child: const Text('فتح'),
                ),
              ],
            );
          },
        ),
      ),
    );

    if (confirmed == true) {
      if (_openingTable) return;
      setState(() => _openingTable = true);
      try {
        await restaurantRepo.createTableOrder(
          table.id,
          userId: selectedEmployeeId,
        );
        try {
          final user = ref.read(authProvider).user;
          final activityLogRepo = ref.read(activityLogRepositoryProvider);
          await activityLogRepo.logActivity(
            userId: user?.id,
            userName: user?.displayName ?? 'مجهول',
            action: 'open_table',
            entityType: 'table',
            entityId: table.id,
            description: 'فتح طاولة: ${table.name}',
          );
        } catch (_) {}

        if (mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => TablePosScreen(
                tableId: table.id,
                tableName: table.name,
              ),
            ),
          );
        }
      } finally {
        if (mounted) setState(() => _openingTable = false);
      }
    }
  }

  void _showTableOrderDialog(
    BuildContext context,
    IRestaurantRepository restaurantRepo,
    RestaurantTable table,
  ) async {
    final order = await _getOpenOrder(restaurantRepo, table.id);
    if (order == null) return;

    final items = await restaurantRepo.getTableOrderItems(order.id);
    final productRepo = ref.read(productRepositoryProvider);
    if (!context.mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Row(
            children: [
              const Icon(PhosphorIconsBold.circlesThree, color: AppColors.info),
              const SizedBox(width: 8),
              Text(table.name),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: AppColors.warning,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${order.total.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolEn}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 400,
            height: 300,
            child: items.isEmpty
                ? const Center(
                    child: Text(
                      'لا توجد أصناف في الطلب',
                      style: TextStyle(color: AppColors.textMuted),
                    ),
                  )
                : ListView.separated(
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (ctx, idx) {
                      final item = items[idx];
                      return FutureBuilder<ProductEntity?>(
                        future: productRepo.getProductById(item.productId),
                        builder: (ctx, snap) {
                          final product = snap.data;
                          return ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(PhosphorIconsBold.package),
                            title: Text(
                              product?.name ?? 'صنف #${item.productId}',
                            ),
                            subtitle: Text(
                              '${item.unitPrice.toStringAsFixed(AppConstants.decimalPlaces)} × ${item.quantity.toStringAsFixed(0)}',
                            ),
                            trailing: Text(
                              '${item.total.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolEn}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
          ),
          actions: [
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                _onMergeTable(restaurantRepo, table, order);
              },
              icon: const Icon(PhosphorIconsBold.intersect),
              label: const Text('دمج مع طاولة أخرى'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.warning,
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إغلاق'),
            ),
            ElevatedButton.icon(
              onPressed: () async {
                Navigator.pop(ctx);
                await _printKitchenOrder(restaurantRepo, table, order);
                if (context.mounted) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => TablePosScreen(
                        tableId: table.id,
                        tableName: table.name,
                      ),
                    ),
                  );
                }
              },
              icon: const Icon(PhosphorIconsBold.plus),
              label: const Text('إضافة أصناف'),
            ),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                // Navigate to TablePosScreen for checkout/payment
                if (context.mounted) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => TablePosScreen(
                        tableId: table.id,
                        tableName: table.name,
                      ),
                    ),
                  );
                }
              },
              icon: const Icon(PhosphorIconsBold.currencyCircleDollar),
              label: const Text('تحصيل الحساب'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.success,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 3.1: Print kitchen order for table
  Future<void> _printKitchenOrder(
    IRestaurantRepository restaurantRepo,
    RestaurantTable table,
    TableOrder order,
  ) async {
    if (!await ensurePosWorkOrderPermission(ref, context)) return;
    try {
      final items = await restaurantRepo.getTableOrderItems(order.id);
      if (items.isEmpty) return;

      final productRepo = ref.read(productRepositoryProvider);
      final List<InvoiceItem> invoiceItems = [];
      for (final item in items) {
        final product = await productRepo.getProductById(item.productId);
        invoiceItems.add(
          InvoiceItem(
            name: product?.name ?? 'صنف #${item.productId}',
            quantity: item.quantity,
            price: item.unitPrice,
            total: item.total,
          ),
        );
      }

      final now = DateTime.now();
      final orderNumber =
          'T${table.id}-${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}';
      final headerInfo = 'طاولة: ${table.name}';

      await InvoiceGenerator.printWorkOrderReceipt(
        orderNumber: orderNumber,
        date: now,
        categoryName: headerInfo,
        items: invoiceItems,
        db: ref.read(databaseProvider),
      );
    } catch (e) {
      debugPrint('Failed to print kitchen order: $e');
    }
  }

  Future<void> _closeTable(
    IRestaurantRepository restaurantRepo,
    RestaurantTable table,
    TableOrder order,
  ) async {
    if (_closingTable) return;
    setState(() => _closingTable = true);
    try {
      await restaurantRepo.finalizeTableOrder(order.id, table.id);
      try {
        final user = ref.read(authProvider).user;
        final activityLogRepo = ref.read(activityLogRepositoryProvider);
        await activityLogRepo.logActivity(
          userId: user?.id,
          userName: user?.displayName ?? 'مجهول',
          action: 'close_table',
          entityType: 'table',
          entityId: table.id,
          description:
              'إغلاق طاولة: ${table.name} — الإجمالي: ${order.total.toStringAsFixed(AppConstants.decimalPlaces)}',
          amount: order.total,
        );
      } catch (_) {}

      if (mounted) {
        AppToast.show(
          context,
          'تم إغلاق ${table.name} - الإجمالي: ${order.total.toStringAsFixed(AppConstants.decimalPlaces)}',
          type: ToastType.success,
        );
      }
    } finally {
      if (mounted) setState(() => _closingTable = false);
    }
  }

  Future<void> _onMergeTable(
    IRestaurantRepository restaurantRepo,
    RestaurantTable sourceTable,
    TableOrder sourceOrder,
  ) async {
    if (_mergingTables) return;
    final allTables = await restaurantRepo.getAllTables();
    final allOccupied = allTables
        .where((t) =>
            (t.status == 'occupied' || t.status == 'billing') &&
            t.id != sourceTable.id &&
            t.isActive)
        .toList();

    if (!mounted) return;

    if (allOccupied.isEmpty) {
      AppToast.show(
        context,
        'لا توجد طاولات مشغولة أخرى للدمج معها',
        type: ToastType.warning,
      );
      return;
    }

    final targetTable = await showDialog<RestaurantTable>(
      context: context,
      builder: (ctx) => MergeTableDialog(
        sourceTable: sourceTable,
        otherOccupiedTables: allOccupied.cast<RestaurantTable>(),
        onMerge: (table) => Navigator.pop(ctx, table),
      ),
    );

    if (targetTable != null && mounted) {
      setState(() => _mergingTables = true);
      try {
        await restaurantRepo.mergeTableOrders(sourceTable.id, targetTable.id);
        if (mounted) {
          try {
            final user = ref.read(authProvider).user;
            final activityLogRepo = ref.read(activityLogRepositoryProvider);
            await activityLogRepo.logActivity(
              userId: user?.id,
              userName: user?.displayName ?? 'مجهول',
              action: 'merge_tables',
              entityType: 'table',
              entityId: sourceTable.id,
              description:
                  'دمج طاولة ${sourceTable.name} مع ${targetTable.name}',
            );
          } catch (_) {}

          if (mounted) {
            AppToast.show(
              context,
              'تم دمج ${sourceTable.name} بنجاح مع ${targetTable.name}',
              type: ToastType.success,
            );
          }
        }
      } catch (e) {
        if (mounted) {
          AppToast.show(
            context,
            'فشل دمج الطاولات: $e',
            type: ToastType.error,
          );
        }
      } finally {
        if (mounted) setState(() => _mergingTables = false);
      }
    }
  }
}
