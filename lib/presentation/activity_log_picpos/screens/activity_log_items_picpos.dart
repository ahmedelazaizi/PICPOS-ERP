part of 'activity_log_picpos_screen.dart';

// ═══════════════════════════════════════════════════════════════════════════
// ACTIVITY LOG (PicPos fork) — Log Item Builder, Details Dialog, Export to
// Excel
//
// Copied verbatim from `lib/presentation/screens/activity_log/activity_log_items.dart`
// (`_ActivityLogItemsMixin`). Only the `part of` target, the mixin name,
// and the `ConsumerState<...>` type parameter changed — see the copy-trap
// note in `activity_log_picpos_screen.dart`. Any LOGICAL bug fix belongs in
// the UralCash source FIRST, then gets patched here — never the other way
// around. Never copy from D:\URAL-ERP.
// ═══════════════════════════════════════════════════════════════════════════

mixin _ActivityLogItemsPicposMixin on ConsumerState<ActivityLogPicposScreen> {
  // Abstract — provided by the shell
  Map<String, String> get actionLabels;
  Map<String, String> get entityLabels;
  List<ActivityLog> get logs;

  /// أيقونةُ الإجراء ولونُه.
  ///
  /// استُخرجت من جسم `buildLogItem` **بلا تعديلِ حالةٍ واحدة** ليستعملها
  /// جدولُ التصميم كذلك. الشاشةُ تعرض عرضَين (قائمةً وزمنيّاً) وثالثاً الآن،
  /// ونسخُ مئتَي سطرِ `switch` مرّةً ثانيةً كان يضمن انحرافَ اللونَين بأوّل
  /// إجراءٍ يُضاف.
  ({IconData icon, Color color}) actionVisual(String action) {
    IconData icon;
    Color iconColor;

    switch (action) {
      case 'sale':
        icon = PhosphorIconsBold.shoppingCart;
        iconColor = AppColors.success;
        break;
      case 'refund':
      case 'return':
      case 'cancel_return':
        icon = PhosphorIconsBold.arrowCounterClockwise;
        iconColor = AppColors.warning;
        break;
      case 'void':
      case 'delete_invoice':
        icon = PhosphorIconsBold.fileX;
        iconColor = AppColors.error;
        break;
      case 'discount':
      case 'pos_discount':
        icon = PhosphorIconsBold.percent;
        iconColor = AppColors.warning;
        break;
      case 'expense':
      case 'delete_expense':
        icon = PhosphorIconsBold.money;
        iconColor = AppColors.error;
        break;
      case 'receipt':
        icon = PhosphorIconsBold.receipt;
        iconColor = AppColors.success;
        break;
      case 'login':
      case 'logout':
      case 'admin_elevation':
        icon = PhosphorIconsBold.user;
        iconColor = AppColors.info;
        break;
      case 'delete_product':
      case 'product_delete':
      case 'delete_customer':
      case 'delete_supplier':
        icon = PhosphorIconsBold.trash;
        iconColor = AppColors.error;
        break;
      case 'price_override':
      case 'product_edit':
      case 'update_customer':
      case 'update_supplier':
        icon = PhosphorIconsBold.pencil;
        iconColor = AppColors.warning;
        break;
      case 'add_product':
      case 'add_customer':
      case 'add_supplier':
      case 'add_purchase':
        icon = PhosphorIconsBold.plus;
        iconColor = AppColors.success;
        break;
      case 'cart_add':
      case 'cart_remove':
      case 'cart_clear':
        icon = PhosphorIconsBold.shoppingCartSimple;
        iconColor = AppColors.info;
        break;
      case 'hold_order':
      case 'order_suspend':
      case 'retrieve_held_order':
      case 'delete_held_order':
        icon = PhosphorIconsBold.pause;
        iconColor = AppColors.warning;
        break;
      case 'open_drawer':
      case 'cash_drawer_open':
        icon = PhosphorIconsBold.lockOpen;
        iconColor = AppColors.warning;
        break;
      case 'settings_change':
        icon = PhosphorIconsBold.gear;
        iconColor = AppColors.textMuted;
        break;
      case 'price_edit':
        icon = PhosphorIconsBold.currencyDollar;
        iconColor = AppColors.warning;
        break;
      case 'pos_item_qty_change':
        icon = PhosphorIconsBold.scales;
        iconColor = AppColors.info;
        break;
      case 'shift_close':
      case 'daily_closing':
        icon = PhosphorIconsBold.clockCountdown;
        iconColor = AppColors.info;
        break;
      case 'safe_adjustment':
        icon = PhosphorIconsBold.vault;
        iconColor = AppColors.warning;
        break;
      case 'offer_add':
      case 'offer_edit':
      case 'offer_delete':
      case 'offer_toggle':
        icon = PhosphorIconsBold.tag;
        iconColor = AppColors.warning;
        break;
      case 'stock_adjust':
        icon = PhosphorIconsBold.warehouse;
        iconColor = AppColors.info;
        break;
      case 'category_add':
      case 'category_edit':
      case 'category_delete':
        icon = PhosphorIconsBold.folders;
        iconColor = AppColors.success;
        break;
      case 'user_create':
      case 'user_edit':
      case 'user_activate':
      case 'user_deactivate':
      case 'user_lock':
      case 'user_unlock':
      case 'user_reset_password':
      case 'perm_change':
        icon = PhosphorIconsBold.userGear;
        iconColor = AppColors.info;
        break;
      case 'add_section':
      case 'update_section':
      case 'delete_section':
      case 'add_table':
      case 'update_table':
      case 'delete_table':
        icon = PhosphorIconsBold.table;
        iconColor = AppColors.primary;
        break;
      case 'add_reservation':
      case 'cancel_reservation':
        icon = PhosphorIconsBold.calendarCheck;
        iconColor = AppColors.warning;
        break;
      case 'add_delivery_company':
      case 'update_delivery_company':
      case 'delete_delivery_company':
        icon = PhosphorIconsBold.buildings;
        iconColor = AppColors.info;
        break;
      case 'add_courier':
      case 'update_courier':
      case 'delete_courier':
        icon = PhosphorIconsBold.moped;
        iconColor = AppColors.success;
        break;
      case 'add_printer':
      case 'update_printer':
      case 'delete_printer':
        icon = PhosphorIconsBold.printer;
        iconColor = AppColors.info;
        break;
      case 'add_employee':
      case 'update_employee':
        icon = PhosphorIconsBold.userPlus;
        iconColor = AppColors.primary;
        break;
      case 'employee_advance':
      case 'employee_deduction':
        icon = PhosphorIconsBold.currencyCircleDollar;
        iconColor = AppColors.error;
        break;
      case 'employee_checkin':
        icon = PhosphorIconsBold.signIn;
        iconColor = AppColors.success;
        break;
      case 'employee_checkout':
        icon = PhosphorIconsBold.signOut;
        iconColor = AppColors.error;
        break;
      case 'salary_payment':
        icon = PhosphorIconsBold.money;
        iconColor = AppColors.success;
        break;
      case 'update_role_permissions':
      case 'add_role':
      case 'delete_role':
        icon = PhosphorIconsBold.shieldCheck;
        iconColor = AppColors.warning;
        break;
      case 'create_invoice_template':
      case 'update_invoice_template':
      case 'delete_invoice_template':
      case 'import_invoice_template':
        icon = PhosphorIconsBold.fileText;
        iconColor = AppColors.primary;
        break;
      default:
        icon = PhosphorIconsBold.note;
        iconColor = AppColors.textMuted;
    }
    return (icon: icon, color: iconColor);
  }

  Widget buildLogItem(ActivityLog log) {
    final actionLabel = actionLabels[log.action] ?? log.action;
    final entityLabel = entityLabels[log.entityType] ?? log.entityType;
    final visual = actionVisual(log.action);
    final icon = visual.icon;
    final iconColor = visual.color;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: iconColor, size: 20),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                actionLabel,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: iconColor,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(log.description, overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
        subtitle: Row(
          children: [
            Text(
              log.userName,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(width: 8),
            const Text('•', style: TextStyle(color: AppColors.textMuted)),
            const SizedBox(width: 8),
            Text(
              entityLabel,
              style: const TextStyle(color: AppColors.textMuted),
            ),
            if (log.amount != null) ...[
              const SizedBox(width: 8),
              const Text('•', style: TextStyle(color: AppColors.textMuted)),
              const SizedBox(width: 8),
              Text(
                '${log.amount!.toStringAsFixed(AppConstants.decimalPlaces)} د.أ',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ],
        ),
        trailing: Text(
          '${log.createdAt.hour.toString().padLeft(2, '0')}:${log.createdAt.minute.toString().padLeft(2, '0')}\n${log.createdAt.day}/${log.createdAt.month}',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
        ),
        onTap: () => showLogDetails(log),
      ),
    );
  }

  void showLogDetails(ActivityLog log) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('تفاصيل العملية #${log.id}'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _detailRow('المستخدم', log.userName),
              _detailRow('العملية', actionLabels[log.action] ?? log.action),
              _detailRow(
                'النوع',
                entityLabels[log.entityType] ?? log.entityType,
              ),
              _detailRow('الوصف', log.description),
              if (log.oldValue != null)
                _detailRow('القيمة السابقة', log.oldValue!),
              if (log.newValue != null)
                _detailRow('القيمة الجديدة', log.newValue!),
              if (log.amount != null)
                _detailRow('المبلغ', '${log.amount!.toStringAsFixed(AppConstants.decimalPlaces)} د.أ'),
              _detailRow(
                'التاريخ',
                '${log.createdAt.day}/${log.createdAt.month}/${log.createdAt.year} ${log.createdAt.hour}:${log.createdAt.minute.toString().padLeft(2, '0')}',
              ),
              if (log.entityId != null)
                FieldAuditHistoryWidget(
                  entityType: log.entityType,
                  entityId: log.entityId!,
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  Future<void> exportToExcel() async {
    try {
      final excel = xls.Excel.createExcel();
      final sheet = excel['سجل العمليات'];
      if (excel.sheets.containsKey('Sheet1')) {
        excel.delete('Sheet1');
      }

      // Headers
      final headers = [
        '#',
        'التاريخ',
        'الوقت',
        'المستخدم',
        'العملية',
        'النوع',
        'الوصف',
        'المبلغ',
        'القيمة السابقة',
        'القيمة الجديدة',
      ];
      for (var i = 0; i < headers.length; i++) {
        sheet
            .cell(xls.CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0))
            .value = xls.TextCellValue(
          headers[i],
        );
      }

      // Data rows
      for (var i = 0; i < logs.length; i++) {
        final log = logs[i];
        final row = i + 1;
        sheet
            .cell(xls.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row))
            .value = xls.IntCellValue(
          log.id,
        );
        sheet
            .cell(xls.CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row))
            .value = xls.TextCellValue(
          '${log.createdAt.day}/${log.createdAt.month}/${log.createdAt.year}',
        );
        sheet
            .cell(xls.CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: row))
            .value = xls.TextCellValue(
          '${log.createdAt.hour.toString().padLeft(2, '0')}:${log.createdAt.minute.toString().padLeft(2, '0')}',
        );
        sheet
            .cell(xls.CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: row))
            .value = xls.TextCellValue(
          log.userName,
        );
        sheet
            .cell(xls.CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: row))
            .value = xls.TextCellValue(
          actionLabels[log.action] ?? log.action,
        );
        sheet
            .cell(xls.CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: row))
            .value = xls.TextCellValue(
          entityLabels[log.entityType] ?? log.entityType,
        );
        sheet
            .cell(xls.CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: row))
            .value = xls.TextCellValue(
          log.description,
        );
        sheet
            .cell(xls.CellIndex.indexByColumnRow(columnIndex: 7, rowIndex: row))
            .value = log.amount != null
            ? xls.DoubleCellValue(log.amount!)
            : xls.TextCellValue('');
        sheet
            .cell(xls.CellIndex.indexByColumnRow(columnIndex: 8, rowIndex: row))
            .value = xls.TextCellValue(
          log.oldValue ?? '',
        );
        sheet
            .cell(xls.CellIndex.indexByColumnRow(columnIndex: 9, rowIndex: row))
            .value = xls.TextCellValue(
          log.newValue ?? '',
        );
      }

      // Save to Desktop
      final bytes = excel.encode();
      if (bytes == null) return;

      final now = DateTime.now();
      final fileName = 'activity_log_${now.day}-${now.month}-${now.year}.xlsx';
      final desktopPath = '${Platform.environment['USERPROFILE']}\\Desktop';
      final file = File('$desktopPath\\$fileName');
      await file.writeAsBytes(bytes);

      if (mounted) {
        AppToast.show(
          context,
          'تم حفظ الملف على سطح المكتب: $fileName',
          type: ToastType.success,
        );
      }
    } catch (e) {
      if (mounted) {
        AppToast.show(context, 'خطأ في التصدير: $e', type: ToastType.error);
      }
    }
  }
}
