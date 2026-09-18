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

/// ⚠️ القيدُ معمَّمٌ على `T` لا مثبَّتٌ على `TablesScreen`: مضيفُ الأفعال
/// [TableActionsHost] يركّب هذه المخاليطَ نفسَها كي تُنادى من شاشةٍ ثانيةٍ
/// بلا نسخِ منطق. ولا سطرَ هنا يمسّ `widget` أصلاً (مقيسٌ: صفرُ مطابقاتٍ
/// لـ`widget.` في الملفّات الثلاثة)، فالتعميمُ لا يغيّر سلوكاً — يفتح الباب
/// فقط. و`T` يُستنتَج من صنف الحالة عند التركيب فلا تُكتب في أيِّ مستدعٍ.
///
/// ولا يصلح `on ConsumerState<ConsumerStatefulWidget>` مكانَه: صنفٌ لا يقدر
/// أن يحقّق `ConsumerState<TablesScreen>` و`ConsumerState<ConsumerStatefulWidget>`
/// معاً (`conflicting_generic_interfaces`) — جُرّب فسقط.
mixin _TableOrderDialogsMixin<T extends ConsumerStatefulWidget>
    on ConsumerState<T> {
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
    // محصورٌ بفروع المستخدم — وإلا ظهر موظفو الشركة كلُّها في منسدلة «مَن
    // يفتح الطاولة»، فيُسنَد الطلبُ لموظفِ فرعٍ آخر.
    //
    // ⚠️ و`// ignore: unused_element` فوق هذه الدالة **مضلّل**: التصريحُ في
    // `table_operations.dart` إعلانٌ مجرَّدٌ في mixin، والتنفيذُ هنا يُنادى
    // فعلاً من `table_operations.dart:226` عند التركيب.
    final scope = await ref.read(branchScopeProvider.future);
    final employeesList = await hrRepo.getAllEmployees(
      allowedBranchIds: scope.hasFullAccess ? null : scope.allowedBranchIds,
    );
    int? selectedEmployeeId =
        employeesList.isNotEmpty ? employeesList.first.id : null;
    // عددُ الأشخاص عمودٌ على الطلب منذ v154، وهو مقامُ «التقسيم بالتساوي».
    // كان لا يُسأل عنه فيبقى ١ دائماً، فتفتح شاشةُ التقسيم على خطأ «التقسيم
    // يحتاج دافعَين على الأقل». المبدئيُّ سعةُ الطاولة كما في نافذة الحجز.
    int guestCount = table.capacity > 0 ? table.capacity : 1;
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
                  Text(table.status == TableStatus.paid
                      ? 'حسابُ هذه الطاولة سُدِّد. سيُغلَق طلبُها المدفوع '
                          'ويُفتح طلبٌ جديدٌ بفاتورةٍ ثانية.'
                      : 'هل تريد فتح طلب جديد لهذه الطاولة؟'),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Text('عدد الأشخاص: '),
                      IconButton(
                        onPressed: guestCount > 1
                            ? () => setState(() => guestCount--)
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
                          '$guestCount',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => setState(() => guestCount++),
                        icon: const Icon(PhosphorIconsBold.plus),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
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
        // الفتحُ يمرّ بـ`TableSessionService` لا بالمستودع مباشرةً: هي التي
        // ترفض حالةً لا تُفتح، وتثبّت عددَ الأشخاص، وتكتب سطرَ السجل بنفسها
        // (فلا `logActivity` يدويٌّ بعدها). وعلى الطاولة 🟠 تُغلق الطلبَ
        // المسدَّدَ أوّلاً في المعاملة نفسِها — وإلا صار على الطاولة طلبان
        // حيّان و`getActiveOrderForTable` ترمي على كلّ قراءةٍ بعدها.
        final user = ref.read(authProvider).user;
        final session = ref.read(tableSessionServiceProvider);
        final userName = user?.displayName ?? 'مجهول';
        // نسبةُ الضريبة تُلقَط **هنا** لحظةَ الفتح وتُثبَّت على الطلب. الخدمةُ
        // لا تملك `ref` فتقرأ الإعداد بنفسها، والقارئُ هو من يمرّره. وتغييرُ
        // الإعداد بعد الفتح لا يمسّ هذا الطلب — الوجبةُ تمتدّ ساعةً وقد
        // عُرض الحسابُ على الضيف.
        final taxRate =
            ref.read(posDefaultTaxRateProvider).value ?? 0.16;
        if (table.status == TableStatus.paid) {
          await session.openNewOrderOnPaidTable(
            tableId: table.id,
            guestCount: guestCount,
            userId: user?.id,
            userName: userName,
            waiterId: selectedEmployeeId,
            taxRate: taxRate,
          );
        } else {
          await session.openTable(
            tableId: table.id,
            guestCount: guestCount,
            userId: user?.id,
            userName: userName,
            waiterId: selectedEmployeeId,
            taxRate: taxRate,
          );
        }

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
      } catch (e) {
        if (mounted) {
          AppToast.show(
            context,
            'تعذّر فتحُ ${table.name}: $e',
            type: ToastType.error,
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
      // `TableSessionService.closeTable` تكتب سطرَ السجلِّ بنفسها، وتشترط
      // اكتمالَ الدفعِ قبل الإغلاق — كانت هذه الدالّةُ تُغلق مباشرةً بلا
      // شرط.
      final user = ref.read(authProvider).user;
      await ref.read(tableSessionServiceProvider).closeTable(
            tableId: table.id,
            userId: user?.id,
            userName: user?.displayName ?? 'مجهول',
          );

      if (mounted) {
        AppToast.show(
          context,
          'تم إغلاق ${table.name} - الإجمالي: ${order.total.toStringAsFixed(AppConstants.decimalPlaces)}',
          type: ToastType.success,
        );
      }
    } catch (e) {
      if (mounted) {
        AppToast.show(
          context,
          'فشل إغلاق ${table.name}: $e',
          type: ToastType.error,
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
    unawaited(DiagnosticLogger.log('TABLE-MERGE',
        '7/ دخولُ _onMergeTable source=${sourceTable.id} order=${sourceOrder.id} busy=$_mergingTables'));
    if (_mergingTables) return;
    final allTables = await restaurantRepo.getAllTables();
    unawaited(DiagnosticLogger.log(
        'TABLE-MERGE', '8/ getAllTables أعادت ${allTables.length}'));
    final allOccupied = allTables
        .where((t) =>
            (t.status == 'occupied' || t.status == 'billing') &&
            t.id != sourceTable.id &&
            t.isActive)
        .toList();
    unawaited(DiagnosticLogger.log(
        'TABLE-MERGE', '9/ المشغولةُ غيرُ المصدر=${allOccupied.length}'));

    if (!mounted) return;

    if (allOccupied.isEmpty) {
      unawaited(DiagnosticLogger.log('TABLE-MERGE', '10/ لا طاولاتٍ — توقّف'));
      AppToast.show(
        context,
        'لا توجد طاولات مشغولة أخرى للدمج معها',
        type: ToastType.warning,
      );
      return;
    }

    unawaited(
        DiagnosticLogger.log('TABLE-MERGE', '10/ قبل فتح حوار الاختيار'));
    final targetTable = await showDialog<RestaurantTable>(
      context: context,
      builder: (ctx) => MergeTableDialog(
        sourceTable: sourceTable,
        otherOccupiedTables: allOccupied.cast<RestaurantTable>(),
        onMerge: (table) => Navigator.pop(ctx, table),
      ),
    );
    unawaited(DiagnosticLogger.log(
        'TABLE-MERGE', '11/ الحوارُ أُغلق target=${targetTable?.id}'));

    if (targetTable != null && mounted) {
      setState(() => _mergingTables = true);
      try {
        // `mergeOrders` تشترط ألّا يكون دُفع من أيٍّ من الطلبين شيء، وتكتب
        // سطرَ السجلِّ بنفسها — لا نداءَ يدويّاً بعدها.
        final user = ref.read(authProvider).user;
        unawaited(DiagnosticLogger.log('TABLE-MERGE',
            '12/ نداءُ mergeOrders ${sourceTable.id}→${targetTable.id}'));
        final outcome = await ref.read(tableSessionServiceProvider).mergeOrders(
              sourceTableId: sourceTable.id,
              targetTableId: targetTable.id,
              userId: user?.id,
              userName: user?.displayName ?? 'مجهول',
            );
        unawaited(DiagnosticLogger.log('TABLE-MERGE',
            '13/ mergeOrders تمّت droppedDiscount=${outcome.droppedDiscount}'));

        if (mounted) {
          // خصمُ الطاولة المصدر يسقط في الدمج — يجب أن يصل الكاشيرَ، لا أن
          // يضيع صامتاً.
          final discountNote = outcome.droppedDiscount
              ? ' — تنبيه: أُسقط خصمُ ${sourceTable.name} (${outcome.droppedDiscountLabel})'
              : '';
          AppToast.show(
            context,
            'تم دمج ${sourceTable.name} بنجاح مع ${targetTable.name}$discountNote',
            type: outcome.droppedDiscount
                ? ToastType.warning
                : ToastType.success,
          );
        }
      } catch (e, st) {
        unawaited(DiagnosticLogger.log('TABLE-MERGE',
            'E/ فشلٌ في mergeOrders: $e\n${st.toString().split('\n').take(12).join('\n')}'));
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
