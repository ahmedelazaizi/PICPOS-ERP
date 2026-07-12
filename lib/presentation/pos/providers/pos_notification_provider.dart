import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A single POS notification entry
class PosNotification {
  final String message;
  final DateTime timestamp;
  final PosNotificationType type;
  final bool isRead;

  const PosNotification({
    required this.message,
    required this.timestamp,
    this.type = PosNotificationType.success,
    this.isRead = false,
  });

  PosNotification copyWith({bool? isRead}) => PosNotification(
    message: message,
    timestamp: timestamp,
    type: type,
    isRead: isRead ?? this.isRead,
  );
}

enum PosNotificationType { success, error, warning, info }

/// Notifier for POS notifications (Riverpod 2 Notifier API)
class PosNotificationNotifier extends Notifier<List<PosNotification>> {
  @override
  List<PosNotification> build() => [];

  /// Add a notification
  void add(
    String message, {
    PosNotificationType type = PosNotificationType.success,
  }) {
    state = [
      PosNotification(message: message, timestamp: DateTime.now(), type: type),
      ...state,
    ];
    // Keep only last 50 notifications
    if (state.length > 50) {
      state = state.sublist(0, 50);
    }
  }

  void markAllRead() {
    state = state.map((n) => n.copyWith(isRead: true)).toList();
  }

  void clear() {
    state = [];
  }
}

/// Provider for POS notifications
final posNotificationsProvider =
    NotifierProvider<PosNotificationNotifier, List<PosNotification>>(
      PosNotificationNotifier.new,
    );

/// Helper for showing POS notification from BuildContext + WidgetRef
/// This replaces ScaffoldMessenger.of(context).showSnackBar(...)
void showPosToast(
  BuildContext context,
  WidgetRef ref,
  String message, {
  PosNotificationType type = PosNotificationType.success,
}) {
  // Add to notification list
  ref.read(posNotificationsProvider.notifier).add(message, type: type);

  // Show a brief overlay toast at the top instead of bottom snackbar
  final overlay = Overlay.of(context);
  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (context) => _PosToastWidget(
      message: message,
      type: type,
      onDismiss: () => entry.remove(),
    ),
  );
  overlay.insert(entry);
}

class _PosToastWidget extends StatefulWidget {
  final String message;
  final PosNotificationType type;
  final VoidCallback onDismiss;

  const _PosToastWidget({
    required this.message,
    required this.type,
    required this.onDismiss,
  });

  @override
  State<_PosToastWidget> createState() => _PosToastWidgetState();
}

class _PosToastWidgetState extends State<_PosToastWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

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

    // Auto-dismiss after 2.5 seconds
    Future.delayed(const Duration(milliseconds: 2500), () {
      if (mounted) {
        _controller.reverse().then((_) {
          if (mounted) widget.onDismiss();
        });
      }
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
      PosNotificationType.success => const Color(0xFF2E7D32),
      PosNotificationType.error => const Color(0xFFC62828),
      PosNotificationType.warning => const Color(0xFFF57F17),
      PosNotificationType.info => const Color(0xFF1565C0),
    };

    final icon = switch (widget.type) {
      PosNotificationType.success => Icons.check_circle_rounded,
      PosNotificationType.error => Icons.error_rounded,
      PosNotificationType.warning => Icons.warning_rounded,
      PosNotificationType.info => Icons.info_rounded,
    };

    return Positioned(
      top: 70,
      right: 16,
      child: SlideTransition(
        position: _slideAnimation,
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: Material(
            color: Colors.transparent,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 360),
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
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
