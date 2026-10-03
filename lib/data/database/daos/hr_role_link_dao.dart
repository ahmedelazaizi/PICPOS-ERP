part of '../database.dart';

/// J4 — «الدور في النظام»: ربطُ الموظف بمستخدم دخولٍ واحد، ووسومُ أدواره،
/// ودفاترُ سنداته، و**المندوبُ الحاليّ** للمستخدم المسجَّل (حفظ كعميل دائم
/// وختمُ فاتورة العميل النقديّ).
extension HrRoleLinkDao on AppDatabase {
  /// The employee linked to login user [userId] — `null` when none.
  Future<int?> employeeIdForUser(int userId) async {
    final row = await customSelect(
      'SELECT id FROM employees WHERE user_id = ? AND deleted_at IS NULL '
      'ORDER BY id LIMIT 1',
      variables: [Variable<int>(userId)],
      readsFrom: {employees},
    ).getSingleOrNull();
    return _dmInt(row?.data['id']);
  }

  /// Links (or with `null` unlinks) the employee's login user. One user ↔
  /// one employee: a user already linked to another employee is refused.
  /// The employee's voucher books follow the user (`holder_user_id`), so
  /// the voucher screens' default book keeps working.
  Future<void> linkEmployeeUser({
    required int employeeId,
    required int? userId,
    int? actorUserId,
  }) {
    return transaction(() async {
      final before = await getEmployeeProfile(employeeId);
      if (before == null) throw HrException('الموظف غير موجود.');
      if (before.userId == userId) return;
      String? username;
      if (userId != null) {
        final user = await (select(users)..where((u) => u.id.equals(userId)))
            .getSingleOrNull();
        if (user == null) throw HrException('المستخدم غير موجود.');
        username = user.username;
        final other = await customSelect(
          'SELECT name FROM employees WHERE user_id = ? AND id <> ? '
          'AND deleted_at IS NULL LIMIT 1',
          variables: [Variable<int>(userId), Variable<int>(employeeId)],
        ).getSingleOrNull();
        if (other != null) {
          throw HrException('المستخدم «{p0}» مرتبط بالموظف «{p1}».',
              {'p0': user.username, 'p1': other.data['name']});
        }
      }
      await customUpdate(
        'UPDATE employees SET user_id = ? WHERE id = ?',
        variables: [Variable<int>(userId), Variable<int>(employeeId)],
        updates: {employees},
      );
      await (update(employees)..where((e) => e.id.equals(employeeId)))
          .write(EmployeesCompanion(lastModifiedAt: Value(DateTime.now())));
      await customUpdate(
        'UPDATE voucher_books SET holder_user_id = ?, last_modified_at = ? '
        'WHERE holder_employee_id = ? AND deleted_at IS NULL',
        variables: [
          Variable<int>(userId),
          Variable<int>(_dmNow()),
          Variable<int>(employeeId),
        ],
        updates: {employees},
      );
      await logEmployeeEvent(employeeId, HrEventType.userLink,
          from: before.username, to: username, actorUserId: actorUserId);
    });
  }

  /// Active users not linked to any other employee (the link picker).
  Future<List<User>> linkableUsers(int employeeId) async {
    final taken = {
      for (final r in await customSelect(
        'SELECT user_id FROM employees WHERE user_id IS NOT NULL AND id <> ? '
        'AND deleted_at IS NULL',
        variables: [Variable<int>(employeeId)],
      ).get())
        (r.data['user_id'] as num).toInt(),
    };
    final all = await (select(users)
          ..where((u) => u.isActive.equals(true) & u.deletedAt.isNull())
          ..orderBy([(u) => OrderingTerm.asc(u.username)]))
        .get();
    return [for (final u in all) if (!taken.contains(u.id)) u];
  }

