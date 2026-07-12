import '../../domain/repositories/notification_repository.dart';
import '../database/database.dart';

class DriftNotificationRepository implements INotificationRepository {
  final AppDatabase _db;

  DriftNotificationRepository(this._db);

  @override
  Stream<int> watchUnreadNotificationsCount(int userId) =>
      _db.watchUnreadNotificationsCount(userId);

  @override
  Stream<List<NotificationData>> watchLatestNotifications(int userId,
          {int limit = 50}) =>
      _db.watchLatestNotifications(userId, limit: limit);

  @override
  Future<void> markNotificationAsRead(int notificationId) =>
      _db.markNotificationAsRead(notificationId);

  @override
  Future<void> markAllNotificationsAsRead(int userId) =>
      _db.markAllNotificationsAsRead(userId);

  @override
  Future<int> createNotification({
    required int userId,
    required String title,
    required String body,
    String type = 'info',
    int? relatedEntityId,
    String? relatedEntityType,
  }) =>
      _db.createNotification(
        userId: userId,
        title: title,
        body: body,
        type: type,
        relatedEntityId: relatedEntityId,
        relatedEntityType: relatedEntityType,
      );

  @override
  Future<int> cleanupOldNotifications({int daysOld = 30}) =>
      _db.cleanupOldNotifications(daysOld: daysOld);
}
