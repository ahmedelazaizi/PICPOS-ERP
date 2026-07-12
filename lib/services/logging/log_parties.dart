part of '../activity_logger.dart';

// ═══════════════════════════════════════════════════════════════════════════
// PARTIES — Customers, Suppliers, Unified Parties
// ═══════════════════════════════════════════════════════════════════════════
//
// PII REDACTION (2026-05-12 hardening pass):
//   activity_logs.description previously embedded the party's actual name
//   (e.g. "تعديل عميل: أحمد محمد"). This put customer PII directly into the
//   audit-trail text — exported logs / cross-branch admins could read every
//   merchant's customer roster without going through a permission-gated
//   join. Now description carries only "تعديل عميل #N" with the entityId,
//   and the UI's activity-log viewer joins to parties at display time so
//   authorized users still see the name while exported / cached log
//   payloads stay free of PII.
//
//   The `partyName` parameters are kept on the public method signatures
//   for source-compat (~30 call sites) but consciously dropped from the
//   description string. Don't add it back without a security review.
//
// ═══════════════════════════════════════════════════════════════════════════

extension ActivityLoggerParties on ActivityLogger {
  String _idOrUnknown(int? id) => id != null ? '#$id' : '#?';

  Future<void> logCustomerAdd(int userId, String userName, String customerName, {int? customerId}) {
    return log(userId: userId, userName: userName, action: 'customer_add', entityType: 'customer',
        entityId: customerId, description: 'إضافة عميل ${_idOrUnknown(customerId)}');
  }

  Future<void> logCustomerEdit(int userId, String userName, String customerName, {int? customerId}) {
    return log(userId: userId, userName: userName, action: 'customer_edit', entityType: 'customer',
        entityId: customerId, description: 'تعديل عميل ${_idOrUnknown(customerId)}');
  }

  Future<void> logCustomerDelete(int userId, String userName, String customerName, {int? customerId}) {
    return log(userId: userId, userName: userName, action: 'customer_delete', entityType: 'customer',
        entityId: customerId, description: 'حذف عميل ${_idOrUnknown(customerId)}');
  }

  Future<void> logSupplierAdd(int userId, String userName, String supplierName, {int? supplierId}) {
    return log(userId: userId, userName: userName, action: 'supplier_add', entityType: 'supplier',
        entityId: supplierId, description: 'إضافة مورد ${_idOrUnknown(supplierId)}');
  }

  Future<void> logSupplierEdit(int userId, String userName, String supplierName, {int? supplierId}) {
    return log(userId: userId, userName: userName, action: 'supplier_edit', entityType: 'supplier',
        entityId: supplierId, description: 'تعديل مورد ${_idOrUnknown(supplierId)}');
  }

  Future<void> logSupplierDelete(int userId, String userName, String supplierName, {int? supplierId}) {
    return log(userId: userId, userName: userName, action: 'supplier_delete', entityType: 'supplier',
        entityId: supplierId, description: 'حذف مورد ${_idOrUnknown(supplierId)}');
  }

  Future<void> logPartyAdd(int userId, String userName, String partyName, String partyType, {int? partyId}) {
    return log(userId: userId, userName: userName, action: 'party_add', entityType: 'party',
        entityId: partyId, description: 'إضافة $partyType ${_idOrUnknown(partyId)}');
  }

  Future<void> logPartyEdit(int userId, String userName, String partyName, String partyType, {int? partyId}) {
    return log(userId: userId, userName: userName, action: 'party_edit', entityType: 'party',
        entityId: partyId, description: 'تعديل $partyType ${_idOrUnknown(partyId)}');
  }

  Future<void> logPartyDelete(int userId, String userName, String partyName, String partyType, {int? partyId}) {
    return log(userId: userId, userName: userName, action: 'party_delete', entityType: 'party',
        entityId: partyId, description: 'حذف $partyType ${_idOrUnknown(partyId)}');
  }
}
