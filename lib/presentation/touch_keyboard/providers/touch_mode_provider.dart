// ═══════════════════════════════════════════════════════════════════════════
// TOUCH MODE PROVIDER — Feature 031
// ═══════════════════════════════════════════════════════════════════════════
//
// Per-device boolean preference. When true, the global FocusManager listener
// in `_TouchKeyboardWrapper` mounts the on-screen touch keyboard on every
// text-input focus event. When false (the default), the listener early-
// returns and no keyboard ever appears — Constitution Principle I, SC-007.
//
// The setting is persisted in the encrypted `settings` table via
// `SettingsRepositoryCached` (key `'touchMode'`). It is excluded from
// multi-device sync by `SettingSyncStrategy.devSpecificKeys` so toggling
// on one device does not propagate to others (FR-019).
//
// Read path: synchronous after the startup `preload(['touchMode'])` call
// in `lib/main.dart`. Cold reads (e.g., before preload) return `false`.
//
// Write path: `setTouchMode(ref, enabled)` writes through the cached repo
// then refreshes the provider so any focus listener observes the new
// value on its next event without an app restart (FR-020).
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/business_profile_provider.dart'
    show settingsRepositoryCachedProvider;

const String touchModeSettingKey = 'touchMode';

class TouchModeNotifier extends Notifier<bool> {
  @override
  bool build() {
    final repo = ref.watch(settingsRepositoryCachedProvider);
    final raw = repo.get(touchModeSettingKey);
    return raw == 'true';
  }

  /// Persist the new value through the cached repository and update
  /// provider state so the focus listener sees it on the next event.
  Future<void> set(bool enabled) async {
    final repo = ref.read(settingsRepositoryCachedProvider);
    await repo.save(touchModeSettingKey, enabled ? 'true' : 'false');
    state = enabled;
  }
}

final touchModeProvider = NotifierProvider<TouchModeNotifier, bool>(
  TouchModeNotifier.new,
);
