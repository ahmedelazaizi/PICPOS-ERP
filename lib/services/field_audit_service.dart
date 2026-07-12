import 'package:flutter/foundation.dart';
import '../data/database/database.dart';

/// Service for tracking field-level changes on sensitive entities.
///
/// Provides a diff engine that compares old vs new entity states and
/// automatically logs individual field changes to the FieldAuditLogs table.
class FieldAuditService {
  final AppDatabase _db;

  FieldAuditService(this._db);

  // ═══════════════════════════════════════════════════════════════════════
  // GENERIC DIFF ENGINE
  // ═══════════════════════════════════════════════════════════════════════

  /// Compare two maps of field values and return the differences.
  /// Each entry in [fieldExtractors] maps a field key to a tuple of
  /// (display name, value extractor for old, value extractor for new).
  List<FieldChange> diffMaps({
    required Map<String, String?> oldFields,
    required Map<String, String?> newFields,
    required Map<String, String> fieldLabels,
  }) {
    final changes = <FieldChange>[];

    for (final key in newFields.keys) {
      final oldVal = oldFields[key];
      final newVal = newFields[key];

      if (oldVal != newVal) {
        changes.add(FieldChange(
          fieldName: fieldLabels[key] ?? key,
          fieldKey: key,
          oldValue: oldVal,
          newValue: newVal,
        ));
      }
    }

    return changes;
  }

  /// Generate a unique transaction ID for grouping changes
  String generateTransactionId() {
    return '${DateTime.now().millisecondsSinceEpoch}_${UniqueKey().hashCode}';
  }

  // ═══════════════════════════════════════════════════════════════════════
  // PRODUCT AUDITING
  // ═══════════════════════════════════════════════════════════════════════

