/// SYNC-002 (audit 2026-10-23): a delta-pull cycle in which any row failed to
/// apply (FK order, constraint, schema) must NOT advance that table's
/// watermark — otherwise the failed rows are skipped forever with no alert.
///
/// To stop one permanently-bad row from forcing endless re-pulls, the hold is
/// bounded: after [maxHeldCycles] consecutive cycles with failures the
/// watermark advances anyway (the caller logs a loud alert).
class DeltaPullFailureTracker {
  static const int maxHeldCycles = 3;

  final Map<String, int> _rowFailures = {};
  final Map<String, int> _heldCycles = {};

  /// Start of a pull cycle for [table].
  void begin(String table) => _rowFailures[table] = 0;

  /// A row of [table] failed to apply.
  void recordRowFailure(String table) =>
      _rowFailures[table] = (_rowFailures[table] ?? 0) + 1;

  int failuresOf(String table) => _rowFailures[table] ?? 0;

  /// Whether the watermark of [table] may advance after this cycle.
  /// `forced` is true when it advances only because the hold budget ran out.
  ({bool advance, bool forced}) decide(String table) {
    if (failuresOf(table) == 0) {
      _heldCycles.remove(table);
      return (advance: true, forced: false);
    }
    final held = (_heldCycles[table] ?? 0) + 1;
    if (held >= maxHeldCycles) {
      _heldCycles.remove(table);
      return (advance: true, forced: true);
    }
    _heldCycles[table] = held;
    return (advance: false, forced: false);
  }
}
