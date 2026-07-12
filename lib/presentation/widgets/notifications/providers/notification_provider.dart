import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../data/providers/providers.dart';
import '../../../../services/password_collision_scanner.dart';

final notificationProvider = Provider((ref) {
  final repo = ref.watch(notificationRepositoryProvider);
  return NotificationService(repo);
});

/// Feature 004 (US2) — stream of every unresolved cross-branch password
/// collision alert (`relatedEntityType == 'password_collision'`).
///
/// Sourced from the local Drift `notifications` table via
/// [NotificationDao.watchByType]. The SecurityAlertsPanel mounted on the
/// user-management screen consumes this provider and renders one card per
/// row. Filters out already-read alerts so resolved warnings disappear from
/// the panel as soon as the admin acts on them.
final passwordCollisionAlertsProvider =
    StreamProvider.autoDispose<List<NotificationData>>((ref) {
  final db = ref.watch(databaseProvider);
  return db
      .watchByType(PasswordCollisionScanner.notificationEntityType)
      .map((rows) => rows.where((n) => !n.isRead).toList());
});

final unreadNotificationsCountProvider = StreamProvider.autoDispose<int>((ref) {
  final authUser = ref.watch(authProvider).user;
  if (authUser == null) return Stream.value(0);

  final repo = ref.watch(notificationRepositoryProvider);
  return repo.watchUnreadNotificationsCount(authUser.id);
});

final latestNotificationsProvider = StreamProvider.autoDispose<List<NotificationData>>((ref) {
  final authUser = ref.watch(authProvider).user;
  if (authUser == null) return Stream.value([]);

  final repo = ref.watch(notificationRepositoryProvider);
  return repo.watchLatestNotifications(authUser.id, limit: 20);
});

class NotificationService {
  final INotificationRepository _repo;

  NotificationService(this._repo);

  Future<void> markAsRead(int notificationId) async {
    await _repo.markNotificationAsRead(notificationId);
  }

  Future<void> markAllAsRead(int userId) async {
    await _repo.markAllNotificationsAsRead(userId);
  }

  Future<void> sendNotification({
    required int userId,
    required String title,
    required String body,
    String type = 'info',
    int? relatedEntityId,
    String? relatedEntityType,
  }) async {
    await _repo.createNotification(
      userId: userId,
      title: title,
      body: body,
      type: type,
      relatedEntityId: relatedEntityId,
      relatedEntityType: relatedEntityType,
    );
  }
}
