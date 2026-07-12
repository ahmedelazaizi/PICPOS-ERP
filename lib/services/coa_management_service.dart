import 'dart:convert';
import 'dart:io';
import 'package:drift/drift.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/core/utils/uuid_v7.dart';

/// Service for exporting and importing Chart of Accounts (COA) via CSV/Excel.
class CoaManagementService {
  final AppDatabase db;

  CoaManagementService(this.db);

  // ═══════════════════════════════════════════════════════════════
  // EXPORT
  // ═══════════════════════════════════════════════════════════════

  /// Export Chart of Accounts to CSV
  Future<String?> exportCoa() async {
    final accounts = await (db.select(db.accounts)
          ..orderBy([(t) => OrderingTerm(expression: t.code)]))
        .get();

    if (accounts.isEmpty) return null;

    final buffer = StringBuffer();
    buffer.write('\uFEFF'); // BOM for Excel Arabic
    buffer.writeln('الرمز,الاسم,النوع,الطبيعة,الرصيد الطبيعي,المستوى,رمز الأب');

    for (final a in accounts) {
      String? parentCode;
      if (a.parentId != null) {
        final parent = await (db.select(db.accounts)
              ..where((t) => t.id.equals(a.parentId!)))
            .getSingleOrNull();
        parentCode = parent?.code;
      }

      buffer.writeln(
        '${_esc(a.code)},${_esc(a.name)},${a.accountType},${a.accountNature},${a.normalBalance},${a.level},${_esc(parentCode ?? '')}',
      );
    }

    return _saveFile('chart_of_accounts_export.csv', buffer.toString());
  }

  // ═══════════════════════════════════════════════════════════════
  // IMPORT
  // ═══════════════════════════════════════════════════════════════

