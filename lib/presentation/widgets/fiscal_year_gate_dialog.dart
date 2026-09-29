import 'package:ural_erp/core/i18n/tr.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/config/brand.dart';
import '../../core/config/business_profile_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../data/providers/providers.dart';

/// Shows a blocking dialog when no fiscal year covers the current date.
/// The user must enter the developer/admin password to proceed to the
/// fiscal year management screen.
class FiscalYearGateDialog {
  FiscalYearGateDialog._();

  // Vendor contact info — from `Brand`, not hard-coded. A brand that
  // declares none hides the block entirely (see `Brand.vendorName`).
  static const String _developerCompany = Brand.vendorName;
  static const String _developerPhone = Brand.vendorPhone;
  static const String _developerEmail = Brand.vendorEmail;
  static const String _developerWebsite = Brand.vendorWebsite;

  /// Checks whether a valid fiscal year exists for today.
  /// If not, shows a blocking dialog.
  /// Call this from the main screen's initState/postFrameCallback.
  /// Returns true if the user authenticated and should navigate to fiscal year screen.
  /// Returns false if no issue was found or the user skipped.
  static Future<bool> check(BuildContext context, WidgetRef ref) async {
    try {
      final db = ref.read(databaseProvider);
      final currentFy = await db.getCurrentFiscalYear();
      final now = DateTime.now();

      String? message;

      if (currentFy == null) {
        // No fiscal year at all
        message =
            tr('لا توجد سنة مالية مفتوحة حالياً.\nيجب فتح سنة مالية جديدة لتتمكن من تسجيل العمليات.');
      } else if (currentFy.endDate.isBefore(now)) {
        // Fiscal year has expired
        message =
            tr('انتهت السنة المالية "{p0}" بتاريخ {p1}.\nيرجى التواصل مع الشركة المصممة لفتح سنة مالية جديدة.', {'p0': currentFy.name, 'p1': _formatDate(currentFy.endDate)});
      } else if (currentFy.isClosed) {
        // Fiscal year is closed
        message =
            tr('السنة المالية "{p0}" مغلقة.\nيرجى فتح سنة مالية جديدة لتتمكن من تسجيل العمليات.', {'p0': currentFy.name});
      }

      if (message == null) return false; // All good

      if (!context.mounted) return false;

      final result = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => _FiscalYearGateContent(message: message!),
      );
      return result == true;
    } catch (e) {
      // Don't block app launch on error — just log it
      debugPrint('[FiscalYearGate] Error checking fiscal year: $e');
      return false;
    }
  }

  static String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
}

class _FiscalYearGateContent extends ConsumerStatefulWidget {
  final String message;

  const _FiscalYearGateContent({required this.message});

  @override
  ConsumerState<_FiscalYearGateContent> createState() =>
      _FiscalYearGateContentState();
}

class _FiscalYearGateContentState
    extends ConsumerState<_FiscalYearGateContent> {
  final _passwordCtrl = TextEditingController();
  bool _obscure = true;
  String? _errorText;
  bool _verifying = false;

  @override
  void dispose() {
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    if (_verifying) return;
    final input = _passwordCtrl.text.trim();
    if (input.isEmpty) {
      setState(() => _errorText = tr('يرجى إدخال كلمة المرور'));
      return;
    }

    setState(() {
      _verifying = true;
      _errorText = null;
    });

    try {
      final devAuth = ref.read(developerAuthServiceProvider);
      if (!devAuth.isConfigured) {
        setState(() => _errorText = tr('لم يتم إعداد كلمة مرور المطور. يرجى التواصل مع الدعم الفني.'));
        return;
      }
      if (await devAuth.verify(input)) {
        if (mounted) Navigator.pop(context, true);
        return;
      }
      setState(() => _errorText = tr('كلمة المرور غير صحيحة'));
    } catch (e) {
      setState(() => _errorText = tr('خطأ في التحقق: {e}', {'e': e}));
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: Row(
          children: [
            const Icon(
              PhosphorIconsBold.calendarX,
              color: AppColors.error,
              size: 22,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                tr('تنبيه السنة المالية'),
                style: GoogleFonts.cairo(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Warning message
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: AppColors.error.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      PhosphorIconsBold.warning,
                      color: AppColors.error,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.message,
                        style: GoogleFonts.cairo(
                          fontSize: 13,
                          color: AppColors.error,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Vendor block — omitted entirely for brands with no vendor info.
              if (Brand.hasVendorInfo) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.2),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tr('بيانات الشركة المصممة:'),
                      style: GoogleFonts.cairo(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    _infoRow(PhosphorIconsBold.buildings,
                        FiscalYearGateDialog._developerCompany),
                    _infoRow(PhosphorIconsBold.phone,
                        FiscalYearGateDialog._developerPhone),
                    _infoRow(PhosphorIconsBold.envelope,
                        FiscalYearGateDialog._developerEmail),
                    _infoRow(PhosphorIconsBold.globe,
                        FiscalYearGateDialog._developerWebsite),
                  ],
                ),
              ),
              ],

              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 8),

              Text(
                tr('أدخل كلمة مرور المطور للانتقال لإدارة السنوات المالية:'),
                style: GoogleFonts.cairo(
                    fontSize: 12, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _passwordCtrl,
                obscureText: _obscure,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: tr('كلمة مرور المطور'),
                  prefixIcon: const Icon(PhosphorIconsBold.key, size: 18),
                  errorText: _errorText,
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscure
                          ? PhosphorIconsBold.eye
                          : PhosphorIconsBold.eyeSlash,
                      size: 18,
                    ),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onSubmitted: (_) => _verify(),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child:  Text(tr('تخطي')),
          ),
          ElevatedButton.icon(
            onPressed: _verifying ? null : _verify,
            icon: _verifying
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(PhosphorIconsBold.lockOpen, size: 16),
            label: Text(tr('فتح'), style: GoogleFonts.cairo()),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(icon, size: 14, color: AppColors.textSecondary),
          const SizedBox(width: 6),
          Text(
            text,
            style: GoogleFonts.cairo(
                fontSize: 12, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}
