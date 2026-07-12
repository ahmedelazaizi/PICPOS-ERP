import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../services/scale_service.dart';

class PosStatusIndicators extends ConsumerWidget {
  final bool showScaleIndicator;

  const PosStatusIndicators({super.key, required this.showScaleIndicator});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Scale connection indicator
        if (showScaleIndicator)
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: ScaleService.instance.isConnected
                    ? AppColors.success.withValues(alpha: 0.2)
                    : Colors.white10,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: ScaleService.instance.isConnected
                      ? AppColors.success
                      : Colors.white.withValues(alpha: 0.1),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    PhosphorIconsBold.scales,
                    color: ScaleService.instance.isConnected
                        ? AppColors.success
                        : Colors.white54,
                    size: 16,
                  ),
                  const SizedBox(width: 6),
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: ScaleService.instance.isConnected
                          ? AppColors.success
                          : Colors.white30,
                    ),
                  ),
                ],
              ),
            ),
          ),

        // Cloud Sync Status — placeholder (SyncWorker not yet wired)
        const SizedBox.shrink(),
      ],
    );
  }
}
