import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/config/brand.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/providers/providers.dart';

/// Top strip: logo · clock/date · user · POS name · held invoices.
class PicPosTopBar extends ConsumerWidget {
  final VoidCallback onHeldOrders;
  final VoidCallback onBack;
  final bool showBackButton;

  const PicPosTopBar({
    super.key,
    required this.onHeldOrders,
    required this.onBack,
    this.showBackButton = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider).effectiveUser;
    final heldCount = ref.watch(heldOrdersProvider).value?.length ?? 0;

    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.primaryDark, AppColors.primary],
          begin: Alignment.centerRight,
          end: Alignment.centerLeft,
        ),
      ),
      child: Row(
        children: [
          if (showBackButton)
            IconButton(
              onPressed: onBack,
              icon: const Icon(PhosphorIconsBold.arrowRight,
                  color: Colors.white),
              tooltip: 'رجوع',
            ),
          // Logo comes from Brand so this bar never hard-codes a product.
          Image.asset(
            Brand.logoAsset,
            height: 36,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stack) => const SizedBox.shrink(),
          ),
          const SizedBox(width: 16),
          const _ClockBlock(),
          const Spacer(),
          _InfoChip(
            icon: PhosphorIconsBold.user,
            label: user?.displayName ?? 'مستخدم',
          ),
          const SizedBox(width: 8),
          const _InfoChip(
            icon: PhosphorIconsBold.storefront,
            label: 'نقطة البيع',
          ),
          const SizedBox(width: 8),
          _HeldOrdersButton(count: heldCount, onPressed: onHeldOrders),
        ],
      ),
    );
  }
}

/// Live clock. Ticks on its own timer rather than rebuilding the whole bar —
/// a POS screen sits open all day, so a per-second rebuild of the header (and
/// everything it watches) is not free.
class _ClockBlock extends StatefulWidget {
  const _ClockBlock();

  @override
  State<_ClockBlock> createState() => _ClockBlockState();
}

class _ClockBlockState extends State<_ClockBlock> {
  late DateTime _now = DateTime.now();
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _two(int v) => v.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    final time = '${_two(_now.hour)}:${_two(_now.minute)}:${_two(_now.second)}';
    final date = '${_now.year}/${_two(_now.month)}/${_two(_now.day)}';
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          time,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
            // Tabular figures stop the clock from jittering as digits change.
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
        Text(
          date,
          style: const TextStyle(color: Colors.white70, fontSize: 11),
        ),
      ],
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _InfoChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: Colors.white),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _HeldOrdersButton extends StatelessWidget {
  final int count;
  final VoidCallback onPressed;

  const _HeldOrdersButton({required this.count, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: count > 0
              ? AppColors.warning
              : Colors.white.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(PhosphorIconsBold.pauseCircle,
                size: 16, color: Colors.white),
            const SizedBox(width: 6),
            Text(
              'فواتير معلقة ($count)',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
