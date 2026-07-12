import 'package:flutter/material.dart';

/// Universal App Toast — replaces ScaffoldMessenger.showSnackBar everywhere.
/// Shows a brief, animated overlay toast at the top of the screen.
///
/// Usage:
///   AppToast.show(context, 'تم الحفظ بنجاح');
///   AppToast.show(context, 'خطأ!', type: ToastType.error);
///   AppToast.show(context, 'يجب ربط الحسابات', type: ToastType.error,
///       actionLabel: 'ربط الآن', onAction: () => navigateToMapping());
class AppToast {
  AppToast._();

  static void show(
    BuildContext context,
    String message, {
    ToastType type = ToastType.success,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    final overlay = Overlay.of(context);
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (context) => _ToastOverlay(
        message: message,
        type: type,
        actionLabel: actionLabel,
        onAction: onAction,
        onDismiss: () {
          entry.remove();
        },
      ),
    );
    overlay.insert(entry);
  }
}

enum ToastType { success, error, warning, info }

class _ToastOverlay extends StatefulWidget {
  final String message;
  final ToastType type;
  final String? actionLabel;
  final VoidCallback? onAction;
  final VoidCallback onDismiss;

  const _ToastOverlay({
    required this.message,
    required this.type,
    this.actionLabel,
    this.onAction,
    required this.onDismiss,
  });

  @override
  State<_ToastOverlay> createState() => _ToastOverlayState();
}

class _ToastOverlayState extends State<_ToastOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  bool _dismissed = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, -1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));

    _controller.forward();

    // Longer display when there's an action button (5s vs 2.5s)
    final duration = widget.actionLabel != null
        ? const Duration(milliseconds: 5000)
        : const Duration(milliseconds: 2500);

    Future.delayed(duration, () {
      _dismiss();
    });
  }

  void _dismiss() {
    if (_dismissed || !mounted) return;
    _dismissed = true;
    _controller.reverse().then((_) {
      if (mounted) widget.onDismiss();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = switch (widget.type) {
      ToastType.success => const Color(0xFF2E7D32),
      ToastType.error => const Color(0xFFC62828),
      ToastType.warning => const Color(0xFFF57F17),
      ToastType.info => const Color(0xFF1565C0),
    };

    final icon = switch (widget.type) {
      ToastType.success => Icons.check_circle_rounded,
      ToastType.error => Icons.error_rounded,
      ToastType.warning => Icons.warning_rounded,
      ToastType.info => Icons.info_rounded,
    };

    return Positioned(
      top: 16,
      right: 16,
      child: SlideTransition(
        position: _slideAnimation,
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: Material(
            color: Colors.transparent,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 440),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: 0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, color: Colors.white, size: 20),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      widget.message,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (widget.actionLabel != null) ...[
                    const SizedBox(width: 10),
                    const SizedBox(
                      height: 20,
                      child: VerticalDivider(
                          color: Colors.white38, thickness: 1, width: 1),
                    ),
                    const SizedBox(width: 6),
                    InkWell(
                      onTap: () {
                        _dismiss();
                        widget.onAction?.call();
                      },
                      borderRadius: BorderRadius.circular(4),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        child: Text(
                          widget.actionLabel!,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            decoration: TextDecoration.underline,
                            decorationColor: Colors.white70,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
