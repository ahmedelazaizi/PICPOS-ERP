// ═══════════════════════════════════════════════════════════════════════════
// C-05: Anomaly Detection Alerts Service
// Flags unusual patterns: excessive discounts, after-hours activity, high voids
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../core/i18n/tr.dart';
import '../core/theme/app_colors.dart';

/// Types of anomalies that can be detected
enum AnomalyType {
  excessiveDiscount,
  afterHoursActivity,
  highVoidRate,
  unusualRefund,
  priceOverride,
  repeatedFailedLogin,
  bulkDeletion;

  String get labelAr => switch (this) {
    AnomalyType.excessiveDiscount => tr('خصم مفرط'),
    AnomalyType.afterHoursActivity => tr('نشاط خارج ساعات العمل'),
    AnomalyType.highVoidRate => tr('معدل إلغاء عالي'),
    AnomalyType.unusualRefund => tr('مرتجع غير عادي'),
    AnomalyType.priceOverride => tr('تعديل أسعار متكرر'),
    AnomalyType.repeatedFailedLogin => tr('محاولات دخول فاشلة'),
    AnomalyType.bulkDeletion => tr('حذف جماعي'),
  };

  IconData get icon => switch (this) {
    AnomalyType.excessiveDiscount => PhosphorIconsBold.percent,
    AnomalyType.afterHoursActivity => PhosphorIconsBold.moon,
    AnomalyType.highVoidRate => PhosphorIconsBold.trash,
    AnomalyType.unusualRefund => PhosphorIconsBold.arrowUUpLeft,
    AnomalyType.priceOverride => PhosphorIconsBold.pencilSimpleLine,
    AnomalyType.repeatedFailedLogin => PhosphorIconsBold.lockKey,
    AnomalyType.bulkDeletion => PhosphorIconsBold.warning,
  };

  Color get color => switch (this) {
    AnomalyType.excessiveDiscount => Colors.orange,
    AnomalyType.afterHoursActivity => Colors.deepPurple,
    AnomalyType.highVoidRate => Colors.red,
    AnomalyType.unusualRefund => Colors.amber,
    AnomalyType.priceOverride => Colors.blue,
    AnomalyType.repeatedFailedLogin => Colors.red,
    AnomalyType.bulkDeletion => Colors.red,
  };
}

/// Severity level for detected anomalies
enum AnomalySeverity {
  low,
  medium,
  high,
  critical;

  String get labelAr => switch (this) {
    AnomalySeverity.low => tr('منخفض'),
    AnomalySeverity.medium => tr('متوسط'),
    AnomalySeverity.high => tr('عالي'),
    AnomalySeverity.critical => tr('حرج'),
  };

  Color get color => switch (this) {
    AnomalySeverity.low => Colors.grey,
    AnomalySeverity.medium => Colors.orange,
    AnomalySeverity.high => Colors.deepOrange,
    AnomalySeverity.critical => Colors.red,
  };
}

/// A detected anomaly record
class AnomalyAlert {
  final AnomalyType type;
  final AnomalySeverity severity;
  final String message;
  final DateTime detectedAt;
  final String? userName;
  final int? userId;
  final Map<String, dynamic>? metadata;

  const AnomalyAlert({
    required this.type,
    required this.severity,
    required this.message,
    required this.detectedAt,
    this.userName,
    this.userId,
    this.metadata,
  });
}

/// Service to detect and raise anomaly alerts
class AnomalyDetectionService {
  /// Thresholds (configurable)
  static const double maxDiscountPercent = 30.0;
  static const int maxVoidsPerShift = 5;
  static const int afterHoursStart = 23; // 11 PM
  static const int afterHoursEnd = 5; // 5 AM
  static const int maxFailedLogins = 5;

  /// Check if a discount is considered anomalous
  static AnomalyAlert? checkDiscount({
    required double discountPercent,
    required String userName,
    required int userId,
  }) {
    if (discountPercent > maxDiscountPercent) {
      return AnomalyAlert(
        type: AnomalyType.excessiveDiscount,
        severity: discountPercent > 50 ? AnomalySeverity.critical : AnomalySeverity.high,
        message: tr('خصم {p0}% بواسطة {p1}', {'p0': discountPercent, 'p1': userName}),
        detectedAt: DateTime.now(),
        userName: userName,
        userId: userId,
        metadata: {'discountPercent': discountPercent},
      );
    }
    return null;
  }

  /// Check if current time is outside business hours
  static AnomalyAlert? checkAfterHoursActivity({
    required String action,
    required String userName,
    required int userId,
  }) {
    final hour = DateTime.now().hour;
    if (hour >= afterHoursStart || hour < afterHoursEnd) {
      return AnomalyAlert(
        type: AnomalyType.afterHoursActivity,
        severity: AnomalySeverity.medium,
        message: tr('{p0} خارج ساعات العمل بواسطة {p1}', {'p0': action, 'p1': userName}),
        detectedAt: DateTime.now(),
        userName: userName,
        userId: userId,
        metadata: {'action': action, 'hour': hour},
      );
    }
    return null;
  }

  /// Check if void rate is too high
  static AnomalyAlert? checkVoidRate({
    required int voidsThisShift,
    required String userName,
    required int userId,
  }) {
    if (voidsThisShift >= maxVoidsPerShift) {
      return AnomalyAlert(
        type: AnomalyType.highVoidRate,
        severity: voidsThisShift > 10 ? AnomalySeverity.critical : AnomalySeverity.high,
        message: tr('{p0} عملية إلغاء في الوردية الحالية - {p1}', {'p0': voidsThisShift, 'p1': userName}),
        detectedAt: DateTime.now(),
        userName: userName,
        userId: userId,
        metadata: {'voidCount': voidsThisShift},
      );
    }
    return null;
  }
}

/// Widget to display anomaly alerts in a list
class AnomalyAlertCard extends StatelessWidget {
  final AnomalyAlert alert;
  final VoidCallback? onDismiss;

  const AnomalyAlertCard({super.key, required this.alert, this.onDismiss});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: alert.severity.color.withValues(alpha: 0.3)),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: alert.type.color.withValues(alpha: 0.1),
          child: Icon(alert.type.icon, size: 20, color: alert.type.color),
        ),
        title: Text(alert.type.labelAr, style: GoogleFonts.cairo(fontWeight: FontWeight.w600, fontSize: 13)),
        subtitle: Text(alert.message, style: GoogleFonts.cairo(fontSize: 11, color: AppColors.textMuted)),
        trailing: onDismiss != null
            ? IconButton(
                icon: const Icon(PhosphorIconsBold.x, size: 16),
                onPressed: onDismiss,
              )
            : Chip(
                label: Text(alert.severity.labelAr, style: const TextStyle(fontSize: 10, color: Colors.white)),
                backgroundColor: alert.severity.color,
                padding: EdgeInsets.zero,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
      ),
    );
  }
}
