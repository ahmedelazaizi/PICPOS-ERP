// ═══════════════════════════════════════════════════════════════════════════
// C-07: Two-Person Rule for High-Value Operations
// Requires a second approver for operations above configurable thresholds
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../core/theme/app_colors.dart';
import '../data/providers/providers.dart';

/// Operations that can require two-person approval
enum DualApprovalOperation {
  refundAboveThreshold,
  discountAboveThreshold,
  voidInvoice,
  priceOverride,
  stockWriteOff,
  deleteTransaction,
  userRoleChange;

  String get labelAr => switch (this) {
    DualApprovalOperation.refundAboveThreshold => 'مرتجع فوق الحد',
    DualApprovalOperation.discountAboveThreshold => 'خصم فوق الحد',
    DualApprovalOperation.voidInvoice => 'إلغاء فاتورة',
    DualApprovalOperation.priceOverride => 'تعديل سعر',
    DualApprovalOperation.stockWriteOff => 'شطب مخزون',
    DualApprovalOperation.deleteTransaction => 'حذف عملية',
    DualApprovalOperation.userRoleChange => 'تغيير صلاحيات مستخدم',
  };
}

/// Service to enforce two-person approval for high-value operations
class DualApprovalService {
  /// Default thresholds (configurable via settings)
  static const double defaultRefundThreshold = 5000;
  static const double defaultDiscountThreshold = 20; // percent

  /// Show dual approval dialog requiring a second user's credentials
  /// Returns true if approved, false if denied/cancelled
  static Future<bool> requestApproval(
    BuildContext context, {
    required DualApprovalOperation operation,
    required String requestedBy,
    required String details,
    required Future<bool> Function(String username, String password) verifier,
  }) async {
    final usernameController = TextEditingController();
    final passwordController = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: StatefulBuilder(
          builder: (context, setState) {
            String? error;
            bool isVerifying = false;

            return AlertDialog(
              title: Row(
                children: [
                  const Icon(PhosphorIconsBold.shieldCheck, color: AppColors.warning, size: 24),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('مطلوب موافقة ثنائية',
                        style: GoogleFonts.cairo(fontWeight: FontWeight.w700, fontSize: 15)),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Operation info
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.warning.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.warning.withValues(alpha: 0.2)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('العملية: ${operation.labelAr}',
                            style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.w600)),
                        Text('بواسطة: $requestedBy',
                            style: GoogleFonts.cairo(fontSize: 11, color: AppColors.textMuted)),
                        Text('التفاصيل: $details',
                            style: GoogleFonts.cairo(fontSize: 11, color: AppColors.textMuted)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text('يرجى إدخال بيانات المعتمد الثاني:',
                      style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: usernameController,
                    decoration: InputDecoration(
                      labelText: 'اسم المستخدم',
                      prefixIcon: const Icon(PhosphorIconsBold.user, size: 18),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: passwordController,
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: 'كلمة المرور',
                      prefixIcon: const Icon(PhosphorIconsBold.lock, size: 18),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      isDense: true,
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('إلغاء'),
                ),
                ElevatedButton.icon(
                  onPressed: isVerifying
                      ? null
                      : () async {
                          setState(() {
                            isVerifying = true;
                            error = null;
                          });
                          final ok = await verifier(
                            usernameController.text,
                            passwordController.text,
                          );
                          if (ok) {
                            if (ctx.mounted) Navigator.pop(ctx, true);
                          } else {
                            setState(() {
                              isVerifying = false;
                              error = 'بيانات غير صحيحة أو غير مصرح';
                            });
                          }
                        },
                  icon: isVerifying
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(PhosphorIconsBold.shieldCheck, size: 18),
                  label: Text('اعتماد', style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.success,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );

    return result ?? false;
  }

  /// 063 (D1-005) — settings-gated dual-approval check.
  ///
  /// Looks up the setting `dual_approval_<op>_enabled` (default `false` =
  /// disabled, no dialog shown — preserves current UX). When `true`, pops
  /// [requestApproval] with a verifier that authenticates the second user
  /// via [AuthRepository.authenticateUser]. Returns true iff:
  ///   - the setting is OFF (auto-pass — no dual approval required), OR
  ///   - the setting is ON AND a valid second user authenticated.
  ///
  /// The second-user verification also blocks the same user as the
  /// requester — you cannot "approve your own action". Comparison uses
  /// the authenticated user's id vs the current logged-in user's id.
  ///
  /// Settings management UI for these flags is out of scope (future spec).
  /// To enable manually for testing:
  ///   `await ref.read(databaseProvider).setSettingValue(
  ///       'dual_approval_void_invoice_enabled', 'true');`
  static Future<bool> requireApprovalForOp(
    BuildContext context,
    WidgetRef ref, {
    required DualApprovalOperation operation,
    required String details,
  }) async {
    final settingKey = 'dual_approval_${operation.name}_enabled';
    final db = ref.read(databaseProvider);
    final flag = await db.getSettingValue(settingKey);
    if (flag != 'true') {
      // Setting OFF — auto-pass.
      return true;
    }

    final auth = ref.read(authProvider);
    final requesterId = auth.user?.id;
    final requesterName = auth.user?.displayName ?? 'مستخدم';
    final authRepo = ref.read(authRepositoryProvider);

    if (!context.mounted) return false;
    return requestApproval(
      context,
      operation: operation,
      requestedBy: requesterName,
      details: details,
      verifier: (username, password) async {
        try {
          final approver = await authRepo.authenticateUser(username, password);
          if (approver == null) return false;
          // Refuse self-approval — must be a DIFFERENT user.
          if (requesterId != null && approver.user.id == requesterId) {
            return false;
          }
          return true;
        } catch (_) {
          // Rate-limit lockout or unexpected error → treat as denied.
          return false;
        }
      },
    );
  }
}
