part of '../database.dart';

// ═══════════════════════════════════════════════════════════════════════════
// RESTATEMENT ENGINE DAO — محرك إعادة العرض
// IAS 8 — Accounting Policies, Changes and Errors
// ═══════════════════════════════════════════════════════════════════════════

extension RestatementDao on AppDatabase {

  /// Create a restatement request
  Future<int> createRestatement({
    required String reason, // error_correction, policy_change, reclassification
    required String description,
    required int fiscalYearId,
    required int createdBy,
    required List<Map<String, dynamic>> adjustments,
  }) async {
    return transaction(() async {
      final restatementId = await into(restatements).insert(
        RestatementsCompanion.insert(
          reason: reason,
          description: description,
          fiscalYearId: fiscalYearId,
          createdBy: createdBy,
        ),
      );

      for (final adj in adjustments) {
        await into(restatementLines).insert(
          RestatementLinesCompanion.insert(
            restatementId: restatementId,
            accountId: adj['accountId'] as int,
            originalDebit: Value((adj['originalDebit'] as num?)?.toDouble() ?? 0),
            originalCredit: Value((adj['originalCredit'] as num?)?.toDouble() ?? 0),
            adjustedDebit: Value((adj['adjustedDebit'] as num?)?.toDouble() ?? 0),
            adjustedCredit: Value((adj['adjustedCredit'] as num?)?.toDouble() ?? 0),
            notes: Value(adj['notes'] as String?),
          ),
        );
      }

      return restatementId;
    });
  }

  /// Apply a restatement — posts correcting journal entries
  Future<void> applyRestatement(int restatementId, int approvedBy) async {
    await transaction(() async {
      final restatement = await (select(restatements)
            ..where((r) => r.id.equals(restatementId)))
          .getSingle();

      if (restatement.status != 'draft') {
        throw Exception('يمكن تطبيق إعادة العرض فقط من الحالة draft');
      }

      final lines = await (select(restatementLines)
            ..where((l) => l.restatementId.equals(restatementId)))
          .get();

      // Create correcting JE
      final jeLines = <JournalLine>[];
      for (final line in lines) {
        final debitAdj = line.adjustedDebit - line.originalDebit;
        final creditAdj = line.adjustedCredit - line.originalCredit;

        if (debitAdj.abs() > 0.001 || creditAdj.abs() > 0.001) {
          if (debitAdj > 0) {
            jeLines.add(JournalLine(
              accountId: line.accountId,
              debit: debitAdj,
              description: 'تعديل مدين — إعادة عرض: ${restatement.description}',
            ));
          } else if (debitAdj < 0) {
            jeLines.add(JournalLine(
              accountId: line.accountId,
              credit: debitAdj.abs(),
              description: 'تعديل دائن — إعادة عرض: ${restatement.description}',
            ));
          }
          if (creditAdj > 0) {
            jeLines.add(JournalLine(
              accountId: line.accountId,
              credit: creditAdj,
              description: 'تعديل دائن — إعادة عرض: ${restatement.description}',
            ));
          } else if (creditAdj < 0) {
            jeLines.add(JournalLine(
              accountId: line.accountId,
              debit: creditAdj.abs(),
              description: 'تعديل مدين — إعادة عرض: ${restatement.description}',
            ));
          }
        }
      }

      if (jeLines.isNotEmpty) {
        await accountingDao.createJournalEntry(
          description: 'إعادة عرض IAS 8: ${restatement.description}',
          date: DateTime.now(),
          lines: jeLines,
          referenceType: 'restatement',
          referenceId: restatementId,
          isAutoPosted: true,
        );
      }

      // Mark applied
      await (update(restatements)
            ..where((r) => r.id.equals(restatementId)))
          .write(RestatementsCompanion(
        status: const Value('applied'),
        approvedBy: Value(approvedBy),
        appliedAt: Value(DateTime.now()),
      ));
    });
  }

  /// Get before/after comparison report
  Future<List<Map<String, dynamic>>> getRestatementComparison(int restatementId) async {
    final lines = await (select(restatementLines)
          ..where((l) => l.restatementId.equals(restatementId)))
        .get();

    return lines.map((l) => {
      'accountId': l.accountId,
      'originalDebit': l.originalDebit,
      'originalCredit': l.originalCredit,
      'adjustedDebit': l.adjustedDebit,
      'adjustedCredit': l.adjustedCredit,
      'debitChange': l.adjustedDebit - l.originalDebit,
      'creditChange': l.adjustedCredit - l.originalCredit,
      'notes': l.notes,
    }).toList();
  }

  /// Get all restatements for a fiscal year
  Future<List<RestatementData>> getRestatements(int fiscalYearId) {
    return (select(restatements)
          ..where((r) => r.fiscalYearId.equals(fiscalYearId))
          ..orderBy([(r) => OrderingTerm.desc(r.createdAt)]))
        .get();
  }
}
