part of '../database.dart';

// ═══════════════════════════════════════════════════════════════════════════
// NOTIFICATION DAO — إدارة الإشعارات الداخلية
// ═══════════════════════════════════════════════════════════════════════════

extension NotificationDao on AppDatabase {
  
  /// Get unread notifications count for a specific user
  Stream<int> watchUnreadNotificationsCount(int userId) {
    final query = select(notifications)
      ..where((n) => n.userId.equals(userId) & n.isRead.equals(false));
    return query.watch().map((list) => list.length);
  }

  /// Get the latest notifications for a specific user
  Stream<List<NotificationData>> watchLatestNotifications(int userId, {int limit = 50}) {
    final query = select(notifications)
      ..where((n) => n.userId.equals(userId))
      ..orderBy([(n) => OrderingTerm(expression: n.createdAt, mode: OrderingMode.desc)])
      ..limit(limit);
    return query.watch();
  }

  /// Watch every notification whose `relatedEntityType` matches [type],
  /// most-recent-first. Used by Feature 004 US2's SecurityAlertsPanel to
  /// stream cross-branch password-collision warnings into the user-management
  /// screen without coupling to a single user inbox.
  Stream<List<NotificationData>> watchByType(String type, {int limit = 100}) {
    final query = select(notifications)
      ..where((n) => n.relatedEntityType.equals(type))
      ..orderBy([(n) => OrderingTerm(expression: n.createdAt, mode: OrderingMode.desc)])
      ..limit(limit);
    return query.watch();
  }

  /// Mark a single notification as read
  Future<void> markNotificationAsRead(int notificationId) {
    return (update(notifications)..where((n) => n.id.equals(notificationId)))
        .write(const NotificationsCompanion(isRead: Value(true)));
  }

  /// Mark all notifications as read for a specific user
  Future<void> markAllNotificationsAsRead(int userId) {
    return (update(notifications)
          ..where((n) => n.userId.equals(userId) & n.isRead.equals(false)))
        .write(const NotificationsCompanion(isRead: Value(true)));
  }

  /// Create a new notification
  Future<int> createNotification({
    required int userId,
    required String title,
    required String body,
    String type = 'info',
    int? relatedEntityId,
    String? relatedEntityType,
  }) {
    return into(notifications).insert(
      NotificationsCompanion.insert(
        userId: userId,
        title: title,
        body: body,
        type: Value(type),
        relatedEntityId: Value(relatedEntityId),
        relatedEntityType: Value(relatedEntityType),
      ),
    );
  }

  /// Delete old read notifications (e.g., older than 30 days) to keep the table small
  Future<int> cleanupOldNotifications({int daysOld = 30}) {
    final cutoffDate = DateTime.now().subtract(Duration(days: daysOld));
    return (delete(notifications)
          ..where((n) => n.isRead.equals(true) & n.createdAt.isSmallerThanValue(cutoffDate)))
        .go();
  }
}
