import 'dart:convert';
import 'dart:io';
import 'package:drift/drift.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:ural_erp/core/widgets/app_toast.dart';
import 'package:ural_erp/domain/repositories/i_products_repository.dart';
import 'package:ural_erp/domain/repositories/parties_repository.dart';
import 'package:ural_erp/data/database/database.dart';

/// CSV cell quoting + formula-injection guard (audit B DATA-007).
///
/// A cell that starts with `= + - @` TAB or CR is executed as a formula by Excel
/// / LibreOffice when the file is opened: prefix a `'` so it is shown as text.
/// Plain numbers (`-5`, `+3.5`) are left alone — they are data, and a `'`
/// would corrupt a re-import of a negative balance.
@visibleForTesting
String escapeCsvCell(String value) {
  if (value.isNotEmpty &&
      '=+-@\t\r'.contains(value[0]) &&
      double.tryParse(value.trim()) == null) {
    value = "'$value";
  }
  if (value.contains(',') || value.contains('"') || value.contains('\n')) {
    return '"${value.replaceAll('"', '""')}"';
  }
  return value;
}

/// B4 — CSV Import/Export service for products and parties.
class CsvImportExportService {
  final IProductRepository productRepo;
  final IPartiesRepository partyRepo;
  final AppDatabase db;

  CsvImportExportService(this.productRepo, this.partyRepo, this.db);

  // ═══════════════════════════════════════════════════════════════
  // EXPORT
  // ═══════════════════════════════════════════════════════════════

  /// Export products to CSV file
  Future<String?> exportProducts() async {
    final products = await productRepo.getAllProducts();
    if (products.isEmpty) return null;

    final buffer = StringBuffer();
    buffer.write('\uFEFF'); // BOM for Excel Arabic
    buffer.writeln('الكود,الاسم,الباركود,سعر البيع,سعر التكلفة,المخزون,الحد الأدنى,وحدة1_اسم,وحدة1_تحويل,وحدة2_اسم,وحدة2_تحويل,وحدة3_اسم,وحدة3_تحويل');
    for (final p in products) {
      final units = await db.getProductUnits(p.id);
      final u1 = units.isNotEmpty ? units[0] : null;
      final u2 = units.length > 1 ? units[1] : null;
      final u3 = units.length > 2 ? units[2] : null;
      buffer.writeln(
        '${_esc(p.code)},${_esc(p.name)},${_esc(p.barcode ?? '')},${p.salePrice},${p.costPrice},${p.currentStock},${p.minStock},${_esc(u1?.unitName ?? '')},${u1?.quantityInBase ?? ''},${_esc(u2?.unitName ?? '')},${u2?.quantityInBase ?? ''},${_esc(u3?.unitName ?? '')},${u3?.quantityInBase ?? ''}',
      );
    }

    return _saveFile('products_export.csv', buffer.toString());
  }

  /// Export parties (customers/suppliers) to CSV
  Future<String?> exportParties() async {
    final parties = await partyRepo.getPartiesWithBalance();
    if (parties.isEmpty) return null;

    final buffer = StringBuffer();
    buffer.write('\uFEFF');
    buffer.writeln('الاسم,الهاتف,العنوان,النوع,الرقم الضريبي');
    for (final p in parties) {
      buffer.writeln(
        '${_esc(p.name)},${_esc(p.phone ?? '')},${_esc(p.address ?? '')},${p.isCustomer ? 'عميل' : 'مورد'},${_esc(p.taxId ?? '')}',
      );
    }

    return _saveFile('parties_export.csv', buffer.toString());
  }

  // ═══════════════════════════════════════════════════════════════
  // IMPORT
  // ═══════════════════════════════════════════════════════════════

