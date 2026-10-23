import 'package:picpos_erp/core/i18n/tr.dart';
import 'package:picpos_erp/core/design_system/typography.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../theme/app_colors.dart';

/// Installs a friendly, in-place replacement for Flutter's default
/// `ErrorWidget` — the grey/red "exception caught by rendering library" box
/// (a bare black-on-yellow error string in release).
///
/// Call once from `main()`, before `runApp`.
///
/// Why a global builder and not a wrapper widget: Flutter offers no true
/// per-subtree error boundary for **build** failures. `ErrorWidget.builder` is
/// the single hook the framework consults when a widget's `build` throws, and
/// it replaces only the failing widget — the rest of the screen keeps working.
/// This file previously shipped an `AppErrorBoundary` widget that assigned
/// `ErrorWidget.builder` from inside its own `build()` (a global mutation
/// during build) and then blanked its **entire** subtree on any descendant
/// failure. It was never mounted anywhere, so in practice the app ran with no
/// handling at all: a build exception in any screen left Flutter's default
/// error box on screen with no way back except restarting the app. That widget
/// is replaced by this function.
///
/// `FlutterError.onError` in `main()` still records the full stack to the
/// diagnostic log; this only governs what the user sees.
void installGlobalErrorWidgetBuilder() {
  ErrorWidget.builder = (FlutterErrorDetails details) {
    // In debug, keep Flutter's own red box — it carries the full diagnostic
    // dump that developers rely on.
    if (kDebugMode) return ErrorWidget(details.exception);

    return _InlineErrorCard(details: details);
  };
}

/// Release-mode stand-in for a widget whose `build` threw. Deliberately
/// dependency-free (no Riverpod, no theme lookups, no `Directionality`
/// inheritance) — it must be able to render inside a subtree that is already
/// broken.
class _InlineErrorCard extends StatelessWidget {
  final FlutterErrorDetails details;

  const _InlineErrorCard({required this.details});

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        padding: const EdgeInsets.all(16),
        margin: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: AppColors.error.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.error.withValues(alpha: 0.35)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              PhosphorIconsBold.warningCircle,
              color: AppColors.error,
              size: 32,
            ),
            const SizedBox(height: 10),
             Text(
              tr('تعذّر عرض هذا الجزء من الشاشة'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 15,
                color: AppColors.error,
              ),
            ),
            const SizedBox(height: 6),
             Text(
              tr('باقي الشاشة يعمل بشكل طبيعي. ارجع للخلف ثم افتح الشاشة مرة أخرى. إذا تكرر الخطأ أرسل ملف السجل للدعم الفني.'),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
            const SizedBox(height: 8),
            Text(
              details.exceptionAsString(),
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 10,
                color: AppColors.textMuted,
                fontFamily: AppTypography.mono,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A professional error display widget with retry capability.
/// Can be used standalone or as part of AppErrorBoundary.
class AppErrorWidget extends StatelessWidget {
  final String title;
  final String? message;
  final VoidCallback? onRetry;
  final IconData icon;

  const AppErrorWidget({
    super.key,
    required this.title,
    this.message,
    this.onRetry,
    this.icon = PhosphorIconsBold.warningCircle,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Error icon with gradient background
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    AppColors.error.withValues(alpha: 0.12),
                    AppColors.error.withValues(alpha: 0.04),
                  ],
                ),
              ),
              child: Icon(
                icon,
                size: 36,
                color: AppColors.error.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
            if (message != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: AppColors.error.withValues(alpha: 0.1),
                  ),
                ),
                child: Text(
                  message!,
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textMuted.withValues(alpha: 0.8),
                    fontFamily: AppTypography.mono,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
            if (onRetry != null) ...[
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: onRetry,
                icon: const Icon(
                  PhosphorIconsBold.arrowCounterClockwise,
                  size: 18,
                ),
                label:  Text(tr('إعادة المحاولة')),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
