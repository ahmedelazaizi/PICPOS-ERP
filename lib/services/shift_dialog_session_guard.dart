/// Feature 012 / Issue C-SHIFT-LOOP — process-wide guard that records
/// which userIds have already been prompted for an opening balance in
/// the current app session.
///
/// Defense-in-depth: even if `getCurrentOpenShift(userId)` transiently
/// returns null (e.g., a delta-pull is mid-flight on another isolate,
/// or the PosScreenV2 widget is re-instantiated by a parent rebuild),
/// the dialog will NOT re-prompt the same user inside the same session.
///
/// Cleared on logout via [clearShiftDialogPromptedUsers] so a cashier
/// swap on the same physical device starts with a fresh slate.
final Set<int> shiftDialogPromptedUserIds = <int>{};

/// Hook called by `AuthNotifier.logout` to reset the same-session
/// already-prompted set.
void clearShiftDialogPromptedUsers() {
  shiftDialogPromptedUserIds.clear();
}
