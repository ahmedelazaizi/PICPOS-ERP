import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_colors.dart';
import '../../providers/pos_notification_provider.dart';

class PosNotificationBell extends ConsumerWidget {
  const PosNotificationBell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifications = ref.watch(posNotificationsProvider);
    final unreadCount = notifications.where((n) => !n.isRead).length;

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: PopupMenuButton<void>(
        offset: const Offset(0, 50),
        onOpened: () {
          // Mark all as read when opened
          ref.read(posNotificationsProvider.notifier).markAllRead();
        },
        itemBuilder: (context) {
          if (notifications.isEmpty) {
            return [
              const PopupMenuItem(
                enabled: false,
                child: Center(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'لا توجد إشعارات',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                ),
              ),
            ];
          }
          return [
            // Header with clear button
            PopupMenuItem(
              enabled: false,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'الإشعارات',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  TextButton.icon(
                    onPressed: () {
                      ref.read(posNotificationsProvider.notifier).clear();
                      Navigator.pop(context);
                    },
                    icon: const Icon(Icons.clear_all, size: 16),
                    label: const Text(
                      'مسح الكل',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
            const PopupMenuDivider(),
            // Show last 15 notifications
            ...notifications.take(15).map((n) {
              final PosNotificationType nType = n.type;
              final color = switch (nType) {
                PosNotificationType.success => AppColors.success,
                PosNotificationType.error => AppColors.error,
                PosNotificationType.warning => AppColors.warning,
                PosNotificationType.info => AppColors.info,
              };
              final icon = switch (nType) {
                PosNotificationType.success => Icons.check_circle_rounded,
                PosNotificationType.error => Icons.error_rounded,
                PosNotificationType.warning => Icons.warning_rounded,
                PosNotificationType.info => Icons.info_rounded,
              };
              final timeAgo = DateTime.now().difference(n.timestamp);
              final timeText = timeAgo.inMinutes < 1
                  ? 'الآن'
                  : timeAgo.inMinutes < 60
                  ? 'منذ ${timeAgo.inMinutes} د'
                  : 'منذ ${timeAgo.inHours} س';

              return PopupMenuItem(
                enabled: false,
                height: 42,
                child: Row(
                  children: [
                    Icon(icon, color: color, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        n.message,
                        style: const TextStyle(fontSize: 13),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      timeText,
                      style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                    ),
                  ],
                ),
              );
            }),
          ];
        },
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white10,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.notifications_outlined,
                color: Colors.white70,
                size: 22,
              ),
            ),
            if (unreadCount > 0)
              Positioned(
                top: -4,
                right: -4,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(
                    color: AppColors.error,
                    shape: BoxShape.circle,
                  ),
                  constraints: const BoxConstraints(
                    minWidth: 18,
                    minHeight: 18,
                  ),
                  child: Center(
                    child: Text(
                      unreadCount > 9 ? '9+' : '$unreadCount',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