  /// Pick and parse a COA file, then import it
  Future<ImportResult> pickAndImportCoa(BuildContext context) async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv', 'txt'],
    );
    if (result == null || result.files.isEmpty) {
      return ImportResult(totalRows: 0, success: 0, failed: 0, errors: []);
    }

    final filePath = result.files.single.path;
    if (filePath == null) {
      return ImportResult(totalRows: 0, success: 0, failed: 0, errors: []);
    }

    try {
      final content = await File(filePath).readAsString(encoding: utf8);
      final parsed = _parseCsv(content);
      return await _executeImport(parsed);
    } catch (e) {
      return ImportResult(totalRows: 0, success: 0, failed: 1, errors: ['خطأ في قراءة الملف: $e']);
    }
  }

  Future<ImportResult> _executeImport(CsvParseResult csv) async {
    int success = 0;
    int failed = 0;
    final errors = <String>[];

    // Map headers to indices
    final headers = csv.headers.map((e) => e.trim()).toList();
    final colCode = headers.indexOf('الرمز');
    final colName = headers.indexOf('الاسم');
    final colType = headers.indexOf('النوع');
    final colNature = headers.indexOf('الطبيعة');
    final colBalance = headers.indexOf('الرصيد الطبيعي');
    final colLevel = headers.indexOf('المستوى');
    final colParentCode = headers.indexOf('رمز الأب');

    if (colCode == -1 || colName == -1) {
      return ImportResult(totalRows: 0, success: 0, failed: 1, errors: ['الملف لا يحتوي على الأعمدة المطلوبة (الرمز، الاسم)']);
    }

    // Process rows in a transaction
    await db.transaction(() async {
      // Sort rows by code length/level to ensure parents are created before children
      final sortedRows = List<List<String>>.from(csv.rows);
      sortedRows.sort((a, b) {
        final codeA = _getField(a, colCode) ?? '';
        final codeB = _getField(b, colCode) ?? '';
        return codeA.length.compareTo(codeB.length);
      });

      for (int i = 0; i < sortedRows.length; i++) {
        final row = sortedRows[i];
        try {
          final code = _getField(row, colCode);
          final name = _getField(row, colName);
          final type = _getField(row, colType) ?? 'asset';
          final nature = _getField(row, colNature) ?? 'detail';
          final balance = _getField(row, colBalance) ?? 'debit';
          final levelStr = _getField(row, colLevel) ?? '1';
          final parentCode = _getField(row, colParentCode);

          if (code == null || name == null) {
            failed++;
            continue;
          }

          // Resolve parentId
          int? parentId;
          if (parentCode != null && parentCode.isNotEmpty) {
            final parent = await (db.select(db.accounts)
                  ..where((t) => t.code.equals(parentCode)))
                .getSingleOrNull();
            parentId = parent?.id;
          }

          // Check for existing account
          final existing = await (db.select(db.accounts)
                ..where((t) => t.code.equals(code)))
              .getSingleOrNull();

          if (existing != null) {
            // Update existing
            await (db.update(db.accounts)..where((t) => t.id.equals(existing.id))).write(
              AccountsCompanion(
                name: Value(name),
                accountType: Value(type),
                accountNature: Value(nature),
                normalBalance: Value(balance),
                level: Value(int.tryParse(levelStr) ?? 1),
                parentId: Value(parentId),
              ),
            );
          } else {
            // Insert new
            await db.into(db.accounts).insert(
                  AccountsCompanion.insert(
                    code: code,
                    name: name,
                    accountType: type,
                    accountNature: Value(nature),
                    normalBalance: Value(balance),
                    level: Value(int.tryParse(levelStr) ?? 1),
                    parentId: Value(parentId),
                    // UUID-First (Phase 1): stable cross-install identity.
                    globalId: Value(UuidV7.generate()),
                  ),
                );
          }
          success++;
        } catch (e) {
          failed++;
          errors.add('خطأ في الرمز ${_getField(row, colCode)}: $e');
        }
      }
    });

    return ImportResult(totalRows: csv.rows.length, success: success, failed: failed, errors: errors);
  }

  // ═══════════════════════════════════════════════════════════════
  // HELPERS
  // ═══════════════════════════════════════════════════════════════

  CsvParseResult _parseCsv(String content) {
    final lines = const LineSplitter().convert(content);
    if (lines.isEmpty) return CsvParseResult(headers: [], rows: []);

    var firstLine = lines[0];
    if (firstLine.startsWith('\uFEFF')) firstLine = firstLine.substring(1);

    final delimiter = firstLine.contains('\t') ? '\t' : ',';
    final headers = _splitCsvLine(firstLine, delimiter);
    final rows = <List<String>>[];
    for (int i = 1; i < lines.length; i++) {
      final trimmed = lines[i].trim();
      if (trimmed.isEmpty) continue;
      rows.add(_splitCsvLine(trimmed, delimiter));
    }
    return CsvParseResult(headers: headers, rows: rows);
  }

  List<String> _splitCsvLine(String line, String delimiter) {
    final result = <String>[];
    bool inQuotes = false;
    final buffer = StringBuffer();
    for (int i = 0; i < line.length; i++) {
      final char = line[i];
      if (char == '"') {
        inQuotes = !inQuotes;
      } else if (char == delimiter && !inQuotes) {
        result.add(buffer.toString().trim());
        buffer.clear();
      } else {
        buffer.write(char);
      }
    }
    result.add(buffer.toString().trim());
    return result;
  }

  String? _getField(List<String> row, int index) {
    if (index < 0 || index >= row.length) return null;
    final val = row[index];
    return val.isEmpty ? null : val;
  }

  String _esc(String value) {
    if (value.contains(',') || value.contains('"') || value.contains('\n')) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }

  Future<String?> _saveFile(String defaultName, String content) async {
    final dir = await FilePicker.getDirectoryPath();
    if (dir == null) return null;
    final file = File('$dir/$defaultName');
    await file.writeAsString(content);
    return file.path;
  }
}

class CsvParseResult {
  final List<String> headers;
  final List<List<String>> rows;
  CsvParseResult({required this.headers, required this.rows});
}

class ImportResult {
  final int totalRows;
  final int success;
  final int failed;
  final List<String> errors;
  ImportResult({required this.totalRows, required this.success, required this.failed, required this.errors});
}
