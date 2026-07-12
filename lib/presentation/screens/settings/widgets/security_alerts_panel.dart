// ═══════════════════════════════════════════════════════════════════════════
// SECURITY ALERTS PANEL — Feature 004 (US2 — Cross-branch password collision)
// ═══════════════════════════════════════════════════════════════════════════
//
// Mounted on the user-management screen (above the users list). Streams every
// unresolved Notification whose `relatedEntityType == 'password_collision'`
// and renders one card per alert with two actions:
//
//   1. "إلزام بتغيير كلمة المرور" — opens the existing reset-password dialog
//      for the user that triggered the alert. Resolving the password change
//      via that dialog calls `updateUserPassword`, which invokes
//      `PasswordCollisionScanner.resolveCollisionsInvolving(...)` and clears
//      the alert from the panel automatically.
//   2. "إخفاء" — marks `isRead = true` on the Notification row so it
//      disappears from the panel without forcing a password rotation.
//
// Empty state: the panel hides itself completely (returns SizedBox.shrink),
// so a healthy environment shows no chrome.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../data/providers/providers.dart';
import '../../../widgets/notifications/providers/notification_provider.dart';
import 'reset_password_dialog.dart';

class SecurityAlertsPanel extends ConsumerWidget {
  const SecurityAlertsPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alertsAsync = ref.watch(passwordCollisionAlertsProvider);

    return alertsAsync.when(
      data: (alerts) {
        if (alerts.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Card(
            elevation: 1,
            color: Colors.orange.shade50,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        PhosphorIconsBold.shieldWarning,
                        color: Colors.orange,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'تنبيهات أمنية: تطابق كلمات مرور بين الفروع',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.orange.shade900,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '${alerts.length}',
                        style: TextStyle(
                          color: Colors.orange.shade900,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ...alerts.map((n) => _AlertCard(notification: n)),
                ],
              ),
            ),
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
    );
  }
}

class _AlertCard extends ConsumerWidget {
  const _AlertCard({required this.notification});

  final NotificationData notification;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pair = _decodePair(notification.body);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              notification.title,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            if (pair.length == 2)
              Text(
                'بين المستخدمين رقم ${pair.first} و ${pair.last}',
                style: const TextStyle(color: Colors.black54, fontSize: 12),
              ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                  ),
                  icon: const Icon(PhosphorIconsBold.key, size: 16),
                  label: const Text('إلزام بتغيير كلمة المرور'),
                  onPressed: pair.isEmpty
                      ? null
                      : () => _forceResetFor(context, ref, pair.first),
                ),
                OutlinedButton.icon(
                  icon: const Icon(PhosphorIconsBold.eyeSlash, size: 16),
                  label: const Text('إخفاء'),
                  onPressed: () =>
                      ref.read(databaseProvider).markNotificationAsRead(
                            notification.id,
                          ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  List<int> _decodePair(String body) {
    try {
      final decoded = jsonDecode(body) as Map<String, dynamic>;
      final pair = (decoded['pair'] as List?)?.cast<int>();
      return pair ?? const [];
    } catch (_) {
      return const [];
    }
  }

  Future<void> _forceResetFor(
    BuildContext context,
    WidgetRef ref,
    int userId,
  ) async {
    final db = ref.read(databaseProvider);
    final user = await (db.select(db.users)..where((u) => u.id.equals(userId)))
        .getSingleOrNull();
    if (user == null) return;
    if (!context.mounted) return;
    await showDialog<bool>(
      context: context,
      builder: (_) => ResetPasswordDialog(user: user),
    );
  }
}
