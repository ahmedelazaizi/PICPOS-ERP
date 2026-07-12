import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../theme/app_colors.dart';

/// A widget that catches errors in its child widget tree and shows a
/// user-friendly fallback instead of crashing the entire app.
///
/// Usage:
/// ```dart
/// AppErrorBoundary(
///   child: SomeWidgetThatMightFail(),
/// )
/// ```
class AppErrorBoundary extends StatefulWidget {
  final Widget child;
  final String? title;
  final VoidCallback? onRetry;

  const AppErrorBoundary({
    super.key,
    required this.child,
    this.title,
    this.onRetry,
  });

  @override
  State<AppErrorBoundary> createState() => _AppErrorBoundaryState();
}

class _AppErrorBoundaryState extends State<AppErrorBoundary> {
  bool _hasError = false;
  FlutterErrorDetails? _errorDetails;

  @override
  void initState() {
    super.initState();
  }

  void _handleError(FlutterErrorDetails details) {
    setState(() {
      _hasError = true;
      _errorDetails = details;
    });
  }

  void _retry() {
    setState(() {
      _hasError = false;
      _errorDetails = null;
    });
    widget.onRetry?.call();
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      return AppErrorWidget(
        title: widget.title ?? 'حدث خطأ غير متوقع',
        message: _errorDetails?.exceptionAsString() ?? 'خطأ غير معروف',
        onRetry: _retry,
      );
    }

    return _ErrorCatcher(onError: _handleError, child: widget.child);
  }
}

class _ErrorCatcher extends StatelessWidget {
  final Widget child;
  final void Function(FlutterErrorDetails) onError;

  const _ErrorCatcher({required this.child, required this.onError});

  @override
  Widget build(BuildContext context) {
    // Use ErrorWidget.builder to catch build errors
    ErrorWidget.builder = (FlutterErrorDetails details) {
      // Schedule the error handling after the current frame
      WidgetsBinding.instance.addPostFrameCallback((_) {
        onError(details);
      });
      return const SizedBox.shrink();
    };
    return child;
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
                    fontFamily: 'monospace',
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
                label: const Text('إعادة المحاولة'),
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
