import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/config/brand.dart';
import '../../../core/theme/app_colors.dart';

/// Right-hand column: a display board, a secondary display area, and the
/// operations buttons.
///
/// The display board is what the customer-facing half of the counter sees on
/// a single-screen till. It currently shows the brand mark; wiring it to a
/// per-branch image playlist is a follow-up (the arrows already page through
/// whatever list it is given).
class PicPosSidePanel extends StatefulWidget {
  final List<PicPosOperation> operations;

  const PicPosSidePanel({super.key, required this.operations});

  @override
  State<PicPosSidePanel> createState() => _PicPosSidePanelState();
}

class PicPosOperation {
  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  const PicPosOperation({
    required this.label,
    required this.icon,
    required this.onPressed,
  });
}

class _PicPosSidePanelState extends State<PicPosSidePanel> {
  // Placeholder playlist — one entry today (the brand mark). Kept as a list
  // so the paging controls are real rather than decorative once a branch
  // supplies its own images.
  static const List<String> _slides = [Brand.logoAsset];
  int _slide = 0;

  void _page(int delta) {
    if (_slides.length < 2) return;
    setState(() {
      _slide = (_slide + delta) % _slides.length;
      if (_slide < 0) _slide += _slides.length;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(flex: 4, child: _buildDisplayBoard()),
        const SizedBox(height: 6),
        Expanded(flex: 3, child: _buildSecondaryArea()),
        const SizedBox(height: 6),
        _buildOperations(),
      ],
    );
  }

  Widget _buildDisplayBoard() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.primaryDark,
        border: Border.all(color: AppColors.border),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Image.asset(
              _slides[_slide],
              fit: BoxFit.contain,
              errorBuilder: (context, error, stack) => const Icon(
                PhosphorIconsBold.image,
                size: 40,
                color: Colors.white24,
              ),
            ),
          ),
          Positioned(
            bottom: 6,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _PagerButton(
                  icon: PhosphorIconsBold.caretRight,
                  enabled: _slides.length > 1,
                  onPressed: () => _page(-1),
                ),
                const SizedBox(width: 10),
                _PagerButton(
                  icon: PhosphorIconsBold.caretLeft,
                  enabled: _slides.length > 1,
                  onPressed: () => _page(1),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSecondaryArea() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(color: AppColors.border),
      ),
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(PhosphorIconsBold.monitor,
                size: 28, color: AppColors.textMuted),
            SizedBox(height: 6),
            Text(
              'منطقة عرض إضافية',
              style: TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOperations() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.all(6),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final op in widget.operations)
            SizedBox(
              width: 96,
              child: OutlinedButton(
                onPressed: op.onPressed,
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  side: const BorderSide(color: AppColors.border),
                  foregroundColor: AppColors.primaryDark,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(op.icon, size: 18),
                    const SizedBox(height: 3),
                    Text(
                      op.label,
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 11, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PagerButton extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final VoidCallback onPressed;

  const _PagerButton({
    required this.icon,
    required this.enabled,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.3,
      child: InkWell(
        onTap: enabled ? onPressed : null,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.15),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 16, color: Colors.white),
        ),
      ),
    );
  }
}
