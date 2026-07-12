import 'package:flutter/material.dart';

/// A transparent wrapper that monitors server connection health in client mode.
/// Does NOT block the UI or show any disruptive notifications.
/// Connection status is only shown in the Settings > Network screen.
/// Data sync is handled by periodic HTTP polling (every 30s) in main_desktop.
class ConnectionHealthWrapper extends StatelessWidget {
  final Widget child;
  const ConnectionHealthWrapper({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    // Pass child through directly — no overlays, no banners, no disruption.
    // Connection health is monitored silently via periodic sync in main_desktop.
    return child;
  }
}
