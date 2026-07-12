/// Exceptions raised by the BOM / manufacturing / auto-deplete code paths.
///
/// These types let the orchestrator + UI distinguish *why* a sale was
/// blocked or an auto-deplete failed, so the right Arabic message is shown
/// to the user (e.g., insufficient stock vs. cycle in BOM definitions).
///
/// Feature 009 (Auto-Deplete BOM on Sale) — Phase 2 Foundational.
library;

/// Raised when a raw material's available quantity is less than what
/// the auto-deplete deduction requires AND the active shortage policy
/// is `block`.
///
/// The optional [shortages] map lists every short raw material with the
/// required vs. available quantity so the UI can surface a complete
/// shortage list to the cashier in Arabic.
class InsufficientStockException implements Exception {
  final String message;
  final Map<int, ({double required, double available, String name})>? shortages;

  const InsufficientStockException(this.message, {this.shortages});

  @override
  String toString() {
    if (shortages == null || shortages!.isEmpty) return 'InsufficientStockException: $message';
    final lines = shortages!.entries.map((e) =>
        '  - ${e.value.name} (#${e.key}): required ${e.value.required}, available ${e.value.available}');
    return 'InsufficientStockException: $message\n${lines.join('\n')}';
  }
}

/// Raised when a multi-level BOM contains a cycle (BOM A → BOM B → BOM A)
/// or exceeds the maximum recursion depth (5 levels per FR-014).
///
/// [path] traces the BOM IDs in order so the admin can locate the malformed
/// component definitions.
class BomCycleException implements Exception {
  final List<int> path;
  final String message;

  const BomCycleException(this.path, [this.message = 'BOM cycle detected']);

  @override
  String toString() => 'BomCycleException: $message — path: ${path.join(' -> ')}';
}

/// Raised when a configuration value is invalid or used in an invalid state.
///
/// Examples (FR-004 + FR-016):
///   - `auto_deplete_on_sale = true` set on an inactive BOM (`is_active = false`).
///   - `depletion_policy` set to a string outside the allowed set.
///   - `stock_shortage_policy` resolved to an unknown value.
class InvalidPolicyException implements Exception {
  final String message;
  const InvalidPolicyException(this.message);

  @override
  String toString() => 'InvalidPolicyException: $message';
}

/// Raised when a sale or shift-open is attempted from a device whose
/// `device_id` exists in `flutter_secure_storage` but has no matching
/// row in `pos_terminals` (the device hasn't been registered with the
/// server, or the terminal was deactivated by the admin).
///
/// FR-035 + the "POS terminal غير مسجَّل" edge case.
class UnregisteredTerminalException implements Exception {
  final String deviceId;
  final String message;

  const UnregisteredTerminalException(
    this.deviceId, [
    this.message = 'POS terminal is not registered',
  ]);

  @override
  String toString() => 'UnregisteredTerminalException: $message (device_id=$deviceId)';
}
