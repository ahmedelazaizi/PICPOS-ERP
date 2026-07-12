// ═══════════════════════════════════════════════════════════════════════════
// C-02: Password Expiry & Rotation Service
// 90-day configurable password expiry with forced rotation
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../data/providers/providers.dart';

/// Settings key for password expiry days
const kPasswordExpiryDaysKey = 'password_expiry_days';

/// Default password expiry period
const kDefaultPasswordExpiryDays = 90;

/// Service to check and enforce password expiry
class PasswordExpiryService {

  /// Check if a user's password has expired.
  /// Returns the number of days since last change, or -1 if no record.
  static int daysSinceLastChange(DateTime? lastPasswordChange) {
    if (lastPasswordChange == null) return -1;
    return DateTime.now().difference(lastPasswordChange).inDays;
  }

  /// Check if password needs rotation
  static bool isExpired(DateTime? lastPasswordChange, int expiryDays) {
    if (expiryDays <= 0) return false; // Disabled
    if (lastPasswordChange == null) return true;
    return daysSinceLastChange(lastPasswordChange) >= expiryDays;
  }

  /// Days until expiry (negative = already expired)
  static int daysUntilExpiry(DateTime? lastPasswordChange, int expiryDays) {
    if (expiryDays <= 0) return 999; // Never expires
    if (lastPasswordChange == null) return 0;
    return expiryDays - daysSinceLastChange(lastPasswordChange);
  }
}

/// Provider for password expiry days setting
final passwordExpiryDaysProvider = FutureProvider<int>((ref) async {
  final settings = ref.watch(settingsRepositoryProvider);
  final value = await settings.getSetting(kPasswordExpiryDaysKey);
  return int.tryParse(value ?? '') ?? kDefaultPasswordExpiryDays;
});

/// Widget that shows a warning banner when password is about to expire or has expired
class PasswordExpiryBanner extends StatelessWidget {
  final DateTime? lastPasswordChange;
  final int expiryDays;
  final VoidCallback onChangePassword;

  const PasswordExpiryBanner({
    super.key,
    required this.lastPasswordChange,
    required this.expiryDays,
    required this.onChangePassword,
  });

  @override
  Widget build(BuildContext context) {
    if (expiryDays <= 0) return const SizedBox.shrink();

    final daysLeft = PasswordExpiryService.daysUntilExpiry(lastPasswordChange, expiryDays);

    if (daysLeft > 14) return const SizedBox.shrink(); // Not close to expiry

    final isExpired = daysLeft <= 0;
    final isWarning = daysLeft <= 14 && daysLeft > 0;

    if (!isExpired && !isWarning) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: isExpired ? Colors.red.shade50 : Colors.orange.shade50,
        border: Border(
          bottom: BorderSide(
            color: isExpired ? Colors.red.shade200 : Colors.orange.shade200,
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(
            isExpired ? PhosphorIconsBold.lockKey : PhosphorIconsBold.clockCountdown,
            color: isExpired ? Colors.red : Colors.orange,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              isExpired
                  ? 'كلمة المرور منتهية الصلاحية! يرجى تغييرها فوراً'
                  : 'كلمة المرور ستنتهي خلال $daysLeft يوم',
              style: GoogleFonts.cairo(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isExpired ? Colors.red.shade700 : Colors.orange.shade800,
              ),
            ),
          ),
          TextButton(
            onPressed: onChangePassword,
            child: Text(
              'تغيير الآن',
              style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}
