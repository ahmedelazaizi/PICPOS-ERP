part of '../database.dart';


extension JournalTemplateDao on AppDatabase {



  /// Create a new journal template with its lines
  Future<int> createTemplateWithLines({
    required String name,
    String? description,
    bool isActive = true,
    required List<JournalEntryTemplateLine> lines,
  }) async {
    return transaction(() async {
      // 1. Insert the main template
      final templateId = await into(journalEntryTemplates).insert(
        JournalEntryTemplatesCompanion.insert(
          name: name,
          description: Value(description),
          isActive: Value(isActive),
        ),
      );

      // 2. Insert all the lines
      for (final line in lines) {
        await into(journalEntryTemplateLines).insert(
          JournalEntryTemplateLinesCompanion.insert(
            templateId: templateId,
            accountId: line.accountId,
            debit: Value(line.debit),
            credit: Value(line.credit),
            description: Value(line.description),
            costCenterId: Value(line.costCenterId),
          ),
        );
      }

      return templateId;
    });
  }

  /// Update an existing template and replace all its lines
  Future<void> updateTemplateWithLines({
    required int templateId,
    String? name,
    String? description,
    bool? isActive,
    List<JournalEntryTemplateLine>? lines,
  }) async {
    return transaction(() async {
      // 1. Update main record
      if (name != null || description != null || isActive != null) {
        await (update(journalEntryTemplates)
              ..where((t) => t.id.equals(templateId)))
            .write(
          JournalEntryTemplatesCompanion(
            name: name != null ? Value(name) : const Value.absent(),
            description: description != null ? Value(description) : const Value.absent(),
            isActive: isActive != null ? Value(isActive) : const Value.absent(),
          ),
        );
      }

      // 2. If lines are provided, delete old ones and insert new ones
      if (lines != null) {
        await (delete(journalEntryTemplateLines)
              ..where((l) => l.templateId.equals(templateId)))
            .go();

        for (final line in lines) {
          await into(journalEntryTemplateLines).insert(
            JournalEntryTemplateLinesCompanion.insert(
              templateId: templateId,
              accountId: line.accountId,
              debit: Value(line.debit),
              credit: Value(line.credit),
              description: Value(line.description),
              costCenterId: Value(line.costCenterId),
            ),
          );
        }
      }
    });
  }

  /// Delete a journal entry template (lines will be deleted via CASCADE if DB supports it, else manual)
  Future<void> deleteJournalEntryTemplate(int templateId) async {
    return transaction(() async {
      await (delete(journalEntryTemplateLines)
            ..where((l) => l.templateId.equals(templateId)))
          .go();
      await (delete(journalEntryTemplates)
            ..where((t) => t.id.equals(templateId)))
          .go();
    });
  }

  /// Watch all templates
  Stream<List<JournalEntryTemplateData>> watchAllTemplates() {
    return (select(journalEntryTemplates)
          ..orderBy([
            (t) => OrderingTerm(expression: t.createdAt, mode: OrderingMode.desc)
          ]))
        .watch();
  }

  /// Watch active templates only
  Stream<List<JournalEntryTemplateData>> watchActiveTemplates() {
    return (select(journalEntryTemplates)
          ..where((t) => t.isActive.equals(true))
          ..orderBy([
            (t) => OrderingTerm(expression: t.createdAt, mode: OrderingMode.desc)
          ]))
        .watch();
  }

  /// Get a journal entry template by ID
  Future<JournalEntryTemplateData> getJournalEntryTemplateById(int templateId) {
    return (select(journalEntryTemplates)
          ..where((t) => t.id.equals(templateId)))
        .getSingle();
  }

  /// Get lines for a specific template
  Future<List<JournalEntryTemplateLine>> getTemplateLines(int templateId) {
    return (select(journalEntryTemplateLines)
          ..where((l) => l.templateId.equals(templateId)))
        .get();
  }

  /// Get lines with account info for a template
  Future<List<Map<String, dynamic>>> getTemplateLinesWithAccounts(int templateId) async {
    final result = await customSelect(
      '''SELECT l.id, l.debit, l.credit, l.description, l.template_id,
          a.id as account_id, a.code as account_code, a.name as account_name
         FROM journal_entry_template_lines l
         JOIN accounts a ON l.account_id = a.id
         WHERE l.template_id = ?
         ORDER BY l.id''',
      variables: [Variable(templateId)],
      readsFrom: {journalEntryTemplateLines, accounts},
    ).get();
    
    return result.map((r) => r.data).toList();
  }
}
