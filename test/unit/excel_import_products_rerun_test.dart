// Product import re-run behaviour + per-row error reporting.
//
// QA: re-importing a /products workbook over overlapping data showed a green
// «0 جديد، 1 تحديث، 353 أخطاء» with no way to see the errors.
import 'dart:typed_data';

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

class _FakePurchases extends Fake implements PurchasesRepository {}

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
  }) async => FilePickerResult([
    PlatformFile(name: 'products.xlsx', size: bytes.length, bytes: bytes),
  ]);
}

const _header = [
  'كود الصنف', 'اسم الصنف', 'الباركود', 'التصنيف', 'سعر التكلفة',
  'سعر البيع', 'سعر طلبات', 'سعر كريم', 'سعر أشياء', 'نسبة الضريبة %',
  'الرصيد الافتتاحي', 'الحد الأدنى', 'يتتبع الصلاحية', 'أيام الصلاحية',
  'تنبيه قبل', 'نوع الميزان', 'سعر الوحدة', 'رقم PLU', 'السماح بالبيع بالسالب',
];

List<Object?> _row(String code, String name, String? barcode, String category,
        {double cost = 1.25, double sale = 2.5, double tax = 16, int open = 0,
        String scale = 'عدد', double unitPrice = 0, int plu = 0,
        String? warehouse}) =>
    [code, name, barcode, category, cost, sale, 0, 0, 0, tax, open, 0, 'لا', 0,
      30, scale, unitPrice, plu, 'لا', '', warehouse];

/// 20 products: 4 categories, barcodes, some opening stock, one by weight.
List<List<Object?>> _twentyRows([String? wh]) => [
  _header,
  for (var i = 1; i <= 20; i++)
    _row('P$i', 'صنف $i', '62900000${i.toString().padLeft(4, '0')}',
        ['مشروبات', 'ألبان', 'مخبوزات', 'عام'][i % 4],
        cost: 0.28 + i / 100, sale: 0.5 + i / 10, open: i % 3 == 0 ? 5 : 0,
        scale: i == 7 ? 'ميزان' : 'عدد', unitPrice: i == 7 ? 3.5 : 0,
        plu: i == 7 ? 107 : 0, warehouse: wh),
];

void main() {
  late AppDatabase db;
  late ExcelService service;
  late FilePickerPlatform previous;

  setUp(() {
    db = AppDatabase.forTesting();
    previous = FilePickerPlatform.instance;
    service = ExcelService(
      DriftProductRepository(db),
      PartiesRepositoryImpl(db),
      BranchRepositoryImpl(db),
      _FakePurchases(),
    );
  });

  tearDown(() async {
    FilePickerPlatform.instance = previous;
    await db.close();
  });

  Future<String> warehouseName() async =>
      (await db.select(db.warehouses).get()).first.name;

  Future<ImportResult> importRows(List<List<Object?>> rows) {
    FilePickerPlatform.instance = _FakePicker(buildXlsx(rows));
    return service.importProducts();
  }

  test('same workbook twice is idempotent: 20 created, then 20 updated, 0 errors',
      () async {
    final rows = _twentyRows(await warehouseName());

    final first = await importRows(rows);
    expect(first.imported, 20, reason: first.message);
    expect(first.updated, 0);
    expect(first.errors, 0, reason: first.rowErrors.map((e) => e.toLine()).join('\n'));
    expect(await db.select(db.products).get(), hasLength(20));

    final second = await importRows(rows);
    expect(second.imported, 0, reason: second.message);
    expect(second.updated, 20, reason: second.message);
    expect(second.errors, 0,
        reason: second.rowErrors.map((e) => e.toLine()).join('\n'));
    expect(second.rowErrors, isEmpty);
    expect(await db.select(db.products).get(), hasLength(20));
  });

  test('existing code with a changed barcode is an update, not an error',
      () async {
    await importRows(_twentyRows(await warehouseName()));
    final rows = _twentyRows(await warehouseName());
    rows[1] = _row('P1', 'صنف 1', '6290999999999', 'عام');
    final r = await importRows(rows);
    expect(r.errors, 0, reason: r.rowErrors.map((e) => e.toLine()).join('\n'));
    expect(r.updated, 20);
    final p1 = await (db.select(db.products)..where((p) => p.code.equals('P1')))
        .getSingle();
    expect(p1.barcode, '6290999999999');
  });

  test('new code carrying another product\'s barcode: clear per-row error',
      () async {
    await importRows(_twentyRows(await warehouseName()));
    final dup = (await (db.select(db.products)
              ..where((p) => p.code.equals('P2')))
            .getSingle())
        .barcode!;
    final r = await importRows([
      _header,
      _row('NEW1', 'جديد مكرر الباركود', dup, 'عام'),
      _row('NEW2', 'جديد سليم', '6291111111111', 'عام'),
    ]);
    expect(r.imported, 1, reason: r.message);
    expect(r.errors, 1);
    expect(r.rowErrors, hasLength(1));
    final e = r.rowErrors.single;
    expect(e.row, 2);
    expect(e.code, 'NEW1');
    expect(e.reason, contains('الباركود'));
    expect(e.toLine(), contains('NEW1'));
    expect(await (db.select(db.products)..where((p) => p.code.equals('NEW1'))).get(),
        isEmpty);
  });

  test('existing code taking another product\'s barcode: clear per-row error',
      () async {
    await importRows(_twentyRows(await warehouseName()));
    final p2Barcode = (await (db.select(db.products)
              ..where((p) => p.code.equals('P2')))
            .getSingle())
        .barcode!;
    final rows = _twentyRows(await warehouseName());
    rows[1] = _row('P1', 'صنف 1', p2Barcode, 'عام'); // P1 now claims P2's barcode
    final r = await importRows(rows);
    expect(r.errors, 1, reason: r.rowErrors.map((e) => e.toLine()).join('\n'));
    expect(r.updated, 19);
    expect(r.rowErrors.single.code, 'P1');
    expect(r.rowErrors.single.reason, contains('الباركود'));
  });

  test('illegal tax rate is a per-row error with the row number', () async {
    final r = await importRows([
      _header,
      _row('T1', 'ضريبة خاطئة', null, 'عام', tax: 37.5),
      _row('T2', 'سليم', null, 'عام'),
    ]);
    expect(r.imported, 1);
    expect(r.errors, 1);
    expect(r.rowErrors.single.row, 2);
    expect(r.rowErrors.single.code, 'T1');
    expect(r.rowErrors.single.reason, isNotEmpty);
  });

  test('opening balance without a warehouse: row error, product still saved',
      () async {
    final r = await importRows([
      _header,
      _row('OB1', 'رصيد بلا مخزن', null, 'عام', open: 5),
    ]);
    expect(r.imported, 0); // counted as an error, not as created
    expect(r.errors, 1);
    expect(r.rowErrors.single.reason, contains('المخزن'));
    expect(
        await (db.select(db.products)..where((p) => p.code.equals('OB1'))).get(),
        hasLength(1));
  });
}