// Audit B DATA-006 — purchase XLSX import normalises a fractional tax rate
// (Excel percentage cell 0.16 -> 16) and rejects rates outside the ladder,
// exactly like the product import.
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:file_picker/file_picker.dart';
// ignore: implementation_imports
import 'package:file_picker/src/platform/file_picker_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/data/repositories/branch_repository_impl.dart';
import 'package:ural_erp/data/repositories/drift_product_repository.dart';
import 'package:ural_erp/data/repositories/parties_repository_impl.dart';
import 'package:ural_erp/data/services/excel_service.dart';
import 'package:ural_erp/domain/repositories/purchases_repository.dart';

import 'xlsx_defect_fixture.dart';

class _RecordingPurchases extends Fake implements PurchasesRepository {
  final created = <CreatePurchaseInvoiceParams>[];
  @override
  Future<int> createInvoice(CreatePurchaseInvoiceParams params) async {
    created.add(params);
    return created.length;
  }
}

class _FakePicker extends FilePickerPlatform {
  _FakePicker(this.bytes);
  final Uint8List bytes;
  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
    bool cancelUploadOnWindowBlur = true,
  }) async =>
      FilePickerResult([
        PlatformFile(name: 'p.xlsx', size: bytes.length, bytes: bytes),
      ]);
}

void main() {
  late AppDatabase db;
  late ExcelService service;
  late _RecordingPurchases purchases;
  late FilePickerPlatform previous;

  setUp(() async {
    db = AppDatabase.forTesting();
    previous = FilePickerPlatform.instance;
    purchases = _RecordingPurchases();
    service = ExcelService(DriftProductRepository(db),
        PartiesRepositoryImpl(db), BranchRepositoryImpl(db), purchases);
    await db.into(db.warehouses).insert(WarehousesCompanion.insert(name: 'W'));
    await db.into(db.products).insert(ProductsCompanion.insert(
        code: 'P1', name: 'Item', salePrice: const Value(10)));
  });
  tearDown(() async {
    FilePickerPlatform.instance = previous;
    await db.close();
  });

  List<List<Object?>> sheet(Object taxRate) => [
        ['فاتورة المورد', 'المورد', 'المخزن', 'التاريخ', 'كود', 'الصنف', 'الكمية',
          'التكلفة', 'الخصم', 'الضريبة', 'المدفوع', 'ملاحظات', 'الدفع'],
        ['INV-1', 'Supplier A', null, null, 'P1', 'Item', 10, 100, 0, taxRate, null, null, 'credit'],
      ];

  Future<ImportResult> run(Object taxRate) async {
    FilePickerPlatform.instance = _FakePicker(buildXlsx(sheet(taxRate)));
    return service.importPurchaseInvoices();
  }

  test('0.16 (Excel percentage cell) imports as 16 %', () async {
    final r = await run(0.16);
    expect(r.success, isTrue, reason: r.message);
    expect(purchases.created.single.items.single.taxRate, 16);
    expect(purchases.created.single.items.single.taxAmount, closeTo(160, 1e-6));
  });

  test('16 imports as 16 %', () async {
    final r = await run(16);
    expect(r.success, isTrue, reason: r.message);
    expect(purchases.created.single.items.single.taxRate, 16);
  });

  test('7 (not on the ladder) is a row error, nothing is created', () async {
    final r = await run(7);
    expect(r.success, isFalse);
    expect(r.errors, 1);
    expect(purchases.created, isEmpty);
  });
}
