import '../../data/database/database.dart';

abstract class INotificationRepository {
  Stream<int> watchUnreadNotificationsCount(int userId);
  Stream<List<NotificationData>> watchLatestNotifications(int userId, {int limit = 50});
  Future<void> markNotificationAsRead(int notificationId);
  Future<void> markAllNotificationsAsRead(int userId);
  Future<int> createNotification({
    required int userId,
    required String title,
    required String body,
    String type = 'info',
    int? relatedEntityId,
    String? relatedEntityType,
  });
  Future<int> cleanupOldNotifications({int daysOld = 30});
}
