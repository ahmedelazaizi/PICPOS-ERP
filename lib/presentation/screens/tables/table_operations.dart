part of '../tables_screen.dart';

// ═══════════════════════════════════════════════════════════════════════════
// TABLE OPERATIONS — Split, Transfer, Options, Reservations
// ═══════════════════════════════════════════════════════════════════════════

/// هل يملك حاملُ هذه الصلاحيات تنفيذَ فعلِ طاولةٍ يلزمه [permission]؟
///
/// دالّةٌ خالصةٌ مُختبَرة — نفسُ نمط `canPrintPosWorkOrder` المجاور. مديرُ
/// النظام يمرّ دوماً كما في كلّ فحصٍ صريحٍ آخر في هذا المستودع.
@visibleForTesting
bool hasTableActionPermission(List<String> permissions, String permission) {
  final isAdmin =
      permissions.contains('system_admin') || permissions.contains('*');
  return isAdmin || permissions.contains(permission);
}

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

          // `partialTransferOrder` تشترط ألّا يكون دُفع من الطلب شيء —
          // نفسُ حارس النقل الكامل — وتكتب سطرَ السجلِّ بنفسها.
          final user = ref.read(authProvider).user;
          await ref.read(tableSessionServiceProvider).partialTransferOrder(
                fromTableId: table.id,
                toTableId: targetTable.id,
                itemQuantities: itemQuantities,
                userId: user?.id,
                userName: user?.displayName ?? 'مجهول',
              );
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

  /// Show the table's actions menu — one row per `TableAction`, derived
  /// من `actionsForStatus(table.status)` لا شروطٌ متناثرة. غيابُ «الدفع»
  /// عن طاولةٍ فارغة أو «النقل» عن طاولةٍ بلا طلبٍ نتيجةٌ تلقائيةٌ للقائمة
  /// المُشتقّة، لا شرطٍ يُكتَب هنا فيُنسى في نسخةٍ تالية.
  ///
  /// بناءُ الكبسات نفسُه في `TableActionsMenu` — ودجتٌ مستقلّةٌ تُختبَر بلا
  /// تركيب هذه الشاشة.
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
          content: SizedBox(
            width: 320,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TableActionsMenu(
                    status: table.status,
                    onSelected: (action) => _handleTableAction(
                      ctx,
                      context,
                      restaurantRepo,
                      table,
                      action,
                    ),
                  ),
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

  /// تنفيذُ الكبسة. كلُّ كبسةٍ تعرضها القائمةُ موصولةٌ بمعالجٍ حقيقيّ —
  /// القائمةُ لا تُعلن ما لا تفعل.
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
        } else {
          _openTablePos(screenContext, table);
        }
        break;
      case TableAction.pay:
        // «الدفع» هو مسارُ التحصيل القائم نفسُه: شاشةُ الطاولة تحمّل أصنافَ
        // الطلب ثم «تحصيل الحساب» — وهناك يقع الفحصُ القبليُّ الذي يقارن
        // المشحونَ بالمستحقّ قبل ترحيل أيّ فاتورة.
        _openTablePos(screenContext, table);
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
        await _handlePrintBill(screenContext, restaurantRepo, table);
        break;
      case TableAction.changeStatus:
        await _handleChangeStatus(screenContext, table);
        break;
      case TableAction.cancelOrder:
        await _handleCancelOrder(screenContext, table);
        break;
    }
  }

  void _openTablePos(BuildContext screenContext, RestaurantTable table) {
    if (!screenContext.mounted) return;
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

  /// فحصُ صلاحيةٍ صريحٌ للأفعال التي لا زرَّ واحدَ لها يُلفّ بـ
  /// `PermissionGuard` — نفسُ نمط `ensurePosWorkOrderPermission` في هذا
  /// الملفّ نفسِه، ونفسُ سببه: المعالجُ يُنادى من قائمةٍ مبنيّةٍ من دالّةٍ
  /// خالصة، فالحراسةُ تعيش عند التنفيذ لا عند الرسم.
  Future<bool> _ensureTablePermission(
    BuildContext screenContext,
    String permission,
    String actionName,
  ) async {
    final permissions =
        ref.read(currentUserPermissionsProvider).asData?.value ??
            const <String>[];
    if (hasTableActionPermission(permissions, permission)) return true;
    if (screenContext.mounted) {
      AppToast.show(screenContext, 'ليس لديك صلاحية $actionName',
          type: ToastType.error);
    }
    return false;
  }

  /// إلغاءُ الطلب — هدمٌ يمحو طلباً حيّاً، فيُؤكَّد صراحةً ويلزمه
  /// `tables_cancel`. الخدمةُ ترفض إلغاءَ طلبٍ دُفع منه شيء وتكتب سطرَ
  /// السجلِّ بنفسها.
  Future<void> _handleCancelOrder(
    BuildContext screenContext,
    RestaurantTable table,
  ) async {
    if (!await _ensureTablePermission(
        screenContext, PermissionCodes.tablesCancel, 'إلغاء طلب الطاولة')) {
      return;
    }
    if (!screenContext.mounted) return;

    final confirmed = await showDialog<bool>(
          context: screenContext,
          builder: (ctx) => Directionality(
            textDirection: TextDirection.rtl,
            child: AlertDialog(
              title: const Row(
                children: [
                  Icon(PhosphorIconsBold.warning, color: AppColors.error),
                  SizedBox(width: 8),
                  Text('إلغاء الطلب'),
                ],
              ),
              content: Text(
                'سيُلغى طلبُ ${table.name} بالكامل وتعود الطاولةُ متاحة. '
                'هذا هدمٌ لا رجعةَ فيه — ولا يُقبل إن كان قد دُفع من الطلب '
                'شيء.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('تراجع'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.error,
                  ),
                  child: const Text('إلغاء الطلب'),
                ),
              ],
            ),
          ),
        ) ??
        false;
    if (!confirmed || !mounted) return;

    try {
      final user = ref.read(authProvider).user;
      await ref.read(tableSessionServiceProvider).cancelOrder(
            tableId: table.id,
            userId: user?.id,
            userName: user?.displayName ?? 'مجهول',
          );
      if (screenContext.mounted) {
        AppToast.show(screenContext, 'تم إلغاء طلب ${table.name}',
            type: ToastType.warning);
      }
    } catch (e) {
      if (screenContext.mounted) {
        AppToast.show(screenContext, 'تعذّر إلغاءُ الطلب: $e',
            type: ToastType.error);
      }
    }
  }

  /// تغييرُ الحالة يدويّاً — بين 🟢 و⚪ فقط، وهو ما تفرضه الخدمةُ نفسُها.
  Future<void> _handleChangeStatus(
    BuildContext screenContext,
    RestaurantTable table,
  ) async {
    if (!await _ensureTablePermission(
        screenContext, PermissionCodes.tablesManage, 'تغيير حالة الطاولة')) {
      return;
    }
    if (!screenContext.mounted) return;

    final target = table.status == TableStatus.outOfService
        ? TableStatus.available
        : TableStatus.outOfService;
    final targetLabel =
        target == TableStatus.available ? 'متاحة' : 'خارج الخدمة';

    final confirmed = await showDialog<bool>(
          context: screenContext,
          builder: (ctx) => Directionality(
            textDirection: TextDirection.rtl,
            child: AlertDialog(
              title: Text('تغيير حالة ${table.name}'),
              content: Text('ستصبح الطاولةُ «$targetLabel».'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('إلغاء'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: Text(targetLabel),
                ),
              ],
            ),
          ),
        ) ??
        false;
    if (!confirmed || !mounted) return;

    try {
      final user = ref.read(authProvider).user;
      await ref.read(tableSessionServiceProvider).setTableStatus(
            tableId: table.id,
            status: target,
            userId: user?.id,
            userName: user?.displayName ?? 'مجهول',
          );
      if (screenContext.mounted) {
        AppToast.show(screenContext, 'صارت ${table.name} «$targetLabel»',
            type: ToastType.success);
      }
    } catch (e) {
      if (screenContext.mounted) {
        AppToast.show(screenContext, 'تعذّر تغييرُ الحالة: $e',
            type: ToastType.error);
      }
    }
  }

  /// طباعةُ فاتورةِ ما قبل الدفع. الطلبُ يصير `bill_requested` (صفةٌ للطلب
  /// لا للطاولة)، والطاولةُ تبقى على حالتها. وعلى طاولةٍ 🟠 هي إعادةُ
  /// طباعةٍ فحسب فلا تُغيَّر حالةُ الطلب.
  Future<void> _handlePrintBill(
    BuildContext screenContext,
    IRestaurantRepository restaurantRepo,
    RestaurantTable table,
  ) async {
    if (!await _ensureTablePermission(
        screenContext, PermissionCodes.tablesPrintBill, 'طباعة فاتورة الطاولة')) {
      return;
    }

    final order = await restaurantRepo.getActiveOrderForTable(table.id);
    if (order == null) {
      if (screenContext.mounted) {
        AppToast.show(screenContext, 'لا يوجد طلبٌ لطباعة فاتورته',
            type: ToastType.warning);
      }
      return;
    }
    final items = await restaurantRepo.getTableOrderItems(order.id);
    if (items.isEmpty) {
      if (screenContext.mounted) {
        AppToast.show(screenContext, 'لا توجد أصنافٌ في الطلب',
            type: ToastType.warning);
      }
      return;
    }

    try {
      final session = ref.read(tableSessionServiceProvider);
      final user = ref.read(authProvider).user;
      final totals = await session.totalsFor(order.id);
      await session.requestBill(
        orderId: order.id,
        userId: user?.id,
        userName: user?.displayName ?? 'مجهول',
      );

      final productRepo = ref.read(productRepositoryProvider);
      final invoiceItems = <InvoiceItem>[];
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

      // الأرقامُ الثلاثةُ من `TableOrderTotals` وحدَها، لا حسابَ هنا.
      // و`total` **شاملٌ للضريبة** بالضرورة: مولِّدُ الإيصال يشتقّ المجموعَ
      // قبل الضريبة عكسيّاً (`subtotal = total + discount - tax`)، فتمريرُ
      // ضريبةٍ فوق إجماليٍّ لا يحويها يطبع مجموعاً أنقصَ من الحقيقة بمقدارها
      // ثم إجماليّاً لا يساوي ما سيُدفَع.
      await InvoiceGenerator.printThermalReceipt(
        invoiceNumber: 'T${table.id}-${order.id}',
        date: DateTime.now(),
        items: invoiceItems,
        total: totals.total,
        paid: order.paidAmount,
        change: 0,
        discount: totals.discount,
        tax: totals.taxAmount,
        customerName: table.name,
        employeeName: user?.displayName,
        notes: 'فاتورةٌ مبدئيّةٌ — ليست إيصالَ سداد',
        db: ref.read(databaseProvider),
      );

      if (screenContext.mounted) {
        AppToast.show(screenContext, 'تمت طباعةُ فاتورة ${table.name}',
            type: ToastType.success);
      }
    } catch (e) {
      if (screenContext.mounted) {
        AppToast.show(screenContext, 'تعذّرت طباعةُ الفاتورة: $e',
            type: ToastType.error);
      }
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
                // حضورُ الحجز فتحُ طاولةٍ، فيلقط النسبةَ كما يلقطها زرُّ
                // الفتح — وإلّا وُلد طلبٌ لا يقبل تفعيلَ الضريبة.
                await restaurantRepo.seatReservation(
                  reservation.id,
                  userId: authState.user?.id,
                  taxRate: ref.read(posDefaultTaxRateProvider).value ?? 0.16,
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
                    // نداءُ الخدمة لا المستودعِ مباشرةً: `reserveTable` تكتب
                    // صفَّ الحجز **وتترك أثراً** في `ActivityLogs` (كان
                    // النداءُ القديمَ على `restaurantRepo.createReservation`
                    // يُنشئ الحجزَ بلا سطرِ سجلٍّ واحد). والمستخدمُ الحاليُّ
                    // يُمرَّر كما يفعل بقيّةُ أفعال هذا الملفّ.
                    final user = ref.read(authProvider).user;
                    await ref.read(tableSessionServiceProvider).reserveTable(
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
                          userId: user?.id,
                          userName: user?.displayName ?? 'مجهول',
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
