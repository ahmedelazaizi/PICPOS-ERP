// ═══════════════════════════════════════════════════════════════════════════
// F-03: Recurring Journal Entry Scheduler
// Auto-posts journal entries from saved templates on a schedule
// ═══════════════════════════════════════════════════════════════════════════

/// Frequency for recurring entries
enum RecurrenceFrequency {
  daily,
  weekly,
  monthly,
  quarterly,
  yearly;

  String get labelAr => switch (this) {
    RecurrenceFrequency.daily => 'يومي',
    RecurrenceFrequency.weekly => 'أسبوعي',
    RecurrenceFrequency.monthly => 'شهري',
    RecurrenceFrequency.quarterly => 'ربع سنوي',
    RecurrenceFrequency.yearly => 'سنوي',
  };
}

/// A scheduled recurring journal entry definition
class RecurringEntryDefinition {
  final int id;
  final String name;
  final int templateId;
  final RecurrenceFrequency frequency;
  final DateTime startDate;
  final DateTime? endDate;
  final DateTime? lastPosted;
  final bool isActive;

  const RecurringEntryDefinition({
    required this.id,
    required this.name,
    required this.templateId,
    required this.frequency,
    required this.startDate,
    this.endDate,
    this.lastPosted,
    this.isActive = true,
  });

  /// Check if this entry is due for posting
  bool isDue(DateTime now) {
    if (!isActive) return false;
    if (endDate != null && now.isAfter(endDate!)) return false;
    if (lastPosted == null) return now.isAfter(startDate) || now.isAtSameMomentAs(startDate);

    final nextDue = _computeNextDue(lastPosted!);
    return now.isAfter(nextDue) || now.isAtSameMomentAs(nextDue);
  }

  DateTime _computeNextDue(DateTime from) {
    return switch (frequency) {
      RecurrenceFrequency.daily => from.add(const Duration(days: 1)),
      RecurrenceFrequency.weekly => from.add(const Duration(days: 7)),
      RecurrenceFrequency.monthly => DateTime(from.year, from.month + 1, from.day),
      RecurrenceFrequency.quarterly => DateTime(from.year, from.month + 3, from.day),
      RecurrenceFrequency.yearly => DateTime(from.year + 1, from.month, from.day),
    };
  }

  DateTime get nextDueDate => lastPosted != null ? _computeNextDue(lastPosted!) : startDate;
}

/// Service to manage recurring journal entries.
///
/// Usage: Call [processDueEntries] on app startup or on schedule to auto-post
/// any entries that have become due since the last check.
class RecurringEntryService {

  /// Check all recurring definitions and post entries that are due.
  /// Returns the number of entries posted.
  ///
  /// [getDefinitions] - fetches all recurring definitions from storage
  /// [postEntry] - posts a single entry by template ID
  /// [markPosted] - updates the lastPosted date for a definition
  Future<int> processDueEntries({
    required Future<List<RecurringEntryDefinition>> Function() getDefinitions,
    required Future<void> Function(int templateId, String description) postEntry,
    required Future<void> Function(int definitionId, DateTime postDate) markPosted,
  }) async {
    final definitions = await getDefinitions();
    final now = DateTime.now();
    int posted = 0;

    for (final def in definitions) {
      if (!def.isDue(now)) continue;

      try {
        await postEntry(
          def.templateId,
          '${def.name} (تلقائي - ${def.frequency.labelAr})',
        );
        await markPosted(def.id, now);
        posted++;
      } catch (e) {
        // Log but don't stop processing other entries
        // ignore: avoid_print
        print('[RecurringEntry] Failed to post definition ${def.id}: $e');
      }
    }

    return posted;
  }
}