  /// Pick and parse a CSV file
  Future<CsvParseResult?> pickAndParseCsv() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv', 'txt'],
    );
    if (result == null || result.files.isEmpty) return null;
    final filePath = result.files.single.path;
    if (filePath == null) return null;

    final content = await File(filePath).readAsString(encoding: utf8);
    return _parseCsv(content);
  }

  /// Import products from parsed CSV with column mapping
  Future<ImportResult> importProducts(
    CsvParseResult csv,
    Map<String, int> columnMapping,
  ) async {
    int success = 0;
    int failed = 0;
    final errors = <String>[];

    for (int i = 0; i < csv.rows.length; i++) {
      try {
        final row = csv.rows[i];
        final name = _getField(row, columnMapping['name']);
        if (name == null || name.isEmpty) {
          failed++;
          errors.add('صف ${i + 1}: اسم الصنف مطلوب');
          continue;
        }

        final code = _getField(row, columnMapping['code']) ?? '';
        final barcode = _getField(row, columnMapping['barcode']) ?? '';
        final salePrice = double.tryParse(_getField(row, columnMapping['salePrice']) ?? '') ?? 0;
        final costPrice = double.tryParse(_getField(row, columnMapping['costPrice']) ?? '') ?? 0;
        final stock = double.tryParse(_getField(row, columnMapping['currentStock']) ?? '') ?? 0;
        final minStock = double.tryParse(_getField(row, columnMapping['minStock']) ?? '') ?? 0;


        await productRepo.insertProduct(ProductsCompanion(
          name: Value(name),
          code: Value(code.isEmpty ? name.hashCode.toString() : code),
          barcode: Value(barcode.isEmpty ? null : barcode),
          salePrice: Value(salePrice),
          costPrice: Value(costPrice),
          currentStock: Value(stock),
          minStock: Value(minStock),
        ));

        // Import product units from CSV columns
        final u1Name = _getField(row, columnMapping['unit1Name']) ?? '';
        final u1Factor = double.tryParse(_getField(row, columnMapping['unit1Factor']) ?? '') ?? 0;
        final u2Name = _getField(row, columnMapping['unit2Name']) ?? '';
        final u2Factor = double.tryParse(_getField(row, columnMapping['unit2Factor']) ?? '') ?? 0;
        final u3Name = _getField(row, columnMapping['unit3Name']) ?? '';
        final u3Factor = double.tryParse(_getField(row, columnMapping['unit3Factor']) ?? '') ?? 0;

        // Resolve the inserted product ID to link units
        final allProducts = await productRepo.getAllProducts();
        final inserted = allProducts.lastWhere(
          (p) => p.name == name,
          orElse: () => allProducts.last,
        );

        final unitEntries = [
          if (u1Name.isNotEmpty) (name: u1Name, factor: u1Factor > 0 ? u1Factor : 1.0),
          if (u2Name.isNotEmpty) (name: u2Name, factor: u2Factor > 0 ? u2Factor : 1.0),
          if (u3Name.isNotEmpty) (name: u3Name, factor: u3Factor > 0 ? u3Factor : 1.0),
        ];
        for (int ui = 0; ui < unitEntries.length; ui++) {
          final ue = unitEntries[ui];
          await db.insertProductUnit(
            ProductUnitsCompanion.insert(
              productId: inserted.id,
              unitName: ue.name,
              quantityInBase: Value(ue.factor),
              salePrice: Value(salePrice * ue.factor),
              costPrice: Value(costPrice * ue.factor),
              isBaseUnit: Value(ue.factor == 1.0),
              isDefaultSale: Value(ui == 0),
              isDefaultPurchase: Value(ui == 0),
              sortOrder: Value(ui),
            ),
          );
        }

        success++;
      } catch (e) {
        failed++;
        errors.add('صف ${i + 1}: $e');
      }
    }

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

  String? _getField(List<String> row, int? index) {
    if (index == null || index < 0 || index >= row.length) return null;
    return row[index];
  }

  String _esc(String value) => escapeCsvCell(value);

  Future<String?> _saveFile(String defaultName, String content) async {
    final dir = await FilePicker.getDirectoryPath();
    if (dir == null) return null;
    final file = File('$dir/$defaultName');
    await file.writeAsString(content);
    return file.path;
  }

  /// Show import result as toast
  static void showResult(BuildContext context, ImportResult result) {
    if (result.failed == 0) {
      AppToast.show(context, 'تم استيراد ${result.success} سجل بنجاح ✓');
    } else {
      AppToast.show(
        context,
        'تم استيراد ${result.success} من ${result.totalRows} (${result.failed} فشل)',
        type: ToastType.warning,
      );
    }
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
