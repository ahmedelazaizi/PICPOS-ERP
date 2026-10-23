import 'package:picpos_erp/core/i18n/tr.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

/// Unified widget for handling [AsyncValue] from Riverpod providers.
///
/// Provides consistent loading, error, and data rendering across all screens.
/// Usage:
/// ```dart
/// AsyncValueWidget<List<Product>>(
///   value: ref.watch(productsProvider),
///   data: (products) => ListView(...),
/// )
/// ```
class AsyncValueWidget<T> extends StatelessWidget {
  /// The [AsyncValue] to render.
  final AsyncValue<T> value;

  /// Builder for the data state.
  final Widget Function(T data) data;

  /// Optional custom loading widget.
  final Widget? loading;

  /// Optional custom error widget builder.
  final Widget Function(Object error, StackTrace? stack)? error;

  /// If true, shows a loading overlay instead of replacing content during refresh.
  final bool showPreviousOnLoading;

  const AsyncValueWidget({
    super.key,
    required this.value,
    required this.data,
    this.loading,
    this.error,
    this.showPreviousOnLoading = true,
  });

  @override
  Widget build(BuildContext context) {
    return value.when(
      data: (d) {
        if (value.isRefreshing && !showPreviousOnLoading) {
          return loading ?? const AppLoadingIndicator();
        }
        return data(d);
      },
      loading: () => loading ?? const AppLoadingIndicator(),
      error: (e, s) =>
          error?.call(e, s) ??
          AppErrorWidget(
            message: e.toString(),
            onRetry: null,
          ),
    );
  }
}

/// Standardized loading indicator used across the app.
class AppLoadingIndicator extends StatelessWidget {
  final String? message;
  final double size;

  const AppLoadingIndicator({
    super.key,
    this.message,
    this.size = 32,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: size,
            height: size,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              color: theme.colorScheme.primary,
            ),
          ),
          if (message != null) ...[
            const SizedBox(height: 12),
            Text(
              message!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Standardized error display widget used across the app.
class AppErrorWidget extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;
  final IconData? icon;

  const AppErrorWidget({
    super.key,
    required this.message,
    this.onRetry,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon ?? PhosphorIconsBold.warning,
              size: 48,
              color: theme.colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(PhosphorIconsBold.arrowClockwise, size: 18),
                label:  Text(tr('إعادة المحاولة')),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Standardized empty state widget.
class AppEmptyState extends StatelessWidget {
  final String message;
  final IconData? icon;
  final Widget? action;

  const AppEmptyState({
    super.key,
    required this.message,
    this.icon,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon ?? PhosphorIconsBold.empty,
              size: 56,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (action != null) ...[
              const SizedBox(height: 20),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}
