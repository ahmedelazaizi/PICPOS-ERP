import 'package:excel/excel.dart' show Data;
import '../../domain/repositories/i_products_repository.dart';

/// One failed spreadsheet row of a bulk import (shown to the user).
class ImportRowError {
  const ImportRowError({
    required this.row,
    required this.code,
    required this.name,
    required this.reason,
  });

  /// 1-based spreadsheet row number (the header is row 1).
  final int row;
  final String code;
  final String name;
  final String reason;

  /// Builds an entry from a raw sheet [cells] row (code in column 0, name in
  /// column 1) and the exception thrown while importing it.
  factory ImportRowError.fromRow(int row, List<Data?> cells, Object error) {
    String cell(int i) =>
        cells.length > i ? (cells[i]?.value?.toString() ?? '') : '';
    return ImportRowError(
      row: row,
      code: cell(0),
      name: cell(1),
      reason: describeImportError(error),
    );
  }

  /// `الصف 5 · P1 · لبن: السبب` — one line, used for copy/export.
  String toLine() {
    final who = [code, name].where((s) => s.isNotEmpty).join(' · ');
    return 'الصف $row${who.isEmpty ? '' : ' · $who'}: $reason';
  }
}

/// Rejects a row whose barcode already belongs to a DIFFERENT product (the
/// schema has no unique index on barcode, so duplicates would be silently
/// created). [selfId] is the product being updated, if any.
Future<void> assertBarcodeFree(
  IProductRepository repo,
  String? barcode,
  int? selfId,
) async {
  if (barcode == null || barcode.isEmpty) return;
  final other = await repo.getProductByBarcode(barcode);
  if (other != null && other.id != selfId) {
    throw Exception(
      'الباركود "$barcode" مستخدم للصنف "${other.name}" (${other.code})',
    );
  }
}

/// Arabic, user-facing reason for an import failure. Known database
/// constraint failures get a clear sentence; anything else keeps its text.
String describeImportError(Object error) {
  var text = error.toString();
  if (error is Exception && text.startsWith('Exception: ')) {
    text = text.substring('Exception: '.length);
  }
  text = text.replaceFirst(RegExp(r'^(الصف|السطر) \d+: '), '');
  final unique =
      RegExp(r'UNIQUE constraint failed: ([\w.,\s]+)').firstMatch(text);
  if (unique != null) {
    final cols = unique.group(1)!;
    if (cols.contains('barcode')) return 'الباركود مستخدم لصنف آخر';
    if (cols.contains('.code')) return 'كود الصنف مكرر';
    return 'قيمة مكررة تخالف قيداً فريداً ($cols)';
  }
  return text;
}

class ImportResult {
  final bool success;
  final String message;
  final int imported;
  final int updated;
  final int errors;

  /// Per-row failures (product import only); the full list, not truncated.
  final List<ImportRowError> rowErrors;

  ImportResult({
    required this.success,
    required this.message,
    this.imported = 0,
    this.updated = 0,
    this.errors = 0,
    this.rowErrors = const [],
  });
}