  /// Audit product field changes
  Future<void> auditProductUpdate({
    required int productId,
    required Map<String, String?> oldFields,
    required Map<String, String?> newFields,
    required int userId,
    required String userName,
    String? reason,
  }) async {
    const labels = {
      'name': 'اسم المنتج',
      'code': 'كود المنتج',
      'barcode': 'الباركود',
      'price': 'سعر البيع',
      'cost': 'سعر التكلفة',
      'wholesale_price': 'سعر الجملة',
      'min_price': 'أقل سعر',
      'tax_rate': 'نسبة الضريبة',
      'category': 'التصنيف',
      'unit': 'الوحدة',
      'description': 'الوصف',
      'is_active': 'الحالة',
      'track_expiry': 'تتبع الصلاحية',
      'min_stock': 'الحد الأدنى للمخزون',
      'max_stock': 'الحد الأعلى للمخزون',
    };

    final changes = diffMaps(
      oldFields: oldFields,
      newFields: newFields,
      fieldLabels: labels,
    );

    if (changes.isEmpty) return;

    final txnId = generateTransactionId();
    try {
      await _db.logBatchFieldChanges(
        entityType: 'product',
        entityId: productId,
        changedBy: userId,
        changedByName: userName,
        transactionId: txnId,
        changes: changes,
        changeReason: reason,
      );
    } catch (e) {
      debugPrint('[FieldAuditService] Error logging product changes: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // PARTY AUDITING
  // ═══════════════════════════════════════════════════════════════════════

  /// Audit party (customer/supplier) field changes
  Future<void> auditPartyUpdate({
    required int partyId,
    required Map<String, String?> oldFields,
    required Map<String, String?> newFields,
    required int userId,
    required String userName,
    String? reason,
  }) async {
    const labels = {
      'name': 'الاسم',
      'phone': 'الهاتف',
      'address': 'العنوان',
      'email': 'البريد الإلكتروني',
      'tax_number': 'الرقم الضريبي',
      'type': 'النوع',
      'credit_limit': 'حد الائتمان',
      'fixed_discount': 'خصم ثابت',
      'price_level': 'مستوى السعر',
      'is_active': 'الحالة',
      'notes': 'ملاحظات',
    };

    final changes = diffMaps(
      oldFields: oldFields,
      newFields: newFields,
      fieldLabels: labels,
    );

    if (changes.isEmpty) return;

    final txnId = generateTransactionId();
    try {
      await _db.logBatchFieldChanges(
        entityType: 'party',
        entityId: partyId,
        changedBy: userId,
        changedByName: userName,
        transactionId: txnId,
        changes: changes,
        changeReason: reason,
      );
    } catch (e) {
      debugPrint('[FieldAuditService] Error logging party changes: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // INVOICE AUDITING
  // ═══════════════════════════════════════════════════════════════════════

  /// Audit invoice field changes
  Future<void> auditInvoiceUpdate({
    required String entityType, // 'sales_invoice' or 'purchase_invoice'
    required int invoiceId,
    required Map<String, String?> oldFields,
    required Map<String, String?> newFields,
    required int userId,
    required String userName,
    String? reason,
  }) async {
    const labels = {
      'total': 'الإجمالي',
      'discount': 'الخصم',
      'tax': 'الضريبة',
      'net_total': 'صافي الإجمالي',
      'payment_status': 'حالة الدفع',
      'notes': 'ملاحظات',
      'party': 'الطرف',
      'date': 'التاريخ',
      'due_date': 'تاريخ الاستحقاق',
    };

    final changes = diffMaps(
      oldFields: oldFields,
      newFields: newFields,
      fieldLabels: labels,
    );

    if (changes.isEmpty) return;

    final txnId = generateTransactionId();
    try {
      await _db.logBatchFieldChanges(
        entityType: entityType,
        entityId: invoiceId,
        changedBy: userId,
        changedByName: userName,
        transactionId: txnId,
        changes: changes,
        changeReason: reason,
      );
    } catch (e) {
      debugPrint('[FieldAuditService] Error logging invoice changes: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // JOURNAL ENTRY AUDITING
  // ═══════════════════════════════════════════════════════════════════════

  /// Audit journal entry field changes
  Future<void> auditJournalEntryUpdate({
    required int entryId,
    required Map<String, String?> oldFields,
    required Map<String, String?> newFields,
    required int userId,
    required String userName,
    String? reason,
  }) async {
    const labels = {
      'description': 'البيان',
      'total_debit': 'إجمالي المدين',
      'total_credit': 'إجمالي الدائن',
      'date': 'التاريخ',
      'reference': 'المرجع',
      'status': 'الحالة',
    };

    final changes = diffMaps(
      oldFields: oldFields,
      newFields: newFields,
      fieldLabels: labels,
    );

    if (changes.isEmpty) return;

    final txnId = generateTransactionId();
    try {
      await _db.logBatchFieldChanges(
        entityType: 'journal_entry',
        entityId: entryId,
        changedBy: userId,
        changedByName: userName,
        transactionId: txnId,
        changes: changes,
        changeReason: reason,
      );
    } catch (e) {
      debugPrint('[FieldAuditService] Error logging journal entry changes: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // GENERIC AUDIT HELPER
  // ═══════════════════════════════════════════════════════════════════════

  /// Generic audit for any entity type
  Future<void> auditEntityUpdate({
    required String entityType,
    required int entityId,
    required Map<String, String?> oldFields,
    required Map<String, String?> newFields,
    required Map<String, String> fieldLabels,
    required int userId,
    required String userName,
    String? reason,
  }) async {
    final changes = diffMaps(
      oldFields: oldFields,
      newFields: newFields,
      fieldLabels: fieldLabels,
    );

    if (changes.isEmpty) return;

    final txnId = generateTransactionId();
    try {
      await _db.logBatchFieldChanges(
        entityType: entityType,
        entityId: entityId,
        changedBy: userId,
        changedByName: userName,
        transactionId: txnId,
        changes: changes,
        changeReason: reason,
      );
    } catch (e) {
      debugPrint('[FieldAuditService] Error logging $entityType changes: $e');
    }
  }
}
