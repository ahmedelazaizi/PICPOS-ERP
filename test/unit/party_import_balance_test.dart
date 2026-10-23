// AUTHZ-003 / DATA-003 (audit 2026-10-23): re-importing a parties sheet must
// not overwrite the cached balance of an EXISTING party (it has no journal
// entry, so the card would diverge from the AR/AP ledger).
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:file_picker/file_picker.dart';
// ignore: implementation_imports
import 'package:file_picker/src/platform/file_picker_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/data/repositories/branch_repository_impl.dart';
import 'package:picpos_erp/data/repositories/drift_product_repository.dart';
import 'package:picpos_erp/data/repositories/parties_repository_impl.dart';
import 'package:picpos_erp/data/services/excel_service.dart';
import 'package:picpos_erp/domain/repositories/purchases_repository.dart';

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
  }) async =>
      FilePickerResult([
        PlatformFile(name: 'parties.xlsx', size: bytes.length, bytes: bytes),
      ]);
}

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

  test('customer import keeps the existing balance, updates master data',
      () async {
    final id = await db.into(db.parties).insert(PartiesCompanion.insert(
          name: 'زبون الاختبار',
          isCustomer: const Value(true),
          isSupplier: const Value(false),
          balance: const Value(500),
        ));
    FilePickerPlatform.instance = _FakePicker(buildXlsx([
      ['الاسم', 'رقم الهاتف', 'العنوان', 'حد الائتمان', 'الخصم', 'تصنيف', 'الرصيد'],
      ['زبون الاختبار', '0790000000', 'عمان', 1000, 0, 'default', 0],
    ]));

    final result = await service.importParties(false);

    expect(result.success, isTrue, reason: result.message);
    final row = await (db.select(db.parties)..where((p) => p.id.equals(id)))
        .getSingle();
    expect(row.phone, '0790000000', reason: 'master data still updates');
    expect(row.balance, 500, reason: 'balance must NOT be overwritten');
  });

  test('supplier import keeps the existing balance', () async {
    final id = await db.into(db.parties).insert(PartiesCompanion.insert(
          name: 'مورد الاختبار',
          isCustomer: const Value(false),
          isSupplier: const Value(true),
          balance: const Value(-250),
        ));
    FilePickerPlatform.instance = _FakePicker(buildXlsx([
      ['الاسم', 'رقم الهاتف', 'العنوان', 'الرقم الضريبي', 'الرصيد'],
      ['مورد الاختبار', '0780000000', 'إربد', '123', 99999],
    ]));

    final result = await service.importParties(true);

    expect(result.success, isTrue, reason: result.message);
    final row = await (db.select(db.parties)..where((p) => p.id.equals(id)))
        .getSingle();
    expect(row.phone, '0780000000');
    expect(row.balance, -250);
  });
}
