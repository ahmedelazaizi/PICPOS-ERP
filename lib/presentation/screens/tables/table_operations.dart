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
  Future<void> _confirmDeleteTable(
    IRestaurantRepository restaurantRepo,
    RestaurantTable table,
  );
  void _showEditTableDialog(
    BuildContext context,
    IRestaurantRepository restaurantRepo,
    RestaurantTable table,
  );
  void _handleSplitTable(
    BuildContext context,
    IRestaurantRepository restaurantRepo,
    RestaurantTable table,
  ) async {
    final allTables = await restaurantRepo.getAllTables();

    if (!context.mounted) return;

    final otherTables = allTables
        .where((t) => t.isActive && t.id != table.id)
        .toList();

    if (otherTables.isEmpty) {
      AppToast.show(
        context,
        'لا توجد طاولات أخرى متاحة للتقسيم إليها',
        type: ToastType.warning,
      );
      return;
    }

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => SplitTableDialog(
        sourceTable: table,
        targetTables: otherTables.cast<RestaurantTable>(),
        restaurantRepo: restaurantRepo,
      ),
    );

    if (result != null && mounted) {
      final targetTable = result['target'] as RestaurantTable;
      final itemQuantities = result['itemQuantities'] as Map<int, double>;

      try {
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
              action: 'split_order',
              entityType: 'table',
              entityId: table.id,
              description:
                  'تقسيم أصناف من ${table.name} إلى ${targetTable.name}',
            );
          } catch (_) {}
          if (context.mounted) {
            AppToast.show(
              context,
              'تم تقسيم الطلب بنجاح إلى ${targetTable.name}',
              type: ToastType.success,
            );
          }
        }
      } catch (e) {
        if (context.mounted) {
          AppToast.show(
            context,
            'خطأ في تقسيم الطلب: $e',
            type: ToastType.error,
          );
        }
      }
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
          await restaurantRepo.transferTableOrder(table.id, targetTable.id);
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
        }

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
              description: transferAll
                  ? 'نقل طلب من ${table.name} إلى ${targetTable.name}'
                  : 'نقل ${itemIds.length} صنف من ${table.name} إلى ${targetTable.name}',
            );
          } catch (_) {}
          if (context.mounted) {
            AppToast.show(
              context,
              transferAll
                  ? 'تم نقل الطلب من ${table.name} إلى ${targetTable.name}'
                  : 'تم نقل ${itemIds.length} صنف من ${table.name} إلى ${targetTable.name}',
              type: ToastType.success,
            );
          }
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

  /// Show options for available table (open order or reserve)
  void _showTableOptions(
    BuildContext context,
    IRestaurantRepository restaurantRepo,
    RestaurantTable table,
  ) {
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
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Primary actions
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _confirmOpenTable(restaurantRepo, table);
                  },
                  icon: const Icon(PhosphorIconsBold.users, size: 18),
                  label: const Text('فتح طلب'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.success,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _showReservationDialog(context, restaurantRepo, table);
                  },
                  icon: const Icon(PhosphorIconsBold.calendarPlus, size: 18),
                  label: const Text('حجز'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.orange,
                    side: const BorderSide(color: Colors.orange),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Secondary actions row
              Row(
                children: [
                  Expanded(
                    child: TextButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        _showEditTableDialog(context, restaurantRepo, table);
                      },
                      icon: const Icon(PhosphorIconsBold.pencil, size: 16),
                      label: const Text('تعديل'),
                    ),
                  ),
                  Expanded(
                    child: TextButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        _confirmDeleteTable(restaurantRepo, table);
                      },
                      icon: const Icon(PhosphorIconsBold.trash, size: 16, color: AppColors.error),
                      label: const Text('حذف', style: TextStyle(color: AppColors.error)),
                    ),
                  ),
                ],
              ),
            ],
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
