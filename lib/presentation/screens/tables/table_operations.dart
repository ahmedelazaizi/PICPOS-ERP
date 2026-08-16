part of '../tables_screen.dart';

// ═══════════════════════════════════════════════════════════════════════════
// TABLE OPERATIONS — Split, Transfer, Options, Reservations
// ═══════════════════════════════════════════════════════════════════════════

mixin _TableOperationsMixin on ConsumerState<TablesScreen> {
  // Abstract — provided by _TableOrderDialogsMixin at composition time
  void _confirmOpenTable(
    IRestaurantRepository restaurantRepo,
    RestaurantTable table,
  );
  Future<void> _onMergeTable(
    IRestaurantRepository restaurantRepo,
    RestaurantTable sourceTable,
    TableOrder sourceOrder,
  );
  Future<void> _closeTable(
    IRestaurantRepository restaurantRepo,
    RestaurantTable table,
    TableOrder order,
  );
  Future<void> _confirmDeleteTable(
    IRestaurantRepository restaurantRepo,
    RestaurantTable table,
  );
  void _showEditTableDialog(
    BuildContext context,
    IRestaurantRepository restaurantRepo,
    RestaurantTable table,
  );
  /// تقسيمُ فاتورة — لا نقلَ أصنافٍ إلى طاولةٍ أخرى. الشاشةُ نفسُها تبني
  /// الخطّةَ وتملأ السلّةَ وتدفع وتسوّي كلَّ حصّةٍ (عبر
  /// `TableCheckoutCoordinator`)، فلا شيءَ يبقى لهذه الدالّة بعد إغلاقها
  /// سوى إظهار نتيجةٍ للكاشير.
  void _handleSplitTable(
    BuildContext context,
    IRestaurantRepository restaurantRepo,
    RestaurantTable table,
  ) async {
    final order = await restaurantRepo.getActiveOrderForTable(table.id);
    if (!context.mounted) return;

    if (order == null) {
      AppToast.show(context, 'لا يوجد طلبٌ نشطٌ لتقسيمه', type: ToastType.warning);
      return;
    }

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => SplitTableDialog(
        sourceTable: table,
        restaurantRepo: restaurantRepo,
      ),
    );

    if (result == true && mounted) {
      try {
        final user = ref.read(authProvider).user;
        final activityLogRepo = ref.read(activityLogRepositoryProvider);
        await activityLogRepo.logActivity(
          userId: user?.id,
          userName: user?.displayName ?? 'مجهول',
          action: 'split_bill',
          entityType: 'table',
          entityId: table.id,
          description: 'تقسيمُ فاتورة ${table.name}',
        );
      } catch (_) {}
    }
  }

  void _handleTransferOrder(
    BuildContext context,
    IRestaurantRepository restaurantRepo,
    RestaurantTable table,
  ) async {
    final allTables = await restaurantRepo.getAllTables();
    final availableTables = allTables
        .where((t) => t.status == 'available' && t.isActive && t.id != table.id)
        .toList();

    if (!context.mounted) return;

    if (availableTables.isEmpty) {
      AppToast.show(
        context,
        'لا توجد طاولات متاحة للنقل إليها',
        type: ToastType.warning,
      );
      return;
    }

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: TransferDialog(
          sourceTable: table,
          availableTables: availableTables.cast<RestaurantTable>(),
          restaurantRepo: restaurantRepo,
        ),
      ),
    );

    if (result != null && mounted) {
      final targetTable = result['target'] as RestaurantTable;
      final itemIds = result['itemIds'] as List<int>;
      final transferAll = result['transferAll'] as bool;

      try {
        if (transferAll) {
          // `transferOrder` تشترط ألّا يكون دُفع من الطلب شيء، وتكتب سطرَ
          // السجلِّ بنفسها — لا نداءَ يدويّاً بعدها.
          final user = ref.read(authProvider).user;
          await ref.read(tableSessionServiceProvider).transferOrder(
                fromTableId: table.id,
                toTableId: targetTable.id,
                userId: user?.id,
                userName: user?.displayName ?? 'مجهول',
              );
        } else {
          final Map<int, double> itemQuantities = {};
          final order = await restaurantRepo.getActiveOrderForTable(table.id);
          if (order != null) {
            final items = await restaurantRepo.getTableOrderItems(order.id);
            for (final id in itemIds) {
              final item = items.where((i) => i.id == id).firstOrNull;
              if (item != null) {
                itemQuantities[id] = item.quantity;
              }
            }
          }

          await restaurantRepo.partialTransferTableOrder(
            sourceTableId: table.id,
            targetTableId: targetTable.id,
            itemQuantities: itemQuantities,
          );

          if (context.mounted) {
            try {
              final user = ref.read(authProvider).user;
              final activityLogRepo = ref.read(activityLogRepositoryProvider);
              await activityLogRepo.logActivity(
                userId: user?.id,
                userName: user?.displayName ?? 'مجهول',
                action: 'transfer_order',
                entityType: 'table',
                entityId: table.id,
                description:
                    'نقل ${itemIds.length} صنف من ${table.name} إلى ${targetTable.name}',
              );
            } catch (_) {}
          }
        }

        if (context.mounted) {
          AppToast.show(
            context,
            transferAll
                ? 'تم نقل الطلب من ${table.name} إلى ${targetTable.name}'
                : 'تم نقل ${itemIds.length} صنف من ${table.name} إلى ${targetTable.name}',
            type: ToastType.success,
          );
        }
      } catch (e) {
        if (context.mounted) {
          AppToast.show(
            context,
            'خطأ في نقل الطلب: $e',
            type: ToastType.error,
          );
        }
      }
    }
  }

  /// نصوصُ الكبسات — نصُّ المواصفة حرفياً، بترتيب `TableAction`.
  static const Map<TableAction, String> _tableActionLabels = {
    TableAction.open: 'فتح طاولة',
    TableAction.addItems: 'إضافة طلب',
    TableAction.transfer: 'نقل الطلب',
    TableAction.merge: 'دمج الطاولات',
    TableAction.splitBill: 'تقسيم الفاتورة',
    TableAction.printBill: 'طباعة الفاتورة',
    TableAction.reserve: 'حجز طاولة',
    TableAction.pay: 'الدفع',
    TableAction.changeStatus: 'تغيير الحالة',
    TableAction.cancelOrder: 'إلغاء الطلب',
    TableAction.closeTable: 'إغلاق الطاولة',
    TableAction.log: 'سجل الطاولة',
  };

  IconData _tableActionIcon(TableAction action) {
    switch (action) {
      case TableAction.open:
        return PhosphorIconsBold.doorOpen;
      case TableAction.addItems:
        return PhosphorIconsBold.plus;
      case TableAction.transfer:
        return PhosphorIconsBold.arrowsLeftRight;
      case TableAction.merge:
        return PhosphorIconsBold.intersect;
      case TableAction.splitBill:
        return PhosphorIconsBold.columns;
      case TableAction.printBill:
        return PhosphorIconsBold.printer;
      case TableAction.reserve:
        return PhosphorIconsBold.calendarPlus;
      case TableAction.pay:
        return PhosphorIconsBold.currencyCircleDollar;
      case TableAction.changeStatus:
        return PhosphorIconsBold.arrowsClockwise;
      case TableAction.cancelOrder:
        return PhosphorIconsBold.xCircle;
      case TableAction.closeTable:
        return PhosphorIconsBold.checkCircle;
      case TableAction.log:
        return PhosphorIconsBold.clockCounterClockwise;
    }
  }

  /// لونُ الكبسة. `cancelOrder` وحدَه بلون الخطر — يهدم طلباً حياً. أما
  /// `closeTable` فروتينٌ: الحسابُ سُدِّد، والطاولةُ تحتاج تحريراً لا غير.
  Color _tableActionColor(TableAction action) {
    switch (action) {
      case TableAction.open:
        return AppColors.success;
      case TableAction.addItems:
        return AppColors.info;
      case TableAction.transfer:
        return AppColors.booking;
      case TableAction.merge:
        return AppColors.warning;
      case TableAction.splitBill:
        return const Color(0xFF06B6D4);
      case TableAction.printBill:
        return const Color(0xFF64748B);
      case TableAction.reserve:
        return Colors.orange;
      case TableAction.pay:
        return AppColors.success;
      case TableAction.changeStatus:
        return const Color(0xFF6366F1);
      case TableAction.cancelOrder:
        return AppColors.error;
      case TableAction.closeTable:
        return const Color(0xFF0EA5E9);
      case TableAction.log:
        return AppColors.textMuted;
    }
  }

  /// Show the table's actions menu — one row per `TableAction`, derived
  /// من `actionsForStatus(table.status)` لا شروطٌ متناثرة. غيابُ «الدفع»
  /// عن طاولةٍ فارغة أو «النقل» عن طاولةٍ بلا طلبٍ نتيجةٌ تلقائيةٌ للقائمة
  /// المُشتقّة، لا شرطٍ يُكتَب هنا فيُنسى في نسخةٍ تالية.
  void _showTableOptions(
    BuildContext context,
    IRestaurantRepository restaurantRepo,
    RestaurantTable table,
  ) {
    final actions = actionsForStatus(table.status);

    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Row(
            children: [
              const Icon(
                PhosphorIconsBold.circlesThree,
                color: AppColors.success,
              ),
              const SizedBox(width: 8),
              Text(table.name),
            ],
          ),
          content: SizedBox(
            width: 320,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final action in actions) ...[
                    _buildActionButton(ctx, context, restaurantRepo, table, action),
                    const SizedBox(height: 8),
                  ],
                  const SizedBox(height: 8),
                  // Secondary actions row — تعديل/حذف الطاولة نفسها، لا
                  // علاقةَ لهما بحالة الطلب فليسا من `TableAction`.
                  Row(
                    children: [
                      Expanded(
                        child: PermissionGuard(
                          permission: PermissionCodes.tablesManage,
                          allowManagerOverride: true,
                          actionName: 'تعديل طاولة',
                          onGranted: () {
                            Navigator.pop(ctx);
                            _showEditTableDialog(context, restaurantRepo, table);
                          },
                          child: TextButton.icon(
                            onPressed: () {
                              Navigator.pop(ctx);
                              _showEditTableDialog(context, restaurantRepo, table);
                            },
                            icon: const Icon(PhosphorIconsBold.pencil, size: 16),
                            label: const Text('تعديل'),
                          ),
                        ),
                      ),
                      Expanded(
                        child: PermissionGuard(
                          permission: PermissionCodes.tablesManage,
                          allowManagerOverride: true,
                          actionName: 'حذف طاولة',
                          onGranted: () {
                            Navigator.pop(ctx);
                            _confirmDeleteTable(restaurantRepo, table);
                          },
                          child: TextButton.icon(
                            onPressed: () {
                              Navigator.pop(ctx);
                              _confirmDeleteTable(restaurantRepo, table);
                            },
                            icon: const Icon(PhosphorIconsBold.trash, size: 16, color: AppColors.error),
                            label: const Text('حذف', style: TextStyle(color: AppColors.error)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
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

  Widget _buildActionButton(
    BuildContext dialogContext,
    BuildContext screenContext,
    IRestaurantRepository restaurantRepo,
    RestaurantTable table,
    TableAction action,
  ) {
    final label = _tableActionLabels[action]!;
    final icon = _tableActionIcon(action);
    final color = _tableActionColor(action);
    final isDestructive = action == TableAction.cancelOrder;

    return SizedBox(
      width: double.infinity,
      child: isDestructive
          ? ElevatedButton.icon(
              onPressed: () => _handleTableAction(
                dialogContext,
                screenContext,
                restaurantRepo,
                table,
                action,
              ),
              icon: Icon(icon, size: 18),
              label: Text(label),
              style: ElevatedButton.styleFrom(
                backgroundColor: color,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            )
          : OutlinedButton.icon(
              onPressed: () => _handleTableAction(
                dialogContext,
                screenContext,
                restaurantRepo,
                table,
                action,
              ),
              icon: Icon(icon, size: 18, color: color),
              label: Text(label, style: TextStyle(color: color)),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: color),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
    );
  }

  /// تنفيذُ الكبسة. الموصولُ منها بمعالجٍ حقيقيٍّ هو ما كان موجوداً قبل
  /// هذه المهمّة (الفتح، الإضافة، النقل، الدمج، التقسيم، الحجز، الإغلاق)؛
  /// والباقي (الدفع، تغييرُ الحالة، الإلغاء، الطباعة، السجل) يُوصَل
  /// بـ`TableSessionService` أو شاشة السجل في مهماتٍ لاحقة (١١، ١٢) — يظهر
  /// بحالته وشكله الصحيحين الآن، ولا ينفّذ شيئاً بعد.
  Future<void> _handleTableAction(
    BuildContext dialogContext,
    BuildContext screenContext,
    IRestaurantRepository restaurantRepo,
    RestaurantTable table,
    TableAction action,
  ) async {
    Navigator.pop(dialogContext);
    switch (action) {
      case TableAction.open:
        _confirmOpenTable(restaurantRepo, table);
        break;
      case TableAction.addItems:
        if (table.status == TableStatus.paid) {
          // الإضافةُ بعد الدفع تفتح طلباً جديداً — لا تُعدّل فاتورةً رُحِّلت.
          _confirmOpenTable(restaurantRepo, table);
        } else if (screenContext.mounted) {
          Navigator.push(
            screenContext,
            MaterialPageRoute(
              builder: (_) => TablePosScreen(
                tableId: table.id,
                tableName: table.name,
              ),
            ),
          );
        }
        break;
      case TableAction.transfer:
        _handleTransferOrder(screenContext, restaurantRepo, table);
        break;
      case TableAction.merge:
        final order = await restaurantRepo.getActiveOrderForTable(table.id);
        if (!screenContext.mounted) return;
        if (order != null) {
          _onMergeTable(restaurantRepo, table, order);
        } else {
          AppToast.show(screenContext, 'لا يوجد طلبٌ لدمجه', type: ToastType.warning);
        }
        break;
      case TableAction.splitBill:
        _handleSplitTable(screenContext, restaurantRepo, table);
        break;
      case TableAction.reserve:
        _showReservationDialog(screenContext, restaurantRepo, table);
        break;
      case TableAction.closeTable:
        final order = await restaurantRepo.getActiveOrderForTable(table.id);
        if (!screenContext.mounted) return;
        if (order != null) {
          await _closeTable(restaurantRepo, table, order);
        } else {
          AppToast.show(screenContext, 'لا يوجد طلبٌ لإغلاقه', type: ToastType.warning);
        }
        break;
      case TableAction.log:
        _showTableLog(screenContext, table);
        break;
      case TableAction.printBill:
      case TableAction.pay:
      case TableAction.changeStatus:
      case TableAction.cancelOrder:
        if (screenContext.mounted) {
          AppToast.show(screenContext, 'هذه الميزةُ قيدُ الإنجاز', type: ToastType.info);
        }
        break;
    }
  }

  /// سجلُّ الطاولة — استعلامٌ على `ActivityLogs` المسلسَل بالهاش (ICR-03)
  /// مصفًّى على هذه الطاولة (T11)، لا جدولٌ جديد.
  void _showTableLog(BuildContext context, RestaurantTable table) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: TableLogSheet(tableId: table.id, tableName: table.name),
      ),
    );
  }

  /// Show options for reserved table (seat guests or cancel)
  void _showReservedTableOptions(
    BuildContext context,
    IRestaurantRepository restaurantRepo,
    RestaurantTable table,
  ) async {
    final reservation =
        await restaurantRepo.getActiveReservationForTable(table.id);
    if (reservation == null || !context.mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Row(
            children: [
              const Icon(PhosphorIconsBold.calendarCheck, color: Colors.orange),
              const SizedBox(width: 8),
              Text('${table.name} - محجوزة'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildInfoRow('العميل', reservation.customerName),
              if (reservation.customerPhone != null)
                _buildInfoRow('الهاتف', reservation.customerPhone!),
              _buildInfoRow('الوقت', _formatTime(reservation.reservationTime)),
              _buildInfoRow('عدد الأشخاص', '${reservation.partySize}'),
              if (reservation.notes != null && reservation.notes!.isNotEmpty)
                _buildInfoRow('ملاحظات', reservation.notes!),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إغلاق'),
            ),
            OutlinedButton.icon(
              onPressed: () async {
                Navigator.pop(ctx);
                await restaurantRepo.cancelReservation(reservation.id);
                final user = ref.read(authProvider).user;
                final activityLogRepo = ref.read(activityLogRepositoryProvider);
                await activityLogRepo.logActivity(
                  userId: user?.id,
                  userName: user?.displayName ?? 'مجهول',
                  action: 'cancel_reservation',
                  entityType: 'reservation',
                  entityId: reservation.id,
                  description:
                      'إلغاء حجز: ${reservation.customerName} - ${table.name}',
                );
                if (context.mounted) {
                  AppToast.show(
                    context,
                    'تم إلغاء الحجز',
                    type: ToastType.warning,
                  );
                }
              },
              icon: const Icon(PhosphorIconsBold.x, size: 18),
              label: const Text('إلغاء الحجز'),
              style: OutlinedButton.styleFrom(foregroundColor: AppColors.error),
            ),
            ElevatedButton.icon(
              onPressed: () async {
                Navigator.pop(ctx);
                final authState = ref.read(authProvider);
                await restaurantRepo.seatReservation(
                  reservation.id,
                  userId: authState.user?.id,
                );
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
              icon: const Icon(PhosphorIconsBold.users, size: 18),
              label: const Text('استقبال الضيوف'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.success,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text('$label: ', style: const TextStyle(color: AppColors.textMuted)),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime dateTime) {
    final hour = dateTime.hour.toString().padLeft(2, '0');
    final minute = dateTime.minute.toString().padLeft(2, '0');
    return '${dateTime.day}/${dateTime.month} - $hour:$minute';
  }

  /// Show dialog to create a new reservation
  void _showReservationDialog(
    BuildContext context,
    IRestaurantRepository restaurantRepo,
    RestaurantTable table,
  ) {
    final nameController = TextEditingController();
    final phoneController = TextEditingController();
    final notesController = TextEditingController();
    int partySize = table.capacity;
    DateTime reservationTime = DateTime.now().add(const Duration(hours: 1));
    bool saving = false;

    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: StatefulBuilder(
          builder: (ctx, setDialogState) => AlertDialog(
            title: Row(
              children: [
                const Icon(
                  PhosphorIconsBold.calendarPlus,
                  color: Colors.orange,
                ),
                const SizedBox(width: 8),
                Text('حجز ${table.name}'),
              ],
            ),
            content: SizedBox(
              width: 350,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(
                        labelText: 'اسم العميل *',
                        prefixIcon: Icon(PhosphorIconsBold.user),
                      ),
                      autofocus: true,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: phoneController,
                      decoration: const InputDecoration(
                        labelText: 'رقم الهاتف',
                        prefixIcon: Icon(PhosphorIconsBold.phone),
                      ),
                      keyboardType: TextInputType.phone,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: () async {
                              final date = await showDatePicker(
                                context: context,
                                initialDate: reservationTime,
                                firstDate: DateTime.now(),
                                lastDate: DateTime.now().add(
                                  const Duration(days: 30),
                                ),
                              );
                              if (date != null) {
                                setDialogState(() {
                                  reservationTime = DateTime(
                                    date.year,
                                    date.month,
                                    date.day,
                                    reservationTime.hour,
                                    reservationTime.minute,
                                  );
                                });
                              }
                            },
                            child: InputDecorator(
                              decoration: const InputDecoration(
                                labelText: 'التاريخ',
                                prefixIcon: Icon(PhosphorIconsBold.calendar),
                              ),
                              child: Text(
                                '${reservationTime.day}/${reservationTime.month}/${reservationTime.year}',
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: InkWell(
                            onTap: () async {
                              final time = await showTimePicker(
                                context: context,
                                initialTime: TimeOfDay.fromDateTime(
                                  reservationTime,
                                ),
                              );
                              if (time != null) {
                                setDialogState(() {
                                  reservationTime = DateTime(
                                    reservationTime.year,
                                    reservationTime.month,
                                    reservationTime.day,
                                    time.hour,
                                    time.minute,
                                  );
                                });
                              }
                            },
                            child: InputDecorator(
                              decoration: const InputDecoration(
                                labelText: 'الوقت',
                                prefixIcon: Icon(PhosphorIconsBold.clock),
                              ),
                              child: Text(
                                '${reservationTime.hour.toString().padLeft(2, '0')}:${reservationTime.minute.toString().padLeft(2, '0')}',
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Text('عدد الأشخاص: '),
                        IconButton(
                          onPressed: partySize > 1
                              ? () => setDialogState(() => partySize--)
                              : null,
                          icon: const Icon(PhosphorIconsBold.minus),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '$partySize',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => setDialogState(() => partySize++),
                          icon: const Icon(PhosphorIconsBold.plus),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: notesController,
                      decoration: const InputDecoration(
                        labelText: 'ملاحظات',
                        prefixIcon: Icon(PhosphorIconsBold.notepad),
                      ),
                      maxLines: 2,
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('إلغاء'),
              ),
              ElevatedButton.icon(
                onPressed: saving ? null : () async {
                  if (nameController.text.trim().isEmpty) {
                    AppToast.show(
                      ctx,
                      'يرجى إدخال اسم العميل',
                      type: ToastType.warning,
                    );
                    return;
                  }
                  setDialogState(() => saving = true);
                  try {
                    await restaurantRepo.createReservation(
                      tableId: table.id,
                      customerName: nameController.text.trim(),
                      customerPhone: phoneController.text.trim().isNotEmpty
                          ? phoneController.text.trim()
                          : null,
                      reservationTime: reservationTime,
                      partySize: partySize,
                      notes: notesController.text.trim().isNotEmpty
                          ? notesController.text.trim()
                          : null,
                    );
                    final user = ref.read(authProvider).user;
                    final activityLogRepo =
                        ref.read(activityLogRepositoryProvider);
                    await activityLogRepo.logActivity(
                      userId: user?.id,
                      userName: user?.displayName ?? 'مجهول',
                      action: 'add_reservation',
                      entityType: 'reservation',
                      description:
                          'حجز ${table.name}: ${nameController.text.trim()} ($partySize أشخاص)',
                    );

                    if (ctx.mounted) {
                      Navigator.pop(ctx);
                      AppToast.show(
                        context,
                        'تم حجز ${table.name} بنجاح',
                        type: ToastType.success,
                      );
                    }
                  } catch (e) {
                    setDialogState(() => saving = false);
                    if (ctx.mounted) {
                      AppToast.show(ctx, 'خطأ: $e', type: ToastType.error);
                    }
                  }
                },
                icon: const Icon(PhosphorIconsBold.calendarCheck, size: 18),
                label: const Text('تأكيد الحجز'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
