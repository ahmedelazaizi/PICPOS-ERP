part of '../database.dart';

// ═══════════════════════════════════════════════════════════════════════════
// SOD MATRIX DAO — مصفوفة فصل المهام
// Segregation of Duties — ISA 315 / COSO Framework
// ═══════════════════════════════════════════════════════════════════════════

extension SodMatrixDao on AppDatabase {

  /// Seed default SOD conflict rules
  Future<void> seedDefaultSodConflicts() async {
    final defaults = [
      {
        'p1': 'create_journal',
        'p2': 'approve_journal',
        'type': 'hard',
        'desc': 'من ينشئ القيد لا يعتمده — فصل إلزامي',
      },
      {
        'p1': 'manage_users',
        'p2': 'manage_permissions',
        'type': 'hard',
        'desc': 'من يدير المستخدمين لا يدير الصلاحيات — منع تصعيد الامتيازات',
      },
      {
        'p1': 'create_purchase',
        'p2': 'approve_payment',
        'type': 'hard',
        'desc': 'من يسجل المشتريات لا يوافق على الدفع — منع الاحتيال',
      },
      {
        'p1': 'manage_inventory',
        'p2': 'create_stock_audit',
        'type': 'hard',
        'desc': 'من يدير المخزون لا يجري الجرد — استقلالية المراقبة',
      },
      {
        'p1': 'create_sales',
        'p2': 'create_refund',
        'type': 'soft',
        'desc': 'من يسجل البيع لا يسجل المرتجع — كشف تحايل (تحذير)',
      },
      {
        'p1': 'manage_accounts',
        'p2': 'create_journal',
        'type': 'soft',
        'desc': 'من يدير شجرة الحسابات لا ينشئ قيود — تحذير',
      },
      {
        'p1': 'manage_pricing',
        'p2': 'create_sales',
        'type': 'soft',
        'desc': 'من يحدد الأسعار لا يسجل البيع — تحذير من التلاعب',
      },
    ];

    for (final rule in defaults) {
      // Check if already exists
      final existing = await customSelect(
        'SELECT COUNT(*) as cnt FROM sod_conflicts WHERE permission1 = ? AND permission2 = ?',
        variables: [Variable(rule['p1']!), Variable(rule['p2']!)],
      ).getSingle();
      if (((existing.data['cnt'] as int?) ?? 0) > 0) continue;

      await into(sodConflicts).insert(
        SodConflictsCompanion.insert(
          permission1: rule['p1']!,
          permission2: rule['p2']!,
          conflictType: Value(rule['type']!),
          description: rule['desc']!,
        ),
      );
    }
  }

  /// Check SOD violations for a user (before assigning permissions)
  /// Returns list of conflicts found
  Future<List<Map<String, dynamic>>> checkSodViolations(int userId) async {
    // Get user's current permissions (via their role)
    final userPerms = await customSelect(
      '''SELECT p.code FROM permissions p
         JOIN role_permissions rp ON p.id = rp.permission_id
         JOIN users u ON u.role_id = rp.role_id
         WHERE u.id = ?''',
      variables: [Variable(userId)],
    ).get();

    final permCodes = userPerms.map((r) => r.data['code'] as String).toSet();
    final violations = <Map<String, dynamic>>[];

    // Check against all active conflicts
    final conflicts = await (select(sodConflicts)
          ..where((c) => c.isActive.equals(true)))
        .get();

    for (final conflict in conflicts) {
      if (permCodes.contains(conflict.permission1) &&
          permCodes.contains(conflict.permission2)) {
        violations.add({
          'conflictId': conflict.id,
          'permission1': conflict.permission1,
          'permission2': conflict.permission2,
          'conflictType': conflict.conflictType,
          'description': conflict.description,
        });
      }
    }

    return violations;
  }

  /// Check SOD before adding a permission to a role
  /// Returns blocking conflicts (hard) and warnings (soft)
  Future<Map<String, List<Map<String, dynamic>>>> checkSodBeforeAssign({
    required int roleId,
    required String newPermissionCode,
  }) async {
    // Get existing permissions for the role
    final rolePerms = await customSelect(
      '''SELECT p.code FROM permissions p
         JOIN role_permissions rp ON p.id = rp.permission_id
         WHERE rp.role_id = ?''',
      variables: [Variable(roleId)],
    ).get();

    final existingCodes = rolePerms.map((r) => r.data['code'] as String).toSet();
    final hardBlocks = <Map<String, dynamic>>[];
    final softWarnings = <Map<String, dynamic>>[];

    final conflicts = await (select(sodConflicts)
          ..where((c) => c.isActive.equals(true)))
        .get();

    for (final conflict in conflicts) {
      // Check if new permission creates a conflict with any existing one
      if ((conflict.permission1 == newPermissionCode &&
              existingCodes.contains(conflict.permission2)) ||
          (conflict.permission2 == newPermissionCode &&
              existingCodes.contains(conflict.permission1))) {
        final entry = {
          'conflictId': conflict.id,
          'conflictWith': conflict.permission1 == newPermissionCode
              ? conflict.permission2
              : conflict.permission1,
          'description': conflict.description,
        };
        if (conflict.conflictType == 'hard') {
          hardBlocks.add(entry);
        } else {
          softWarnings.add(entry);
        }
      }
    }

    return {'blocks': hardBlocks, 'warnings': softWarnings};
  }

  /// Log a SOD violation occurrence
  Future<void> logSodViolation({
    required int conflictId,
    required int userId,
    required String action,
    bool wasBlocked = false,
    String? overrideReason,
    int? overriddenBy,
  }) async {
    final user = await (select(users)..where((u) => u.id.equals(userId))).getSingleOrNull();
    await into(sodViolations).insert(
      SodViolationsCompanion.insert(
        conflictId: conflictId,
        userId: userId,
        roleId: Value(user?.roleId),
        detectedAction: action,
        wasBlocked: Value(wasBlocked),
        overrideReason: Value(overrideReason),
        overriddenBy: Value(overriddenBy),
      ),
    );
  }

  /// Get SOD violation report
  Future<List<SodViolationData>> getSodViolationReport({
    DateTime? from,
    DateTime? to,
  }) {
    final query = select(sodViolations);
    if (from != null) {
      query.where((v) => v.detectedAt.isBiggerOrEqualValue(from));
    }
    if (to != null) {
      query.where((v) => v.detectedAt.isSmallerOrEqualValue(to));
    }
    query.orderBy([(v) => OrderingTerm.desc(v.detectedAt)]);
    return query.get();
  }

  /// Get all active SOD conflicts
  Future<List<SodConflictData>> getActiveSodConflicts() {
    return (select(sodConflicts)..where((c) => c.isActive.equals(true))).get();
  }
}
