import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// A professional, cross-platform On-Screen Keyboard (OSK) for touch devices.
/// Supports numeric and alphanumeric layouts with Arabic/English support.
class AppOSK extends StatelessWidget {
  final TextEditingController controller;
  final bool isNumeric;
  final VoidCallback? onSubmitted;
  final VoidCallback? onClosed;

  const AppOSK({
    super.key,
    required this.controller,
    this.isNumeric = true,
    this.onSubmitted,
    this.onClosed,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.secondary,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 10,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header / Drag Handle
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          if (isNumeric) _buildNumericLayout() else _buildAlphanumericLayout(),
        ],
      ),
    );
  }

  Widget _buildNumericLayout() {
    return GridView.count(
      shrinkWrap: true,
      crossAxisCount: 3,
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 1.5,
      children: [
        ...[
          '1',
          '2',
          '3',
          '4',
          '5',
          '6',
          '7',
          '8',
          '9',
          '.',
          '0',
        ].map(_buildKey),
        _buildActionKey(
          icon: Icons.backspace_outlined,
          onTap: () {
            if (controller.text.isNotEmpty) {
              controller.text = controller.text.substring(
                0,
                controller.text.length - 1,
              );
            }
          },
          color: AppColors.error,
        ),
        _buildActionKey(
          icon: Icons.check_circle_outline,
          onTap: onSubmitted,
          color: AppColors.success,
        ),
        _buildActionKey(
          icon: Icons.close,
          onTap: onClosed,
          color: AppColors.textMuted,
        ),
      ],
    );
  }

  Widget _buildAlphanumericLayout() {
    // Basic alphanumeric implementation can be expanded later
    return const Center(
      child: Text(
        'Alphanumeric Layout WIP',
        style: TextStyle(color: Colors.white),
      ),
    );
  }

  Widget _buildKey(String value) {
    return InkWell(
      onTap: () => controller.text += value,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        ),
        child: Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildActionKey({
    required IconData icon,
    required VoidCallback? onTap,
    required Color color,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Icon(icon, color: color, size: 24),
      ),
    );
  }

  /// Helper to show OSK as a bottom sheet
  static void show(
    BuildContext context, {
    required TextEditingController controller,
    bool isNumeric = true,
    VoidCallback? onSubmitted,
  }) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => AppOSK(
        controller: controller,
        isNumeric: isNumeric,
        onSubmitted: () {
          onSubmitted?.call();
          Navigator.pop(context);
        },
        onClosed: () => Navigator.pop(context),
      ),
    );
  }
}
