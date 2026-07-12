// ═══════════════════════════════════════════════════════════════════════════
// AppStateView — Day 11 PIR: Unified Loading / Error / Empty / Content states
// ═══════════════════════════════════════════════════════════════════════════
//
// Every list screen went through the same three-state pattern independently:
//   if (isLoading) → shimmer
//   if (error)     → red text
//   if (isEmpty)   → custom empty illustration
//   else           → content
//
// This file centralises that into a single widget so each screen only needs
// to describe its data state, not the rendering of each branch.
//
// Usage:
//   AppStateView(
//     isLoading: state.isLoading,
//     isEmpty: state.invoices.isEmpty,
//     emptyMessage: 'لا توجد فواتير',
//     child: MyList(state.invoices),
//   )
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../theme/app_colors.dart';
import 'app_empty_state.dart';
import 'shimmer_loading.dart';

// ── Sub-views ──────────────────────────────────────────────────────────────

/// Standard loading placeholder — matches the shimmer style used site-wide.
class AppLoadingView extends StatelessWidget {
  final int itemCount;
  final EdgeInsetsGeometry padding;

  const AppLoadingView({
    super.key,
    this.itemCount = 6,
    this.padding = const EdgeInsets.all(16),
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: padding,
        child: ShimmerLoading.list(itemCount: itemCount),
      );
}

/// Standard error display — shows a red-tinted card with a retry button.
class AppErrorView extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;

  const AppErrorView({
    super.key,
    required this.message,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: AppColors.error.withValues(alpha: 0.25)),
                ),
                child: Column(
                  children: [
                    const Icon(PhosphorIconsBold.warningCircle,
                        color: AppColors.error, size: 40),
                    const SizedBox(height: 12),
                    Text(
                      message,
                      style: const TextStyle(
                        color: AppColors.error,
                        fontSize: 14,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              if (onRetry != null) ...[
                const SizedBox(height: 16),
                TextButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(PhosphorIconsBold.arrowClockwise),
                  label: const Text('إعادة المحاولة'),
                ),
              ],
            ],
          ),
        ),
      );
}

/// Standard empty-state placeholder — wraps the existing `AppEmptyState`.
class AppEmptyView extends StatelessWidget {
  final String message;
  final IconData? icon;
  final String? description;
  final String? actionLabel;
  final VoidCallback? onAction;

  const AppEmptyView({
    super.key,
    required this.message,
    this.icon,
    this.description,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) => AppEmptyState(
        icon: icon ?? PhosphorIconsBold.tray,
        title: message,
        description: description,
        actionLabel: actionLabel,
        onAction: onAction,
      );
}

// ── Orchestrator ───────────────────────────────────────────────────────────

/// Unified widget that selects the right sub-view based on the data state.
///
/// Priority order: loading → error → empty → [child].
///
/// ```dart
/// AppStateView(
///   isLoading: state.isLoading,
///   error: state.errorMessage,
///   isEmpty: state.items.isEmpty,
///   emptyMessage: 'لا توجد فواتير',
///   child: InvoiceList(state.items),
/// )
/// ```
class AppStateView extends StatelessWidget {
  final bool isLoading;
  final String? error;
  final bool isEmpty;
  final String emptyMessage;
  final Widget child;

  // Customisation pass-throughs
  final int loadingItemCount;
  final IconData? emptyIcon;
  final String? emptyDescription;
  final String? emptyActionLabel;
  final VoidCallback? onEmptyAction;
  final VoidCallback? onRetry;

  const AppStateView({
    super.key,
    required this.isLoading,
    required this.isEmpty,
    required this.emptyMessage,
    required this.child,
    this.error,
    this.loadingItemCount = 6,
    this.emptyIcon,
    this.emptyDescription,
    this.emptyActionLabel,
    this.onEmptyAction,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    if (isLoading) return AppLoadingView(itemCount: loadingItemCount);
    if (error != null) return AppErrorView(message: error!, onRetry: onRetry);
    if (isEmpty) {
      return AppEmptyView(
        message: emptyMessage,
        icon: emptyIcon,
        description: emptyDescription,
        actionLabel: emptyActionLabel,
        onAction: onEmptyAction,
      );
    }
    return child;
  }
}
