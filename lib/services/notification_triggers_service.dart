import 'package:flutter/foundation.dart';
import '../domain/repositories/i_products_repository.dart';
import '../domain/repositories/settings_repository.dart';
import '../presentation/widgets/notifications/providers/notification_provider.dart';

/// B3 — Automated notification triggers service.
/// Checks for actionable business events and creates in-app notifications.
class NotificationTriggersService {
  final IProductRepository _productRepo;
  final ISettingsRepository _settingsRepo;
  final NotificationService _notificationService;

  NotificationTriggersService(
    this._productRepo,
    this._settingsRepo,
    this._notificationService,
  );

  /// Run all automated checks and fire notifications for relevant events.
  /// Called on dashboard load. All errors are silently caught.
  Future<void> runAllChecks({required int userId}) async {
    await Future.wait([
      _checkLowStockProducts(userId),
      _checkBackupReminder(userId),
    ]);
  }

  // ═══════════════════════════════════════════════════════════════
  // 1. LOW STOCK CHECK
  // ═══════════════════════════════════════════════════════════════
  Future<void> _checkLowStockProducts(int userId) async {
    try {
      final lowStock = await _productRepo.getLowStockProducts();
      if (lowStock.isEmpty) return;

      // Check if we already notified today via setting key
      final lastCheck = await _settingsRepo.getSetting('_notif_low_stock_date');
      final todayStr = DateTime.now().toIso8601String().substring(0, 10);
      if (lastCheck == todayStr) return;

      await _notificationService.sendNotification(
        userId: userId,
        title: 'تنبيه نقص مخزون ⚠️',
        body: '${lowStock.length} صنف وصل للحد الأدنى. راجع المخزون لتفادي نفاد الأصناف.',
        type: 'warning',
        relatedEntityType: 'low_stock',
      );
      await _settingsRepo.saveSetting('_notif_low_stock_date', todayStr);
    } catch (e) {
      debugPrint('⚠️ Low stock notification check failed: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // 2. BACKUP REMINDER
  // ═══════════════════════════════════════════════════════════════
  Future<void> _checkBackupReminder(int userId) async {
    try {
      // Check if we already reminded today
      final lastReminder = await _settingsRepo.getSetting('_notif_backup_date');
      final todayStr = DateTime.now().toIso8601String().substring(0, 10);
      if (lastReminder == todayStr) return;

      final lastBackup = await _settingsRepo.getSetting('last_backup_date');
      if (lastBackup == null) {
        // Never backed up
        await _notificationService.sendNotification(
          userId: userId,
          title: 'تذكير: أنشئ نسخة احتياطية 💾',
          body: 'لم يتم إنشاء أي نسخة احتياطية بعد. احمِ بياناتك الآن.',
          type: 'warning',
          relatedEntityType: 'backup_reminder',
        );
        await _settingsRepo.saveSetting('_notif_backup_date', todayStr);
        return;
      }

      // Check if last backup is older than 7 days
      final lastDate = DateTime.tryParse(lastBackup);
      if (lastDate != null && DateTime.now().difference(lastDate).inDays > 7) {
        await _notificationService.sendNotification(
          userId: userId,
          title: 'تذكير: نسخة احتياطية 💾',
          body: 'مضى أكثر من 7 أيام على آخر نسخة احتياطية. أنشئ نسخة جديدة.',
          type: 'info',
          relatedEntityType: 'backup_reminder',
        );
        await _settingsRepo.saveSetting('_notif_backup_date', todayStr);
      }
    } catch (e) { debugPrint('⚠️ Notification trigger error: $e'); }
  }
}
