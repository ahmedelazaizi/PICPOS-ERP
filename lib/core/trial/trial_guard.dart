import 'package:flutter/material.dart';
import '../../services/license_service.dart';

/// A widget that guards access based on the trial policy.
///
/// Wraps a child widget and checks if the feature is available.
/// If the trial has expired or the feature is locked, shows a prompt.
class TrialGuard extends StatelessWidget {
  /// The child widget to show when access is granted
  final Widget child;

  /// Optional screen index to check if locked
  final int? screenIndex;

  /// Whether to block on trial expiry
  final bool checkExpiry;

  /// Custom message for blocked state
  final String? blockedMessage;

  const TrialGuard({
    super.key,
    required this.child,
    this.screenIndex,
    this.checkExpiry = true,
    this.blockedMessage,
  });

  @override
  Widget build(BuildContext context) {
    // Full version — no restrictions
    if (LicenseService.isActivatedCached) {
      return child;
    }

    // Check trial expiry
    if (checkExpiry && LicenseService.isTrialExpired) {
      return _buildBlockedWidget(
        context,
        icon: Icons.timer_off_rounded,
        title: 'انتهت الفترة التجريبية',
        message: blockedMessage ??
            'انتهت فترة التجربة المجانية.\nيرجى التواصل مع الدعم للحصول على مفتاح التفعيل.',
      );
    }

    // Check screen lock
    if (screenIndex != null && LicenseService.isScreenLocked(screenIndex!)) {
      return _buildBlockedWidget(
        context,
        icon: Icons.lock_rounded,
        title: 'ميزة مقفلة',
        message: blockedMessage ??
            'هذه الميزة غير متوفرة في النسخة التجريبية.\nقم بتفعيل النسخة الكاملة للوصول لجميع الميزات.',
      );
    }

    return child;
  }

  Widget _buildBlockedWidget(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String message,
  }) {
    final theme = Theme.of(context);
    final remainingDays = LicenseService.getRemainingTrialDays();

    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 420),
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: theme.colorScheme.error),
            const SizedBox(height: 16),
            Text(
              title,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.error,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              message,
              style: theme.textTheme.bodyLarge,
              textAlign: TextAlign.center,
            ),
            if (remainingDays >= 0) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: remainingDays > 7
                      ? Colors.orange.withAlpha(25)
                      : Colors.red.withAlpha(25),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'الأيام المتبقية: $remainingDays يوم',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: remainingDays > 7 ? Colors.orange : Colors.red,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => _showActivationDialog(context),
              icon: const Icon(Icons.key_rounded),
              label: const Text('تفعيل النسخة الكاملة'),
            ),
          ],
        ),
      ),
    );
  }

  void _showActivationDialog(BuildContext context) {
    // Navigate to settings screen where activation is handled
    Navigator.of(context).popUntil((route) => route.isFirst);
    // The user can activate from the settings screen
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('يرجى الذهاب للإعدادات → الترخيص لتفعيل النسخة الكاملة'),
        duration: Duration(seconds: 4),
      ),
    );
  }
}

/// A banner widget that shows trial status at the top of the app
class TrialBanner extends StatelessWidget {
  const TrialBanner({super.key});

  @override
  Widget build(BuildContext context) {
    if (!LicenseService.isTrial) return const SizedBox.shrink();

    final remainingDays = LicenseService.getRemainingTrialDays();
    final isExpiring = remainingDays >= 0 && remainingDays <= 7;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isExpiring
              ? [Colors.red.shade700, Colors.red.shade500]
              : [Colors.orange.shade700, Colors.amber.shade600],
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            isExpiring ? Icons.warning_rounded : Icons.info_outline_rounded,
            size: 16,
            color: Colors.white,
          ),
          const SizedBox(width: 8),
          Text(
            remainingDays >= 0
                ? 'نسخة تجريبية — متبقي $remainingDays يوم'
                : 'نسخة تجريبية',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
