// ═══════════════════════════════════════════════════════════════════════════
// E-01: Bank Statement CSV Import Service
// Parses CSV/TSV bank statements and creates reconciliation entries
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:io';
import 'package:intl/intl.dart';

/// A single row from a bank statement file
class BankStatementRow {
  final DateTime date;
  final String description;
  final double? debit;
  final double? credit;
  final double? balance;
  final String? reference;
  final String? checkNumber;

  const BankStatementRow({
    required this.date,
    required this.description,
    this.debit,
    this.credit,
    this.balance,
    this.reference,
    this.checkNumber,
  });

  double get amount => (credit ?? 0) - (debit ?? 0);
}

/// Mapping configuration for CSV columns
class CsvColumnMapping {
  final int dateColumn;
  final int descriptionColumn;
  final int debitColumn;
  final int creditColumn;
  final int? balanceColumn;
  final int? referenceColumn;
  final int? checkNumberColumn;
  final String dateFormat;
  final String delimiter;
  final int skipHeaderRows;

  const CsvColumnMapping({
    this.dateColumn = 0,
    this.descriptionColumn = 1,
    this.debitColumn = 2,
    this.creditColumn = 3,
    this.balanceColumn,
    this.referenceColumn,
    this.checkNumberColumn,
    this.dateFormat = 'yyyy/MM/dd',
    this.delimiter = ',',
    this.skipHeaderRows = 1,
  });
}

/// Service to import bank statements from CSV files
class BankStatementImportService {

  /// Parse a CSV file into bank statement rows
  static Future<BankStatementImportResult> importFromFile({
    required String filePath,
    required CsvColumnMapping mapping,
  }) async {
    final file = File(filePath);
    if (!await file.exists()) {
      return BankStatementImportResult(
        rows: [],
        errors: ['الملف غير موجود: $filePath'],
        totalLines: 0,
      );
    }

    final lines = await file.readAsLines();
    final rows = <BankStatementRow>[];
    final errors = <String>[];
    final dateFmt = DateFormat(mapping.dateFormat);

    for (int i = mapping.skipHeaderRows; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;

      try {
        final parts = _splitCsv(line, mapping.delimiter);

        final date = dateFmt.parse(parts[mapping.dateColumn].trim());
        final description = parts[mapping.descriptionColumn].trim();
        final debit = _parseAmount(parts[mapping.debitColumn]);
        final credit = _parseAmount(parts[mapping.creditColumn]);
        final balance = mapping.balanceColumn != null && mapping.balanceColumn! < parts.length
            ? _parseAmount(parts[mapping.balanceColumn!])
            : null;
        final reference = mapping.referenceColumn != null && mapping.referenceColumn! < parts.length
            ? parts[mapping.referenceColumn!].trim()
            : null;
        final checkNumber = mapping.checkNumberColumn != null && mapping.checkNumberColumn! < parts.length
            ? parts[mapping.checkNumberColumn!].trim()
            : null;

        rows.add(BankStatementRow(
          date: date,
          description: description,
          debit: debit,
          credit: credit,
          balance: balance,
          reference: reference,
          checkNumber: checkNumber,
        ));
      } catch (e) {
        errors.add('سطر ${i + 1}: $e');
      }
    }

    return BankStatementImportResult(
      rows: rows,
      errors: errors,
      totalLines: lines.length - mapping.skipHeaderRows,
    );
  }

  /// Parse amount string (handles Arabic/English numbers, commas, parentheses for negatives)
  static double? _parseAmount(String value) {
    var clean = value.trim();
    if (clean.isEmpty || clean == '-' || clean == '--') return null;

    // Handle parentheses for negatives: (5,000.00) -> -5000.00
    bool isNeg = false;
    if (clean.startsWith('(') && clean.endsWith(')')) {
      clean = clean.substring(1, clean.length - 1);
      isNeg = true;
    }

    // Remove currency symbols and commas
    clean = clean.replaceAll(RegExp(r'[^\d.\-]'), '');

    final num = double.tryParse(clean);
    if (num == null) return null;
    return isNeg ? -num : num;
  }

  /// Split CSV line handling quoted fields
  static List<String> _splitCsv(String line, String delimiter) {
    final parts = <String>[];
    bool inQuotes = false;
    final buffer = StringBuffer();

    for (int i = 0; i < line.length; i++) {
      final c = line[i];
      if (c == '"') {
        inQuotes = !inQuotes;
      } else if (c == delimiter && !inQuotes) {
        parts.add(buffer.toString());
        buffer.clear();
      } else {
        buffer.write(c);
      }
    }
    parts.add(buffer.toString());
    return parts;
  }

  /// Auto-detect column mapping from header row
  static CsvColumnMapping? autoDetectMapping(String headerLine, {String delimiter = ','}) {
    final headers = headerLine.toLowerCase().split(delimiter).map((h) => h.trim()).toList();

    int? dateCol, descCol, debitCol, creditCol, balanceCol, refCol;

    for (int i = 0; i < headers.length; i++) {
      final h = headers[i];
      if (h.contains('date') || h.contains('تاريخ')) dateCol ??= i;
      if (h.contains('desc') || h.contains('narr') || h.contains('بيان') || h.contains('وصف')) descCol ??= i;
      if (h.contains('debit') || h.contains('مدين') || h.contains('سحب')) debitCol ??= i;
      if (h.contains('credit') || h.contains('دائن') || h.contains('إيداع')) creditCol ??= i;
      if (h.contains('balance') || h.contains('رصيد')) balanceCol ??= i;
      if (h.contains('ref') || h.contains('مرجع')) refCol ??= i;
    }

    if (dateCol == null || descCol == null || debitCol == null || creditCol == null) {
      return null; // Could not auto-detect
    }

    return CsvColumnMapping(
      dateColumn: dateCol,
      descriptionColumn: descCol,
      debitColumn: debitCol,
      creditColumn: creditCol,
      balanceColumn: balanceCol,
      referenceColumn: refCol,
    );
  }
}

/// Result of a bank statement import
class BankStatementImportResult {
  final List<BankStatementRow> rows;
  final List<String> errors;
  final int totalLines;

  const BankStatementImportResult({
    required this.rows,
    required this.errors,
    required this.totalLines,
  });

  int get successCount => rows.length;
  int get errorCount => errors.length;
  bool get hasErrors => errors.isNotEmpty;
  double get totalDebits => rows.fold(0, (s, r) => s + (r.debit ?? 0));
  double get totalCredits => rows.fold(0, (s, r) => s + (r.credit ?? 0));
}
