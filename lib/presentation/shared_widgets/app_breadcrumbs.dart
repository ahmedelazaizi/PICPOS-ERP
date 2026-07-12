import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../core/theme/app_colors.dart';
import '../providers/breadcrumb_provider.dart';
import '../widgets/notifications/notification_bell.dart';

class AppBreadcrumbs extends ConsumerWidget {
  final VoidCallback? onHomeTap;
  const AppBreadcrumbs({super.key, this.onHomeTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final breadcrumbs = ref.watch(breadcrumbProvider);
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor.withValues(alpha: 0.5),
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).dividerColor.withValues(alpha: 0.1),
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Row(
              children: [
                // Home button
                InkWell(
                  onTap: () {
                    ref.read(breadcrumbProvider.notifier).clear();
                    onHomeTap?.call();
                  },
                  borderRadius: BorderRadius.circular(4),
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(
                      PhosphorIconsBold.house,
                      size: 16,
                      color: AppColors.textMuted,
                    ),
                  ),
                ),
                // Breadcrumbs trail — only if non-empty
                if (breadcrumbs.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: breadcrumbs.asMap().entries.map((entry) {
                          final index = entry.key;
                          final item = entry.value;
                          final isLast = index == breadcrumbs.length - 1;

                          return Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                PhosphorIconsBold.caretLeft,
                                size: 14,
                                color: AppColors.textMuted,
                              ),
                              const SizedBox(width: 4),
                              InkWell(
                                onTap: isLast ? null : item.onTap,
                                borderRadius: BorderRadius.circular(4),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  child: Text(
                                    item.label,
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: isLast ? AppColors.primary : AppColors.textMuted,
                                      fontWeight: isLast ? FontWeight.bold : FontWeight.normal,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 16),
          const NotificationBell(),
        ],
      ),
    );
  }
}
