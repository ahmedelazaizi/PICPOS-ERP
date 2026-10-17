import 'dart:typed_data';

import 'package:excel/excel.dart';
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

/// Feeds fixed bytes to `FilePicker.pickFiles` (what `_pickFile` calls).
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

List<Object?> _row(String code, String name, double cost, double sale,
        double tax, String negative) =>
    [code, name, null, 'عام', cost, sale, 0, 0, 0, tax, 0, 0, 'لا', 0, 30,
      'عدد', 0, 0, negative];

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

  test('raw defect workbook cannot be decoded (premise)', () {
    final raw = buildXlsx([_header]);
    expect(() => Excel.decodeBytes(raw), throwsA(anything));
  });

  test('importProducts imports a workbook declaring numFmtId=43', () async {
    final bytes = buildXlsx([
      _header,
      _row('P1', 'لبن', 1.25, 2.5, 0.16, 'نعم'),
      _row('P2', 'خبز', 0.5, 1.0, 0, 'لا'),
    ]);
    FilePickerPlatform.instance = _FakePicker(bytes);

    final result = await service.importProducts();

    expect(result.success, isTrue, reason: result.message);
    final products = await db.select(db.products).get();
    expect(products, hasLength(2));
    final p1 = products.firstWhere((p) => p.code == 'P1');
    expect(p1.name, 'لبن');
    expect(p1.costPrice, 1.25);
    expect(p1.salePrice, 2.5);
    expect(p1.allowNegativeSale, isTrue);
    expect(p1.taxRate, 16); // 0.16 fraction is normalised to 16 %
    final p2 = products.firstWhere((p) => p.code == 'P2');
    expect(p2.costPrice, 0.5);
    expect(p2.allowNegativeSale, isFalse);
  });
}
