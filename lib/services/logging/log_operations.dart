part of '../activity_logger.dart';

// ═══════════════════════════════════════════════════════════════════════════
// OPERATIONS — Offers, Delivery, Distribution, Restaurant Tables, Loyalty,
//              E-Invoice, HR, Branch, Settings, Invoice Design
// ═══════════════════════════════════════════════════════════════════════════

extension ActivityLoggerOperations on ActivityLogger {
  // ── Offers ──
  Future<void> logOfferAdd(int userId, String userName, String offerName, double price) {
    return log(userId: userId, userName: userName, action: 'offer_add', entityType: 'offer',
        description: 'إضافة عرض: $offerName بسعر ${price.toStringAsFixed(AppConstants.decimalPlaces)}', amount: price);
  }

  Future<void> logOfferEdit(int userId, String userName, String offerName) {
    return log(userId: userId, userName: userName, action: 'offer_edit', entityType: 'offer',
        description: 'تعديل عرض: $offerName');
  }

  Future<void> logOfferDelete(int userId, String userName, String offerName) {
    return log(userId: userId, userName: userName, action: 'offer_delete', entityType: 'offer',
        description: 'حذف عرض: $offerName');
  }

  Future<void> logOfferToggle(int userId, String userName, String offerName, bool isNowActive) {
    return log(userId: userId, userName: userName, action: 'offer_toggle', entityType: 'offer',
        description: '${isNowActive ? "تفعيل" : "إيقاف"} عرض: $offerName');
  }

  // ── Delivery ──
  Future<void> logDeliveryCreate(int userId, String userName, String companyName, {int? deliveryId}) {
    return log(userId: userId, userName: userName, action: 'delivery_create', entityType: 'delivery',
        entityId: deliveryId, description: 'إنشاء شركة توصيل: $companyName');
  }

  Future<void> logDeliveryEdit(int userId, String userName, String companyName, {int? deliveryId}) {
    return log(userId: userId, userName: userName, action: 'delivery_edit', entityType: 'delivery',
        entityId: deliveryId, description: 'تعديل شركة توصيل: $companyName');
  }

  Future<void> logDeliveryDelete(int userId, String userName, String companyName, {int? deliveryId}) {
    return log(userId: userId, userName: userName, action: 'delivery_delete', entityType: 'delivery',
        entityId: deliveryId, description: 'حذف شركة توصيل: $companyName');
  }

  Future<void> logDeliveryStatusChange(int userId, String userName, int orderId, String newStatus) {
    return log(userId: userId, userName: userName, action: 'delivery_status_change', entityType: 'delivery',
        entityId: orderId, description: 'تغيير حالة التوصيل لـ #$orderId إلى $newStatus');
  }

  // ── Distribution ──
  Future<void> logDistribution(int userId, String userName, String action_, String details, {double? amount}) {
    return log(userId: userId, userName: userName, action: 'distribution_$action_', entityType: 'distribution',
        description: details, amount: amount);
  }

  // ── Restaurant Tables ──
  Future<void> logTableOperation(int userId, String userName, String operation, String tableInfo, {int? tableId}) {
    return log(userId: userId, userName: userName, action: 'table_$operation', entityType: 'table',
        entityId: tableId, description: tableInfo);
  }

  // ── Loyalty ──
  Future<void> logLoyaltyOperation(int userId, String userName, String operation, String details, {double? points}) {
    return log(userId: userId, userName: userName, action: 'loyalty_$operation', entityType: 'loyalty',
        description: details, amount: points);
  }

  // ── E-Invoice ──
  Future<void> logEInvoice(int userId, String userName, String operation, String invoiceRef, {int? invoiceId}) {
    return log(userId: userId, userName: userName, action: 'einvoice_$operation', entityType: 'e_invoice',
        entityId: invoiceId, description: 'فاتورة إلكترونية — $operation: $invoiceRef');
  }

  // ── HR — Field-Level Audit Trail ──

  /// Generic HR operation (backward-compatible)
  Future<void> logHrOperation(int userId, String userName, String operation, String details, {int? employeeId}) {
    return log(userId: userId, userName: userName, action: 'hr_$operation', entityType: 'employee',
        entityId: employeeId, description: details);
  }

  /// Log salary change with old/new values for compliance
  Future<void> logSalaryChange(int userId, String userName, String employeeName,
      {int? employeeId, required double oldSalary, required double newSalary, String? reason}) {
    return log(userId: userId, userName: userName, action: 'hr_salary_change', entityType: 'employee',
        entityId: employeeId,
        description: 'تعديل راتب $employeeName${reason != null ? " — $reason" : ""}',
        oldValue: oldSalary.toStringAsFixed(AppConstants.decimalPlaces), newValue: newSalary.toStringAsFixed(AppConstants.decimalPlaces),
        amount: newSalary - oldSalary);
  }

  /// Log payroll run with total amount
  Future<void> logPayrollRun(int userId, String userName, String period,
      {required int employeeCount, required double totalAmount}) {
    return log(userId: userId, userName: userName, action: 'hr_payroll_run', entityType: 'payroll',
        description: 'تشغيل مسير الرواتب: $period ($employeeCount موظف)', amount: totalAmount);
  }

  /// Log employee field change (position, department, etc.)
  Future<void> logEmployeeFieldChange(int userId, String userName, String employeeName, String fieldName,
      {int? employeeId, String? oldValue, String? newValue}) {
    return log(userId: userId, userName: userName, action: 'hr_field_change', entityType: 'employee',
        entityId: employeeId, description: 'تعديل $fieldName لموظف $employeeName',
        oldValue: oldValue, newValue: newValue);
  }

  /// Log attendance action (check-in, check-out, absence, late)
  Future<void> logAttendance(int userId, String userName, String employeeName, String action_,
      {int? employeeId, String? details}) {
    return log(userId: userId, userName: userName, action: 'hr_attendance_$action_', entityType: 'attendance',
        entityId: employeeId,
        description: '${_attendanceLabel(action_)} $employeeName${details != null ? " — $details" : ""}');
  }

  /// Log deduction or bonus applied
  Future<void> logSalaryAdjustment(int userId, String userName, String employeeName, String adjustmentType,
      {int? employeeId, required double amount, String? reason}) {
    return log(userId: userId, userName: userName, action: 'hr_salary_$adjustmentType', entityType: 'payroll',
        entityId: employeeId,
        description: '$adjustmentType لموظف $employeeName${reason != null ? " — $reason" : ""}',
        amount: amount);
  }

  static String _attendanceLabel(String action) => switch (action) {
    'checkin' => 'حضور',
    'checkout' => 'انصراف',
    'absence' => 'غياب',
    'late' => 'تأخر',
    _ => action,
  };

  // ── Branch ──
  Future<void> logBranchOperation(int userId, String userName, String operation, String branchName, {int? branchId}) {
    return log(userId: userId, userName: userName, action: 'branch_$operation', entityType: 'branch',
        entityId: branchId, description: '$operation فرع: $branchName');
  }

  // ── Settings ──
  Future<void> logSettingsChange(int userId, String userName, String settingName,
      {String? oldValue, String? newValue}) {
    return log(userId: userId, userName: userName, action: 'settings_change', entityType: 'settings',
        description: 'تغيير إعداد: $settingName', oldValue: oldValue, newValue: newValue);
  }

  // ── Invoice Design ──
  Future<void> logInvoiceDesignSave(int userId, String userName, String designType) {
    return log(userId: userId, userName: userName, action: 'invoice_design_save', entityType: 'invoice_design',
        description: 'حفظ تصميم فاتورة: $designType');
  }
}