  /// Sets the employee's role tags ([HrRoleTag]) and logs the change.
  Future<void> setEmployeeRoleTags(int employeeId, Set<String> tags,
      {int? actorUserId}) async {
    final before = await getEmployeeProfile(employeeId);
    if (before == null) throw HrException('الموظف غير موجود.');
    final encoded = HrRoleTag.encode(tags);
    if (HrRoleTag.encode(before.roleTags) == encoded) return;
    await customUpdate(
      'UPDATE employees SET role_tags = ? WHERE id = ?',
      variables: [Variable<String>(encoded), Variable<int>(employeeId)],
      updates: {employees},
    );
    await (update(employees)..where((e) => e.id.equals(employeeId)))
        .write(EmployeesCompanion(lastModifiedAt: Value(DateTime.now())));
    await logEmployeeEvent(employeeId, HrEventType.roleChange,
        from: HrRoleTag.encode(before.roleTags),
        to: encoded,
        actorUserId: actorUserId);
  }

  /// The id of the seeded role suggested for [tag] (‏[HrRoleTag.suggestedRoleNames]).
  Future<int?> suggestedRoleIdForTag(String tag) async {
    for (final name in HrRoleTag.suggestedRoleNames[tag] ?? const <String>[]) {
      final role = await (select(roles)..where((r) => r.name.equals(name)))
          .getSingleOrNull();
      if (role != null) return role.id;
    }
    return null;
  }

  /// Gives (or with `null` takes back) voucher book [bookId] to
  /// [employeeId]; the holder user follows the employee's login user.
  Future<void> setVoucherBookHolder(int bookId, int? employeeId) async {
    final userId = employeeId == null
        ? null
        : (await getEmployeeProfile(employeeId))?.userId;
    await customUpdate(
      'UPDATE voucher_books SET holder_employee_id = ?, holder_user_id = ?, '
      'last_modified_at = ? WHERE id = ?',
      variables: [
        Variable<int>(employeeId),
        Variable<int>(userId),
        Variable<int>(_dmNow()),
        Variable<int>(bookId),
      ],
      updates: {employees},
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // The current rep (logged-in user → employee → routes)
  // ═══════════════════════════════════════════════════════════════════════

  /// The rep behind login user [userId]: the linked employee when it is a
  /// rep (tagged, holding a route, or having rep resources). `routeIds` are
  /// its active routes; `preferredRouteId` is today's route by visit day,
  /// else its only/first route. `null` when the user is not a rep — callers
  /// fall back to the route picker.
  Future<({int repEmployeeId, List<int> routeIds, int? preferredRouteId})?>
      currentRepForUser(int? userId, {DateTime? now}) async {
    if (userId == null) return null;
    final employeeId = await employeeIdForUser(userId);
    if (employeeId == null) return null;
    final profile = await getEmployeeProfile(employeeId);
    if (profile == null || profile.status == EmployeeStatus.terminated) {
      return null;
    }
    final routes = [
      for (final r in await listDistributionRoutes())
        if (r.repEmployeeId == employeeId) r,
    ];
    final hasResources = await getRepResources(employeeId) != null;
    if (!profile.isRep && routes.isEmpty && !hasResources) return null;
    final weekday = (now ?? DateTime.now()).weekday;
    final today = routes.where((r) => r.visitDays.contains(weekday)).toList();
    final preferred = today.isNotEmpty
        ? today.first.id
        : (routes.isNotEmpty ? routes.first.id : null);
    return (
      repEmployeeId: employeeId,
      routeIds: [for (final r in routes) r.id],
      preferredRouteId: preferred,
    );
  }

  /// A sale to the cash customer (or a walk-in) is on no route, so its rep
  /// stamp comes from the selling user's employee link (J3 follow-up).
  /// Never overwrites a stamp already written.
  Future<void> stampSalesInvoiceRepFromUser(
      int invoiceId, int? customerId, int? userId) async {
    if (userId == null) return;
    if (customerId != null && !await isCashCustomer(customerId)) return;
    final stamp = await getDocumentRepStamp('sales_invoices', invoiceId);
    if (stamp.repEmployeeId != null) return;
    final rep = await currentRepForUser(userId);
    if (rep == null) return;
    await stampDocumentRep('sales_invoices', invoiceId, null,
        explicit: RepStamp(
          repEmployeeId: rep.repEmployeeId,
          routeId: stamp.routeId ?? rep.preferredRouteId,
        ));
  }
}
