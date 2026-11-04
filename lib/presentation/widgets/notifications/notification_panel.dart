import 'package:picpos_erp/core/i18n/tr.dart';
// ignore_for_file: avoid_dynamic_calls
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../core/theme/app_colors.dart';
import 'package:picpos_erp/presentation/picpos_shell/picpos_surface.dart';
import 'package:picpos_erp/core/theme/readable_colors.dart';
import '../../../../data/providers/providers.dart';
import 'providers/notification_provider.dart';

/// حبر الهوية: الفاتح `AppColors.primary` كما كان، والداكن أفتح قراءةً.
Color _brand(BuildContext c) =>
    c.picposIsDark ? readableBrand(c) : AppColors.primary;

class NotificationPanel extends ConsumerWidget {
  const NotificationPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notificationsAsync = ref.watch(latestNotificationsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: context.picposHairline)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(PhosphorIconsBold.bellRinging, color: _brand(context)),
                  const SizedBox(width: 12),
                  Text(
                    tr('الإشعارات'),
                    style: GoogleFonts.cairo(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: context.picposText,
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  TextButton.icon(
                    onPressed: () {
                      final authUser = ref.read(authProvider).user;
                      if (authUser != null) {
                        ref.read(notificationProvider).markAllAsRead(authUser.id);
                      }
                    },
                    icon: const Icon(PhosphorIconsRegular.checks, size: 16),
                    label: Text(
                      tr('تحديد الكل كمقروء'),
                      style: GoogleFonts.cairo(fontSize: 12),
                    ),
                    style: TextButton.styleFrom(
                      foregroundColor: _brand(context),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(PhosphorIconsRegular.x, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                    tooltip: tr('إغلاق'),
                  ),
                ],
              ),
            ],
          ),
        ),

        // List
        Expanded(
          child: notificationsAsync.when(
            data: (notifications) {
              if (notifications.isEmpty) {
                return _buildEmptyState(context);
              }

              return ListView.separated(
                itemCount: notifications.length,
                separatorBuilder: (context, index) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final notif = notifications[index];
                  return _NotificationTile(
                    notification: notif,
                    onTap: () {
                      if (!notif.isRead) {
                        ref.read(notificationProvider).markAsRead(notif.id);
                      }
                      // Optionally, navigate based on relatedEntityId / Type
                      if (notif.relatedEntityType != null && notif.relatedEntityId != null) {
                        Navigator.of(context).pop(); // close drawer
                        _handleNavigation(context, notif.relatedEntityType!, notif.relatedEntityId!);
                      }
                    },
                  );
                },
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (err, stack) => Center(
              child: Text(tr('خطأ في تحميل الإشعارات'), style: GoogleFonts.cairo(color: AppColors.error)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(PhosphorIconsRegular.bellSlash, size: 60, color: context.picposMuted.withValues(alpha: 0.5)),
          const SizedBox(height: 16),
          Text(
            tr('لا توجد إشعارات جديدة'),
            style: GoogleFonts.cairo(
              fontSize: 16,
              color: context.picposMuted,
            ),
          ),
        ],
      ),
    );
  }

  void _handleNavigation(BuildContext context, String type, int id) {
    // E.g.
    // if (type == 'stock_requisition') {
    //   context.goNamed('stock_requisitions', pathParameters: {'id': id.toString()});
    // }
  }
}

class _NotificationTile extends StatelessWidget {
  final dynamic notification;
  final VoidCallback onTap;

  const _NotificationTile({
    required this.notification,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bool isRead = notification.isRead as bool;
    final String type = notification.type as String;

    Color iconColor;
    IconData iconData;

    switch (type) {
      case 'warning':
        iconColor = AppColors.warning;
        iconData = PhosphorIconsFill.warningCircle;
        break;
      case 'error':
        iconColor = AppColors.error;
        iconData = PhosphorIconsFill.warningOctagon;
        break;
      case 'success':
        iconColor = AppColors.success;
        iconData = PhosphorIconsFill.checkCircle;
        break;
      case 'info':
      default:
        iconColor = AppColors.primary;
        iconData = PhosphorIconsFill.info;
        break;
    }
    // الحبرُ يُقاس على خلفية الصف المصبوغة فعلاً (غير المقروء) لا على الكرت.
    final rowBg = isRead
        ? context.picposCard
        : Color.alphaBlend(iconColor.withValues(alpha: 0.05), context.picposCard);
    final iconBgSolid =
        Color.alphaBlend(iconColor.withValues(alpha: 0.1), rowBg);
    final iconInk = readableOn(context, iconColor, on: iconBgSolid);
    final mutedInk = readableOn(context, context.picposMuted, on: rowBg);

    return InkWell(
      onTap: onTap,
      child: Container(
        color: isRead ? Colors.transparent : iconColor.withValues(alpha: 0.05),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(iconData, color: iconInk, size: 20),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          notification.title as String,
                          style: GoogleFonts.cairo(
                            fontWeight: isRead ? FontWeight.normal : FontWeight.bold,
                            color: context.picposText,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      if (!isRead)
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: AppColors.primary,
                            shape: BoxShape.circle,
                          ),
                        )
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    notification.body as String,
                    style: GoogleFonts.cairo(
                      color: context.picposSecondary,
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _formatTimeAgo(notification.createdAt as DateTime),
                    style: GoogleFonts.cairo(
                      color: mutedInk,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTimeAgo(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays > 0) {
      return tr('منذ {p0} يوم', {'p0': difference.inDays});
    } else if (difference.inHours > 0) {
      return tr('منذ {p0} ساعة', {'p0': difference.inHours});
    } else if (difference.inMinutes > 0) {
      return tr('منذ {p0} دقيقة', {'p0': difference.inMinutes});
    } else {
      return tr('الآن');
    }
  }
}