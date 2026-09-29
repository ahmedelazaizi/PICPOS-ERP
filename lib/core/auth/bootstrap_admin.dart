import 'package:ural_erp/core/i18n/tr.dart';
// ═══════════════════════════════════════════════════════════════════════════
// Spec 061 — Bootstrap Admin Invariants
// ═══════════════════════════════════════════════════════════════════════════
//
// The bootstrap admin row (id=1, username='admin') is seeded by the initial
// migration and MUST never be deactivated, locked, deleted, or demoted.
// Recovery from such a state requires direct SQLCipher surgery — no in-app
// path exists.
//
// QA findings D1-002 (P0) and D1-003 (P0) showed two attack surfaces:
//   • Local screen — Users-management handlers (`_toggleUserActive`,
//     `_toggleUserLock`, `_deleteUser`) never check the target user before
//     mutating.
//   • Server API — `setRolePermissions` accepts an empty list for the admin
//     role; `putUser` accepts arbitrary `roleId` change for user id=1.
//
// Every mutation path that could violate this invariant gates on
// [isBootstrapAdmin] and surfaces the appropriate Arabic message constant.
// Server-side handlers wrap the message in HTTP 403; local handlers raise
// a StateError that the screen catches into a snackbar.
//
// See specs/061-bootstrap-admin-invariants/spec.md for the full design.
// ═══════════════════════════════════════════════════════════════════════════

/// True if [userId] identifies the bootstrap admin — either by id (the
/// stable identifier from the seed migration) OR by [username] (catches
/// the edge case where a future migration kept the username while
/// renaming the id).
bool isBootstrapAdmin(int userId, {String? username}) =>
    userId == 1 || username == 'admin';

/// Generic message for deactivate / lock / delete attempts on the
/// bootstrap admin. Used by DAO StateError throws and screen snackbars.
const String bootstrapAdminGuardMessage =
    'لا يمكن تعطيل أو قفل أو حذف المستخدم الإداري الأساسي '
    '(يُسبّب قفل النظام بالكامل).';

/// Message for role-change attempts on the bootstrap admin.
String get bootstrapAdminRoleGuardMessage => tr('لا يمكن تغيير دور المستخدم الإداري الأساسي.');

/// Message for setRolePermissions attempts that would strip the
/// admin role of its core management permissions (rolesManage / usersManage).
String get bootstrapAdminRolePermissionsGuardMessage => tr('لا يمكن إزالة صلاحيات إدارة الأدوار والمستخدمين من دور المدير الأساسي.');
