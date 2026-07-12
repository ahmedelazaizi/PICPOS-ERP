import 'core/utils/platform_init.dart';

/// Initialize web-specific features
Future<void> initPlatform() async {
  // Supabase is already initialized in main.dart
  initFileUtils();
}

bool isDesktop() => false;

void exitApp() {
  // No-op on web or maybe window.close() if allowed
}

/// No-op on web - scales only work on desktop
Future<void> autoConnectScale() async {
  // Scale connection not available on web
}

/// No-op on web - keyboard is handled by browser
void showTouchKeyboard() {
  // Touch keyboard not needed on web
}

/// No-op on web - server/client mode only works on desktop
Future<void> autoStartNetworkServer(dynamic db) async {
  // Network server not available on web
}

/// No-op on web - sync only works on desktop
Future<void> autoSyncIfClient(dynamic db) async {
  // Client sync not available on web
}

/// No-op on web — PostgreSQL offline fallback is desktop-only
void startOfflineReconnectionTimer() {}

/// Web stub — always false
bool pgServerReachable = false;

/// Web stub — always returns a null-safe stub; server mode is desktop-only
dynamic getNetworkService() => _WebNetworkServiceStub();

class _WebNetworkServiceStub {
  bool get isServer => false;
}
