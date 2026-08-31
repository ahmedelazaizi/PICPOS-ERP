// ignore_for_file: avoid_dynamic_calls
import '../../core/constants/app_constants.dart';
import '../../core/tax/tax_rate_policy.dart';
import '../../core/utils/file_utils.dart';
import 'package:flutter/foundation.dart'
    show kIsWeb, kDebugMode, debugPrint, visibleForTesting;
import '../../domain/repositories/i_products_repository.dart';
import '../../domain/repositories/parties_repository.dart';
import '../../domain/repositories/branch_repository.dart';
import '../../domain/repositories/purchases_repository.dart';
import '../../domain/repositories/modifier_repository.dart';
import '../../domain/repositories/inventory_repository.dart';
import '../../data/database/database_barrel.dart' as db;
import '../../services/client_write_interceptor.dart';
import '../database/sync_interceptor.dart';
import '../../core/utils/uuid_v7.dart';
import 'package:drift/drift.dart';
import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';

/// Excel Import/Export Service for Products, Customers, Suppliers, and Purchase Invoices
// ═══════════════════════════════════════════════════════════════════════════
// سياقُ التقرير المُصدَّر — الفترةُ والفرع
// ═══════════════════════════════════════════════════════════════════════════
//
// دالّتان **نقيّتان** خارج الصنف عن قصد: منطقُ «عن أيّ فترةٍ وأيّ فرعٍ هذا
// الملف» هو موضعُ الكذب المحتمل، فيجب أن يكون قابلاً للاختبار مباشرةً بلا
// قاعدةِ بياناتٍ ولا كتابةِ ملفٍ على القرص.

/// تسميةُ الفرع في رأس الملف المُصدَّر.
///
/// تُشتقّ من **الفلتر الصريح والنطاق معاً**: مديرُ فرعٍ محصورٌ يصدّر بلا اختيار
/// فرعٍ، فبياناتُه محصورةٌ بفروعه — وكتابةُ «كل الفروع» تجعل الملفَّ يدّعي
/// شمولاً ليس فيه. والسطرُ الكاذب أسوأُ من الغائب: الغائبُ يُسأل عنه،
/// والكاذبُ يُصدَّق.
///
/// [scopedBranchIds] — `null` = وصولٌ كامل · `{}` = لا شيء (فشلٌ مقفول).
String reportBranchLabel({
  required int? branchId,
  required Set<int>? scopedBranchIds,
  required Map<int, String> names,
}) {
  if (branchId != null) {
    return names[branchId] ?? 'فرع #$branchId';
  }
  if (scopedBranchIds == null) return 'كل الفروع';
  if (scopedBranchIds.isEmpty) return 'لا يوجد فرع مسموح';
  final labels = scopedBranchIds
      .map((id) => names[id] ?? 'فرع #$id')
      .toList()
    ..sort();
  return labels.join('، ');
}

String _d(DateTime d) =>
    '${d.year}/${d.month.toString().padLeft(2, '0')}/'
    '${d.day.toString().padLeft(2, '0')}';

/// كتلةُ السياق التي تسبق صفَّ الرؤوس في الملف المُصدَّر.
///
/// سطرُ الفترة يُحذف إن لم تكن هناك فترة — تقريرُ المخزون لقطةٌ لحظية، وسطرُ
/// فترةٍ فيه اختراع. وآخرُ سطرٍ فارغٌ فاصلاً، وإلا التصقت الكتلةُ بصفِّ الرؤوس
/// فقُرئت عموداً من البيانات.
List<List<String>> reportContextRows({
  required String title,
  required DateTime? periodFrom,
  required DateTime? periodTo,
  required String branchLabel,
  required DateTime generatedAt,
}) {
  final rows = <List<String>>[
    [title],
  ];

  if (periodFrom != null && periodTo != null) {
    rows.add(['الفترة: ${_d(periodFrom)} — ${_d(periodTo)}']);
  } else if (periodTo != null) {
    rows.add(['الفترة: حتى ${_d(periodTo)}']);
  } else if (periodFrom != null) {
    rows.add(['الفترة: من ${_d(periodFrom)}']);
  }

  rows.add(['الفرع: $branchLabel']);
  rows.add([
    'تاريخ التصدير: ${_d(generatedAt)} '
        '${generatedAt.hour.toString().padLeft(2, '0')}:'
        '${generatedAt.minute.toString().padLeft(2, '0')}'
  ]);
  rows.add(['']);

  return rows;
}

/// خليّةُ بياناتٍ في تقريرٍ مُصدَّر.
///
/// ⚠️ **العددُ الكسريُّ يُدوَّر لخاناتِ العملة قبل الكتابة.** كان يُكتب
/// `DoubleCellValue(cell)` خاماً، فالشاشةُ تعرض `12.346` والملفُّ يحمل
/// `12.345678900000001` — ومجموعُ عمودٍ في Excel يفترق عن مجموع الشاشة في
/// الكسور، فيقول المراجعُ إنّ التقريرَ لا يطابق النظام. والعطبُ صامت: الملفُّ
/// يُفتح ويبدو سليماً، والفرقُ يظهر عند الجمع وحدَه.
///
/// وهذا **نفسُ عقدِ** `ExcelExportHelper.toCellValue` الذي كان يخدم أربعَ
/// شاشاتٍ وحدَها، بينما [ExcelService.exportReport] تخدم ثمانيَ عشرةَ.
///
/// والصحيحُ يبقى `IntCellValue`: عددُ الفواتير ليس كسراً، وتحويلُه عائماً
/// يجعل عموداً صحيحاً يُعرض `3.0`.
///
/// نقيّةٌ خارج الصنف عن قصد — كـ[reportBranchLabel] و[reportContextRows] — كي
/// تُقاس بلا قاعدةِ بياناتٍ ولا كتابةِ ملفٍّ على القرص.
CellValue reportCellValue(dynamic cell) {
  if (cell is int) return IntCellValue(cell);
  if (cell is num) {
    return DoubleCellValue(
      double.parse(cell.toDouble().toStringAsFixed(AppConstants.decimalPlaces)),
    );
  }
  return TextCellValue(cell.toString());
}

class ExcelService {
  final IProductRepository productRepo;
  final IPartiesRepository partyRepo;
  final IBranchRepository branchRepo;
  final PurchasesRepository purchasesRepo;
  final IModifierRepository? modifierRepo;
  final InventoryRepository? inventoryRepo;

  ExcelService(this.productRepo, this.partyRepo, this.branchRepo, this.purchasesRepo, {this.modifierRepo, this.inventoryRepo});

  // ═══════════════════════════════════════════════════════════════════════
  // PRODUCTS EXPORT/IMPORT
  // ═══════════════════════════════════════════════════════════════════════

  /// Export products template with existing data
  Future<String?> exportProductsTemplate() async {
    try {
      final products = await productRepo.getAllProducts();
      final excel = Excel.createExcel();
      final sheet = excel['قائمة المنتجات'];

      // Header row - all fields matching the input form
      sheet.appendRow([
        TextCellValue('كود الصنف'),
        TextCellValue('اسم الصنف'),
        TextCellValue('الباركود'),
        TextCellValue('التصنيف'),
        TextCellValue('سعر التكلفة'),
        TextCellValue('سعر البيع'),
        TextCellValue('سعر طلبات'),
        TextCellValue('سعر كريم'),
        TextCellValue('سعر أشيائي'),
        TextCellValue('نسبة الضريبة %'),
        TextCellValue('الرصيد الافتتاحي'),
        TextCellValue('حد الطلب'),
        TextCellValue('تتبع الصلاحية'),
        TextCellValue('أيام الصلاحية'),
        TextCellValue('أيام التنبيه'),
        TextCellValue('نوع البيع'),
        TextCellValue('سعر الوحدة'),
        TextCellValue('رقم PLU'),
        TextCellValue('السماح بالسالب'),
        TextCellValue('نوع الصنف'),
        TextCellValue('المخزن الافتراضي'),
        TextCellValue('الخيارات'),
        TextCellValue('الإضافات'),
      ]);

      // Data rows
      for (final product in products) {
        String? categoryName;
        if (product.categoryId != null) {
          final cat = await productRepo.getCategoryById(product.categoryId!);
          categoryName = cat?.name;
        }

        // Map scaleType to Arabic label
        String scaleTypeLabel;
        switch (product.scaleType) {
          case 'weight':
            scaleTypeLabel = 'ميزان';
            break;
          case 'weightByPiece':
            scaleTypeLabel = 'حبة';
            break;
          case 'display':
            scaleTypeLabel = 'عرض';
            break;
          default:
            scaleTypeLabel = 'عدد';
            break;
        }

        sheet.appendRow([
          TextCellValue(product.code),
          TextCellValue(product.name),
          TextCellValue(product.barcode ?? ''),
          TextCellValue(categoryName ?? 'عام'),
          DoubleCellValue(product.costPrice),
          DoubleCellValue(product.salePrice),
          DoubleCellValue(product.priceTalabat),
          DoubleCellValue(product.priceCareem),
          DoubleCellValue(product.priceAshyae),
          DoubleCellValue(product.taxRate),
          DoubleCellValue(product.currentStock),
          DoubleCellValue(product.minStock),
          TextCellValue(product.trackExpiry ? 'نعم' : 'لا'),
          IntCellValue(product.defaultShelfDays),
          IntCellValue(product.alertDaysBefore),
          TextCellValue(scaleTypeLabel),
          DoubleCellValue(product.pricePerUnit ?? 0),
          IntCellValue(product.scalePluNumber ?? 0),
          TextCellValue(product.allowNegativeSale ? 'نعم' : 'لا'),
          TextCellValue(_productTypeToArabic(product.productType)),
          TextCellValue(await _getWarehouseName(product.warehouseId)),
          TextCellValue(await _buildOptionsColumn(product.id)),
          TextCellValue(await _buildAddonsColumn(product.id)),
        ]);
      }

      return await _saveExcel(excel, 'products_template');
    } catch (e) {
      return null;
    }
  }

  /// Import products from Excel
  Future<ImportResult> importProducts() async {
    try {
      final file = await _pickFile();
      if (file == null) {
        return ImportResult(success: false, message: 'لم يتم اختيار ملف');
      }

      final excel = Excel.decodeBytes(file);

      int imported = 0, updated = 0, errors = 0;
      String? lastError;
      final sheet = excel.tables[excel.tables.keys.first]!;

      // Spec 136 ISS-11 — batch all local row writes in ONE transaction
      // (standalone/server) so Drift emits a single products-stream update on
      // commit instead of one per row (which made `allProductsProvider` re-map
      // the growing list every row → O(N²) → "Not Responding" on bulk import).
      // Client mode keeps per-row writes: each row does a server network call
      // that must NOT run inside a DB write transaction.
      final useTxn = !SyncInterceptor.isClientMode;
      Future<void> importRows() async {
      for (int i = 1; i < sheet.maxRows; i++) {
        try {
          final row = sheet.row(i);
          if (row.isEmpty || row[0]?.value == null) continue;

          // Parse all columns matching the new template (19 columns)
          final code = row[0]?.value.toString() ?? '';
          final name = row.length > 1 ? row[1]?.value.toString() ?? '' : '';
          final barcodeStr = row.length > 2 ? row[2]?.value?.toString() : null;
          final categoryStr = row.length > 3
              ? row[3]?.value?.toString() ?? 'عام'
              : 'عام';
          final costPrice = row.length > 4 ? _parseDouble(row[4]?.value) : 0.0;
          final salePrice = row.length > 5 ? _parseDouble(row[5]?.value) : 0.0;
          final priceTalabat = row.length > 6
              ? _parseDouble(row[6]?.value)
              : 0.0;
          final priceCareem = row.length > 7
              ? _parseDouble(row[7]?.value)
              : 0.0;
          final priceAshyae = row.length > 8
              ? _parseDouble(row[8]?.value)
              : 0.0;
          final taxRate = _normalizeTaxRate(
              row.length > 9 ? _parseDouble(row[9]?.value) : 0.0);
          // البند 4: the importer is the third unguarded ingress for the tax
          // rate (after the form and the server API). Silently storing 37.5
          // from a spreadsheet is exactly how illegal rates got in. Throwing
          // here lands in the per-row catch below → the row is counted as an
          // error and reported, instead of being imported wrong.
          try {
            TaxRatePolicy.assertAllowed(taxRate);
          } on ArgumentError catch (e) {
            throw Exception('السطر ${i + 1}: ${e.message}');
          }
          final openingBalance = row.length > 10
              ? _parseDouble(row[10]?.value)
              : 0.0;
          final minStock = row.length > 11 ? _parseDouble(row[11]?.value) : 0.0;
          final trackExpiry = row.length > 12
              ? _parseBool(row[12]?.value)
              : false;
          final defaultShelfDays = row.length > 13
              ? _parseInt(row[13]?.value)
              : 0;
          final alertDaysBefore = row.length > 14
              ? _parseInt(row[14]?.value)
              : 30;
          // Parse scaleType from Arabic label
          final scaleTypeRaw = row.length > 15
              ? row[15]?.value?.toString().trim() ?? ''
              : '';
          String scaleType;
          switch (scaleTypeRaw) {
            case 'ميزان':
              scaleType = 'weight';
              break;
            case 'حبة':
              scaleType = 'weightByPiece';
              break;
            case 'عرض':
              scaleType = 'display';
              break;
            default:
              scaleType = 'count';
              break;
          }
          final isSoldByWeight =
              scaleType == 'weight' || scaleType == 'weightByPiece';
          final pricePerUnit = row.length > 16
              ? _parseDouble(row[16]?.value)
              : 0.0;
          final scalePluNumber = row.length > 17
              ? _parseInt(row[17]?.value)
              : 0;
          final allowNegativeSale = row.length > 18
              ? _parseBool(row[18]?.value)
              : false;
          // Parse productType from Arabic label
          final productTypeRaw = row.length > 19
              ? row[19]?.value?.toString().trim() ?? ''
              : '';
          final productType = _arabicToProductType(productTypeRaw);
          // Parse warehouse name
          final warehouseStr = row.length > 20
              ? row[20]?.value?.toString().trim()
              : null;
          // Parse modifiers columns (options & addons)
          final optionsStr = row.length > 21
              ? row[21]?.value?.toString().trim() ?? ''
              : '';
          final addonsStr = row.length > 22
              ? row[22]?.value?.toString().trim() ?? ''
              : '';

          if (code.isEmpty || name.isEmpty) continue;

          // Get or create category
          final categoryId = await productRepo.getOrCreateCategory(categoryStr);

          final existing = await productRepo.getProductByCode(code);

          if (existing != null) {
            // Issue 5 (Feature 021): the legacy update path wrote
            // `currentStock: openingBalance` directly here, so re-importing a
            // file with a different opening balance OVERWROTE the live stock
            // (silently bypassing inventory_balances + stock_movements). The
            // import should NOT touch live stock on update — it should
            // optionally adjust opening stock via the canonical adjustStock
            // path (handled in the post-update opening-stock block below).
            // Preserve existing.currentStock to avoid the silent overwrite.
            await productRepo.updateProduct(
              db.Product(
                id: existing.id,
                code: code,
                name: name,
                barcode: barcodeStr?.isNotEmpty == true ? barcodeStr : null,
                categoryId: categoryId,
                costPrice: costPrice,
                salePrice: salePrice,
                priceTalabat: priceTalabat,
                priceCareem: priceCareem,
                priceAshyae: priceAshyae,
                wholesalePrice: existing.wholesalePrice,
                taxRate: taxRate,
                currentStock: existing.currentStock,
                minStock: minStock,
                trackExpiry: trackExpiry,
                defaultShelfDays: defaultShelfDays,
                alertDaysBefore: alertDaysBefore,
                isSoldByWeight: isSoldByWeight,
                scaleType: scaleType,
                scalePluNumber: scalePluNumber > 0 ? scalePluNumber : null,
                pricePerUnit: pricePerUnit > 0 ? pricePerUnit : null,
                allowNegativeSale: allowNegativeSale,
                productType: productType,
                warehouseId: warehouseStr != null ? await _getWarehouseIdByName(warehouseStr) : null,
                trackInventory: existing.trackInventory,
                isActive: existing.isActive,
                isLocked: existing.isLocked,
                weightUnit: 'kg',
                isKitchenSet: false,
                itemTaxType: 'T1',
                itemTaxSubtype: 'V009',
                createdAt: DateTime.now(),
                updatedAt: DateTime.now(),
                sortOrder: 0,
                globalId: '',
                rowVersion: 0,
                // v138: Excel imports run inside the server process when in
                // server mode and through the interceptor in client mode;
                // either way the row reflects an admin's deliberate add, so
                // it stays server-canonical.
                createdOnServer: true,
              ),
            );
            // Import modifiers for this product
            await _importModifiersForProduct(existing.id, optionsStr, addonsStr);

            // Issue 5 (Feature 021): if the row carries an opening balance,
            // route it through the canonical adjustStock path with both
            // warehouse-presence validation and duplicate detection.
            // Idempotent: a re-import of the same file is a no-op for any
            // product+warehouse pair that already has an opening_stock row.
            if (openingBalance > 0) {
              final wId = warehouseStr != null
                  ? await _getWarehouseIdByName(warehouseStr)
                  : null;
              await _applyOpeningStock(
                productId: existing.id,
                warehouseId: wId,
                quantity: openingBalance,
                rowIndex: i,
              );
            }

            updated++;
          } else {
            final warehouseId = warehouseStr != null
                ? await _getWarehouseIdByName(warehouseStr)
                : null;

            // ── CLIENT MODE: send to server FIRST ─────────────────────
            // If we're in client mode, push the product to the server
            // through the ClientWriteInterceptor before writing locally.
            // The interceptor returns the server-assigned id so we
            // persist the SAME id on both sides — critical for later
            // sales referencing this product (otherwise the server
            // rejects them with FK 23503).
            //
            // Previously the Excel import wrote ONLY to local SQLite.
            // In client mode that meant every bulk-imported product
            // stayed invisible to the server until an (impossible)
            // manual re-entry happened. This silent loss is exactly
            // what the user reported for the Excel bulk import path.
            // UUID-First (Phase 1): mint ONE global_id up-front and share it
            // between the server call and the local insert. Without this, the
            // DAO would auto-mint a *different* UUID client-side, so the two
            // rows would never map 1:1 after sync → duplicates.
            final productGlobalId = UuidV7.generate();
            int? serverId;
            try {
              // Opening stock is NOT sent via the product payload — the server
              // only writes `products.current_stock` from that field and never
              // creates an `inventory_balances` row. We send it as a separate
              // `adjustStock` call after the product exists, which is the
              // canonical path that materialises an inventory_balances row on
              // both sides. Without this split, sales fail with
              // "الصنف غير متوفر نهائياً فى المستودع".
              serverId = await ClientWriteInterceptor.createProduct(
                code: code,
                name: name,
                salePrice: salePrice,
                costPrice: costPrice,
                categoryId: categoryId,
                currentStock: 0,
                barcode: barcodeStr?.isNotEmpty == true ? barcodeStr : null,
                minStock: minStock,
                taxRate: taxRate,
                isSoldByWeight: isSoldByWeight,
                allowNegativeSale: allowNegativeSale,
                trackExpiry: trackExpiry,
                defaultShelfDays: defaultShelfDays,
                alertDaysBefore: alertDaysBefore,
                pricePerUnit: pricePerUnit > 0 ? pricePerUnit : null,
                priceTalabat: priceTalabat,
                priceCareem: priceCareem,
                priceAshyae: priceAshyae,
                scaleType: scaleType,
                scalePluNumber: scalePluNumber > 0 ? scalePluNumber : null,
                productType: productType,
                warehouseId: warehouseId,
                globalId: productGlobalId,
              );
            } catch (e) {
              // Server unreachable or non-client mode — continue with
              // local insert. In client mode, `_tryOrQueue` inside the
              // interceptor will have already queued to outbox so the
              // product syncs on the next drain.
              debugPrint('[ExcelImport] server createProduct failed (will use local ID): $e');
            }

            await productRepo.insertProduct(
              db.ProductsCompanion.insert(
                code: code,
                name: name,
                id: serverId != null ? Value(serverId) : const Value<int>.absent(),
                globalId: Value(productGlobalId),
                barcode: Value(
                  barcodeStr?.isNotEmpty == true ? barcodeStr : null,
                ),
                categoryId: Value(categoryId),
                costPrice: Value(costPrice),
                salePrice: Value(salePrice),
                priceTalabat: Value(priceTalabat),
                priceCareem: Value(priceCareem),
                priceAshyae: Value(priceAshyae),
                taxRate: Value(taxRate),
                // Start at 0 — the adjustStock call below populates
                // products.current_stock AND inventory_balances together.
                currentStock: const Value(0),
                minStock: Value(minStock),
                trackExpiry: Value(trackExpiry),
                defaultShelfDays: Value(defaultShelfDays),
                alertDaysBefore: Value(alertDaysBefore),
                isSoldByWeight: Value(isSoldByWeight),
                scaleType: Value(scaleType),
                scalePluNumber: Value(
                  scalePluNumber > 0 ? scalePluNumber : null,
                ),
                pricePerUnit: Value(pricePerUnit > 0 ? pricePerUnit : null),
                allowNegativeSale: Value(allowNegativeSale),
                productType: Value(productType),
                warehouseId: Value(warehouseId),
              ),
            );
            // Get ID of newly inserted product and import modifiers
            final newProduct = await productRepo.getProductByCode(code);
            if (newProduct != null) {
              await _importModifiersForProduct(newProduct.id, optionsStr, addonsStr);

              // Materialise opening stock via the canonical adjustStock path.
              // This creates:
              //   - a stock_movements row (type=opening_stock)
              //   - an inventory_balances row (quantity=openingBalance)
              //   - updates products.current_stock atomically
              // Without this, products.current_stock would exist but
              // inventory_balances would be missing → sales fail with
              // "الصنف غير متوفر نهائياً فى المستودع".
              // Issue 5 (Feature 021): unified opening-stock flow. Same
              // helper as the update path — validates warehouseId presence
              // (errors instead of silently skipping) and skips on
              // duplicate detection.
              if (openingBalance > 0) {
                await _applyOpeningStock(
                  productId: newProduct.id,
                  warehouseId: warehouseId,
                  quantity: openingBalance,
                  rowIndex: i,
                );
              }
            }
            imported++;
          }
        } catch (e) {
          debugPrint('[ExcelImport] Row $i error: $e');
          lastError = e.toString();
          errors++;
        }
      }
      } // importRows
      if (useTxn) {
        await productRepo.runInWriteTransaction(importRows);
      } else {
        await importRows();
      }

      // Build descriptive result message
      // Capture into a local: `lastError` is now mutated inside the importRows
      // closure, so Dart can't promote the field — read it once here.
      final String? le = lastError;
      final bool anySuccess = imported > 0 || updated > 0;
      String message;
      if (anySuccess) {
        message = 'تمت العملية: $imported جديد، $updated تحديث';
        if (errors > 0) {
          message += '، $errors أخطاء';
          if (le != null && le.contains('الحد الأقصى')) {
            message += ' (تم الوصول للحد الأقصى للأصناف في النسخة التجريبية)';
          }
        }
      } else if (errors > 0) {
        message = 'فشل استيراد الأصناف ($errors خطأ)';
        if (le != null) {
          // Show the actual error for diagnosis (truncate to fit toast)
          final errorSnippet = le.length > 120
              ? le.substring(0, 120)
              : le;
          message += '\n$errorSnippet';
        }
      } else {
        message = 'لم يتم استيراد أي أصناف';
      }

      return ImportResult(
        success: anySuccess,
        message: message,
        imported: imported,
        updated: updated,
        errors: errors,
      );
    } catch (e) {
      return ImportResult(success: false, message: 'خطأ أثناء الاستيراد: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // SCALE ITEMS (PLU) EXPORT/IMPORT
  // ═══════════════════════════════════════════════════════════════════════

  /// Export scale items template — simplified 4-column format for PLU items
  Future<String?> exportScaleItemsTemplate() async {
    try {
      final products = await productRepo.getScaleProducts();
      final excel = Excel.createExcel();
      final sheet = excel['أصناف الميزان'];

      // Header — scale operator fields
      sheet.appendRow([
        TextCellValue('رقم PLU'),
        TextCellValue('اسم الصنف'),
        TextCellValue('التصنيف'),
        TextCellValue('نوع البيع'),
        TextCellValue('سعر الكيلو/الوحدة'),
      ]);

      // Existing scale items
      for (final product in products) {
        String? categoryName;
        if (product.categoryId != null) {
          final cat = await productRepo.getCategoryById(product.categoryId!);
          categoryName = cat?.name;
        }

        String scaleTypeLabel;
        switch (product.scaleType) {
          case 'weight':
            scaleTypeLabel = 'ميزان';
            break;
          case 'weightByPiece':
            scaleTypeLabel = 'حبة';
            break;
          case 'display':
            scaleTypeLabel = 'عرض';
            break;
          default:
            scaleTypeLabel = 'عدد';
            break;
        }

        sheet.appendRow([
          TextCellValue(product.code),
          IntCellValue(product.scalePluNumber ?? 0),
          TextCellValue(product.name),
          TextCellValue(categoryName ?? 'عام'),
          TextCellValue(scaleTypeLabel),
          DoubleCellValue(product.pricePerUnit ?? product.salePrice),
        ]);
      }

      return await _saveExcel(excel, 'scale_items_template');
    } catch (e) {
      return null;
    }
  }

  /// Import scale items from Excel — auto-sets isSoldByWeight=true
  Future<ImportResult> importScaleItems() async {
    try {
      final file = await _pickFile();
      if (file == null) {
        return ImportResult(success: false, message: 'لم يتم اختيار ملف');
      }

      final excel = Excel.decodeBytes(file);

      int imported = 0, updated = 0, errors = 0;
      final sheet = excel.tables[excel.tables.keys.first]!;

      // Spec 136 ISS-11 — batch local writes in one transaction (see
      // importProducts) so the scale-items bulk import emits a single
      // products-stream update instead of one per row.
      final useTxn = !SyncInterceptor.isClientMode;
      Future<void> importRows() async {
      for (int i = 1; i < sheet.maxRows; i++) {
        try {
          final row = sheet.row(i);
          if (row.isEmpty || row[0]?.value == null) continue;

          final code = row[0]?.value.toString() ?? '';
          final scalePluNumber = row.length > 1 ? _parseInt(row[1]?.value) : 0;
          final name = row.length > 2 ? row[2]?.value.toString() ?? '' : '';
          final categoryStr = row.length > 3
              ? row[3]?.value?.toString() ?? 'عام'
              : 'عام';
          // Parse scaleType from Arabic label
          final scaleTypeRaw = row.length > 4
              ? row[4]?.value?.toString().trim() ?? ''
              : '';
          String scaleType;
          switch (scaleTypeRaw) {
            case 'حبة':
              scaleType = 'weightByPiece';
              break;
            case 'عرض':
              scaleType = 'display';
              break;
            default:
              scaleType = 'weight';
              break; // default for scale items
          }
          final isSoldByWeight =
              scaleType == 'weight' || scaleType == 'weightByPiece';
          final pricePerKg = row.length > 5 ? _parseDouble(row[5]?.value) : 0.0;

          if (code.isEmpty || name.isEmpty) continue;

          // Get or create category
          final categoryId = await productRepo.getOrCreateCategory(categoryStr);

          final existing = await productRepo.getProductByCode(code);

          if (existing != null) {
            await productRepo.updateProduct(
              db.Product(
                id: existing.id,
                code: existing.code,
                name: name,
                barcode: existing.barcode,
                categoryId: categoryId,
                costPrice: existing.costPrice,
                salePrice: pricePerKg,
                priceTalabat: existing.priceTalabat,
                priceCareem: existing.priceCareem,
                priceAshyae: existing.priceAshyae,
                wholesalePrice: existing.wholesalePrice,
                taxRate: existing.taxRate,
                currentStock: existing.currentStock,
                minStock: existing.minStock,
                trackExpiry: existing.trackExpiry,
                defaultShelfDays: existing.defaultShelfDays,
                alertDaysBefore: existing.alertDaysBefore,
                isSoldByWeight: isSoldByWeight,
                scaleType: scaleType,
                scalePluNumber: scalePluNumber > 0 ? scalePluNumber : null,
                pricePerUnit: pricePerKg > 0 ? pricePerKg : null,
                allowNegativeSale: existing.allowNegativeSale,
                productType: existing.productType,
                warehouseId: existing.warehouseId,
                trackInventory: existing.trackInventory,
                isActive: existing.isActive,
                isLocked: existing.isLocked,
                weightUnit: 'kg',
                isKitchenSet: false,
                itemTaxType: 'T1',
                itemTaxSubtype: 'V009',
                createdAt: DateTime.now(),
                updatedAt: DateTime.now(),
                sortOrder: 0,
                globalId: '',
                rowVersion: 0,
                // v138: Excel imports run inside the server process when in
                // server mode and through the interceptor in client mode;
                // either way the row reflects an admin's deliberate add, so
                // it stays server-canonical.
                createdOnServer: true,
              ),
            );
            updated++;
          } else {
            await productRepo.insertProduct(
              db.ProductsCompanion.insert(
                code: code,
                name: name,
                categoryId: Value(categoryId),
                salePrice: Value(pricePerKg),
                isSoldByWeight: Value(isSoldByWeight),
                scaleType: Value(scaleType),
                scalePluNumber: Value(
                  scalePluNumber > 0 ? scalePluNumber : null,
                ),
                pricePerUnit: Value(pricePerKg > 0 ? pricePerKg : null),
              ),
            );
            imported++;
          }
        } catch (e) {
          errors++;
        }
      }
      } // importRows
      if (useTxn) {
        await productRepo.runInWriteTransaction(importRows);
      } else {
        await importRows();
      }

      return ImportResult(
        success: true,
        message:
            'تم استيراد أصناف الميزان: $imported جديد، $updated تحديث${errors > 0 ? '، $errors أخطاء' : ''}',
        imported: imported,
        updated: updated,
        errors: errors,
      );
    } catch (e) {
      return ImportResult(success: false, message: 'خطأ أثناء الاستيراد: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // PARTIES EXPORT/IMPORT
  // ═══════════════════════════════════════════════════════════════════════

  /// Export parties template
  Future<String?> exportPartiesTemplate(bool isSupplier) async {
    try {
      final parties = await partyRepo.getParties(
        isCustomer: !isSupplier,
        isSupplier: isSupplier,
      );

      final excel = Excel.createExcel();
      final title = isSupplier ? 'الموردين' : 'العملاء';
      final sheet = excel[title];

      // Different columns for customers vs suppliers
      if (isSupplier) {
        // Supplier columns: name, phone, address, taxId, balance
        sheet.appendRow([
          TextCellValue('الاسم'),
          TextCellValue('رقم الهاتف'),
          TextCellValue('العنوان'),
          TextCellValue('الرقم الضريبي'),
          TextCellValue('الرصيد الافتتاحي'),
        ]);

        for (final party in parties) {
          sheet.appendRow([
            TextCellValue(party.name),
            TextCellValue(party.phone ?? ''),
            TextCellValue(party.address ?? ''),
            TextCellValue(party.taxId ?? ''),
            DoubleCellValue(party.balance),
          ]);
        }
      } else {
        // Customer columns: name, phone, address, creditLimit, fixedDiscount, priceLevel, balance
        sheet.appendRow([
          TextCellValue('الاسم'),
          TextCellValue('رقم الهاتف'),
          TextCellValue('العنوان'),
          TextCellValue('حد الائتمان'),
          TextCellValue('الخصم الثابت %'),
          TextCellValue('تصنيف السعر'),
          TextCellValue('الرصيد الافتتاحي'),
        ]);

        for (final party in parties) {
          sheet.appendRow([
            TextCellValue(party.name),
            TextCellValue(party.phone ?? ''),
            TextCellValue(party.address ?? ''),
            DoubleCellValue(party.creditLimit),
            DoubleCellValue(party.fixedDiscount),
            TextCellValue(party.priceLevel),
            DoubleCellValue(party.balance),
          ]);
        }
      }

      return await _saveExcel(
        excel,
        '${isSupplier ? 'suppliers' : 'customers'}_template',
      );
    } catch (e) {
      return null;
    }
  }

  /// Import parties from Excel
  Future<ImportResult> importParties(bool isSupplier) async {
    try {
      final file = await _pickFile();
      if (file == null) {
        return ImportResult(success: false, message: 'لم يتم اختيار ملف');
      }

      final excel = Excel.decodeBytes(file);

      int imported = 0, updated = 0, errors = 0;
      final sheet = excel.tables[excel.tables.keys.first]!;

      for (int i = 1; i < sheet.maxRows; i++) {
        try {
          final row = sheet.row(i);
          if (row.isEmpty || row[0]?.value == null) continue;

          final name = row[0]?.value.toString() ?? '';
          final phone = row.length > 1 ? row[1]?.value?.toString() : null;
          final address = row.length > 2 ? row[2]?.value?.toString() : null;

          if (name.isEmpty) continue;

          if (isSupplier) {
            // Supplier import: name, phone, address, taxId, balance
            final taxId = row.length > 3 ? row[3]?.value?.toString() : null;
            final openingBalance = row.length > 4
                ? _parseDouble(row[4]?.value)
                : 0.0;

            final existing = await partyRepo.getPartyByName(name, isSupplier);

            if (existing != null) {
              await partyRepo.updateParty(
                existing.copyWith(
                  phone: Value(phone),
                  address: Value(address),
                  taxId: Value(taxId),
                  balance: openingBalance,
                ),
              );
              updated++;
            } else {
              await partyRepo.insertParty(
                db.PartiesCompanion.insert(
                  name: name,
                  isCustomer: const Value(false),
                  isSupplier: const Value(true),
                  phone: Value(phone),
                  address: Value(address),
                  taxId: Value(taxId),
                  balance: Value(openingBalance),
                ),
              );
              imported++;
            }
          } else {
            // Customer import: name, phone, address, creditLimit, fixedDiscount, priceLevel, balance
            final creditLimit = row.length > 3
                ? _parseDouble(row[3]?.value)
                : 0.0;
            final fixedDiscount = row.length > 4
                ? _parseDouble(row[4]?.value)
                : 0.0;
            final priceLevel = row.length > 5
                ? row[5]?.value?.toString() ?? 'default'
                : 'default';
            final openingBalance = row.length > 6
                ? _parseDouble(row[6]?.value)
                : 0.0;

            final existing = await partyRepo.getPartyByName(name, isSupplier);

            if (existing != null) {
              await partyRepo.updateParty(
                existing.copyWith(
                  phone: Value(phone),
                  address: Value(address),
                  creditLimit: creditLimit,
                  fixedDiscount: fixedDiscount,
                  priceLevel: priceLevel,
                  balance: openingBalance,
                ),
              );
              updated++;
            } else {
              await partyRepo.insertParty(
                db.PartiesCompanion.insert(
                  name: name,
                  isCustomer: const Value(true),
                  isSupplier: const Value(false),
                  phone: Value(phone),
                  address: Value(address),
                  creditLimit: Value(creditLimit),
                  fixedDiscount: Value(fixedDiscount),
                  priceLevel: Value(priceLevel),
                  balance: Value(openingBalance),
                ),
              );
              imported++;
            }
          }
        } catch (e) {
          errors++;
        }
      }

      return ImportResult(
        success: true,
        message: 'تمت العملية بنجاح',
        imported: imported,
        updated: updated,
        errors: errors,
      );
    } catch (e) {
      return ImportResult(success: false, message: 'خطأ أثناء الاستيراد: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // PURCHASE INVOICES EXPORT/IMPORT
  // ═══════════════════════════════════════════════════════════════════════

  /// Export purchase invoices template
  Future<String?> exportPurchaseInvoicesTemplate() async {
    try {
      final excel = Excel.createExcel();
      final sheet = excel['فواتير مشتريات'];

      sheet.appendRow([
        TextCellValue('رقم فاتورة المورد'),         // 0: grouping key
        TextCellValue('اسم المورد'),                 // 1
        TextCellValue('المخزن'),                     // 2
        TextCellValue('تاريخ الفاتورة'),             // 3
        TextCellValue('كود/باركود الصنف'),           // 4
        TextCellValue('اسم الصنف (بديل عن الكود)'), // 5: used for lookup if code is empty
        TextCellValue('الكمية'),                     // 6
        TextCellValue('سعر الوحدة (تكلفة)'),        // 7
        TextCellValue('الخصم'),                      // 8
        TextCellValue('نسبة الضريبة %'),             // 9
        TextCellValue('المبلغ المدفوع (اتركه فارغاً = حسب طريقة الدفع | رقم = دفع جزئي/كامل)'), // 10
        TextCellValue('ملاحظات'),                    // 11
        TextCellValue('طريقة الدفع (كاش = مدفوع كامل / آجل = غير مدفوع)'), // 12
      ]);

      // Sample row 1 — fully paid cash invoice (paid column empty → auto-full)
      sheet.appendRow([
        TextCellValue('INV-2024-001'),
        TextCellValue('شركة الأمل'),
        TextCellValue('المخزن الرئيسي'),
        TextCellValue('2026-03-19'),
        TextCellValue('PRD001'),
        TextCellValue('سكر 1 كجم'),
        const DoubleCellValue(100),
        const DoubleCellValue(25.50),
        const DoubleCellValue(0),
        const DoubleCellValue(14),
        TextCellValue(''), // paid empty → cash default = full
        TextCellValue('دفعة كاملة (نقد)'),
        TextCellValue('كاش'),
      ]);

      // Sample row 2 — credit invoice (paid empty + آجل → unpaid)
      sheet.appendRow([
        TextCellValue('INV-2024-002'),
        TextCellValue('شركة الأمل'),
        TextCellValue('المخزن الرئيسي'),
        TextCellValue('2026-03-20'),
        TextCellValue('PRD002'),
        TextCellValue('أرز 1 كجم'),
        const DoubleCellValue(50),
        const DoubleCellValue(40),
        const DoubleCellValue(0),
        const DoubleCellValue(0),
        TextCellValue(''), // paid empty → credit default = 0
        TextCellValue('غير مدفوعة'),
        TextCellValue('آجل'),
      ]);

      // Sample row 3 — partial payment (explicit paid value < total)
      sheet.appendRow([
        TextCellValue('INV-2024-003'),
        TextCellValue('شركة الأمل'),
        TextCellValue('المخزن الرئيسي'),
        TextCellValue('2026-03-21'),
        TextCellValue('PRD003'),
        TextCellValue('زيت 1 لتر'),
        const DoubleCellValue(20),
        const DoubleCellValue(30),
        const DoubleCellValue(0),
        const DoubleCellValue(0),
        const DoubleCellValue(200), // partial: 200 of 600 total
        TextCellValue('دفع جزئي 200 من 600'),
        TextCellValue('كاش'),
      ]);

      return await _saveExcel(excel, 'purchase_invoices_template');
    } catch (e) {
      return null;
    }
  }

  /// Import purchase invoices from Excel
  /// Rows are grouped by supplier invoice number (column 0).
  /// Each group becomes one purchase invoice.
  Future<ImportResult> importPurchaseInvoices() async {
    try {
      final file = await _pickFile();
      if (file == null) {
        return ImportResult(success: false, message: 'لم يتم اختيار ملف');
      }

      final excel = Excel.decodeBytes(file);
      final sheet = excel.tables[excel.tables.keys.first]!;

      // Phase 1: Parse all rows (skip header)
      final List<_PurchaseImportRow> parsedRows = [];
      for (int i = 1; i < sheet.maxRows; i++) {
        final row = sheet.row(i);
        if (row.isEmpty || row[0]?.value == null) continue;
        final invoiceNum = row[0]?.value.toString().trim() ?? '';
        if (invoiceNum.isEmpty) continue;

        final paidCellValue = row.length > 10 ? row[10]?.value : null;
        parsedRows.add(_PurchaseImportRow(
          supplierInvoiceNumber: invoiceNum,
          supplierName:
              row.length > 1 ? row[1]?.value?.toString().trim() ?? '' : '',
          warehouseName:
              row.length > 2 ? row[2]?.value?.toString().trim() : null,
          dateStr: row.length > 3 ? row[3]?.value?.toString().trim() : null,
          productCode:
              row.length > 4 ? row[4]?.value?.toString().trim() ?? '' : '',
          productName:
              row.length > 5 ? row[5]?.value?.toString().trim() ?? '' : '',
          quantity: row.length > 6 ? _parseDouble(row[6]?.value) : 0,
          unitCost: row.length > 7 ? _parseDouble(row[7]?.value) : 0,
          discount: row.length > 8 ? _parseDouble(row[8]?.value) : 0,
          taxRate: row.length > 9 ? _parseDouble(row[9]?.value) : 0,
          paid: _parseDouble(paidCellValue),
          paidProvided: paidCellValue != null &&
              paidCellValue.toString().trim().isNotEmpty,
          notes: row.length > 11 ? row[11]?.value?.toString().trim() : null,
          paymentMethod: row.length > 12
              ? row[12]?.value?.toString().trim().toLowerCase() ?? 'cash'
              : 'cash',
        ));
      }

      if (parsedRows.isEmpty) {
        return ImportResult(success: false, message: 'الملف لا يحتوي على بيانات');
      }

      // Phase 2: Group by supplier invoice number
      final Map<String, List<_PurchaseImportRow>> grouped = {};
      for (final row in parsedRows) {
        grouped.putIfAbsent(row.supplierInvoiceNumber, () => []).add(row);
      }

      int imported = 0, errors = 0;
      final List<String> errorMessages = [];

      // Phase 3: Process each invoice group
      for (final entry in grouped.entries) {
        try {
          final rows = entry.value;
          final firstRow = rows.first;

          // Resolve supplier (auto-create if not found)
          int? supplierId;
          if (firstRow.supplierName.isNotEmpty) {
            final existing = await partyRepo.getPartyByName(firstRow.supplierName, true);
            if (existing != null) {
              supplierId = existing.id;
            } else {
              // Auto-create supplier
              supplierId = await partyRepo.insertParty(
                db.PartiesCompanion.insert(
                  name: firstRow.supplierName,
                  isCustomer: const Value(false),
                  isSupplier: const Value(true),
                ),
              );
            }
          }
          if (supplierId == null) {
            errorMessages.add('فاتورة ${entry.key}: لم يتم تحديد المورد');
            errors++;
            continue;
          }

          // Resolve warehouse
          int warehouseId = 1; // default
          if (firstRow.warehouseName != null && firstRow.warehouseName!.isNotEmpty) {
            final whId = await _getWarehouseIdByName(firstRow.warehouseName!);
            if (whId != null) warehouseId = whId;
          }

          // Parse date
          DateTime invoiceDate = DateTime.now();
          if (firstRow.dateStr != null && firstRow.dateStr!.isNotEmpty) {
            invoiceDate = DateTime.tryParse(firstRow.dateStr!) ?? DateTime.now();
          }

          // Build items
          final List<PurchaseItemParams> items = [];
          bool hasItemError = false;
          for (final itemRow in rows) {
            if (itemRow.productCode.isEmpty && itemRow.productName.isEmpty) {
              hasItemError = true;
              continue;
            }
            // Try lookup by code first, then barcode, then name
            dynamic product;
            if (itemRow.productCode.isNotEmpty) {
              product = await productRepo.getProductByCode(itemRow.productCode);
              product ??= await productRepo.getProductByBarcode(itemRow.productCode);
            }
            if (product == null && itemRow.productName.isNotEmpty) {
              // Search by exact name (case-insensitive)
              final allProducts = await productRepo.getAllProducts();
              final match = allProducts.where((p) => p.name.trim().toLowerCase() == itemRow.productName.toLowerCase()).toList();
              product = match.isNotEmpty ? match.first : null;
            }
            if (product == null) {
              errorMessages.add('فاتورة ${entry.key}: الصنف ${itemRow.productCode.isNotEmpty ? itemRow.productCode : itemRow.productName} غير موجود');
              hasItemError = true;
              continue;
            }
            // Handle per-unit discount
            final double actualUnitCost = itemRow.quantity > 0 
                ? itemRow.unitCost - (itemRow.discount / itemRow.quantity)
                : itemRow.unitCost;

            final lineTotal = itemRow.quantity * actualUnitCost;
            final taxAmount = lineTotal * (itemRow.taxRate / 100);

            items.add(PurchaseItemParams(
              productId: product.id,
              quantity: itemRow.quantity,
              unitCost: actualUnitCost,
              salePrice: product.salePrice,
              taxRate: itemRow.taxRate,
              taxAmount: taxAmount,
            ));
          }

          if (items.isEmpty) {
            errorMessages.add('فاتورة ${entry.key}: لا توجد أصناف صالحة');
            errors++;
            continue;
          }

          // Resolve payment method
          final pmText = firstRow.paymentMethod.toLowerCase();
          final paymentMethod = (pmText.contains('أجل') || pmText.contains('اجل') || pmText.contains('credit') || pmText.contains('اجله')) 
              ? 'credit' 
              : 'cash';

          // Calculate total for auto-paid in cash
          double totalAmount = 0.0;
          for (final item in items) {
            final qty = item.quantity;
            final cost = item.unitCost;
            final rate = item.taxRate;
            final subtotal = qty * cost;
            final tax = subtotal * (rate / 100);
            totalAmount += subtotal + tax;
          }

          // Spec 110 — tri-state paid logic for clearer accounting:
          //
          //   (1) If the operator typed a positive number into the "المدفوع"
          //       column, honour it verbatim (capped at total). This is the
          //       partial-payment channel and works regardless of method
          //       label. The invoice status auto-derives in the DAO from
          //       paid vs total → 'paid' / 'partial' / 'pending'.
          //
          //   (2) Otherwise, fall back to the method label as a binary:
          //         كاش (cash)  → fully paid
          //         آجل (credit)→ fully unpaid
          //
          // Bug pre-110: "كاش" + an explicit 0 in the paid column landed
          // the invoice as unpaid because the binary fallback only fired on
          // a missing cell. Operators reading "كاش" expected fully paid.
          double finalPaid;
          if (firstRow.paidProvided && firstRow.paid > 0) {
            finalPaid =
                firstRow.paid > totalAmount ? totalAmount : firstRow.paid;
          } else if (paymentMethod == 'cash') {
            finalPaid = totalAmount;
          } else {
            // credit (آجل) — explicitly unpaid even if the column carried 0.
            finalPaid = 0;
          }

          // Parse date
          DateTime? parsedDate;
          if (firstRow.dateStr != null && firstRow.dateStr!.isNotEmpty) {
            parsedDate = DateTime.tryParse(firstRow.dateStr!);
          }

          // Create invoice via existing pipeline (handles stock + accounting)
          await purchasesRepo.createInvoice(CreatePurchaseInvoiceParams(
            supplierId: supplierId,
            warehouseId: warehouseId,
            items: items,
            paid: finalPaid,
            paymentMethod: paymentMethod,
            notes: firstRow.notes,
            supplierInvoiceNumber: entry.key,
            date: parsedDate,
          ));

          imported++;
          if (hasItemError) errors++; // partial errors
        } catch (e) {
          errorMessages.add('فاتورة ${entry.key}: $e');
          errors++;
        }
      }

      final details = errorMessages.isNotEmpty
          ? '\n${errorMessages.take(5).join('\n')}'
          : '';
      final msg = imported > 0
          ? 'تم استيراد $imported فاتورة مشتريات${errors > 0 ? '، $errors أخطاء' : ''}$details'
          : 'فشل استيراد الفواتير: $errors أخطاء$details';

      return ImportResult(
        success: imported > 0,
        message: msg,
        imported: imported,
        errors: errors,
      );
    } catch (e) {
      return ImportResult(success: false, message: 'خطأ أثناء الاستيراد: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // HELPERS
  // ═══════════════════════════════════════════════════════════════════════

  Future<Uint8List?> _pickFile() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'xls'],
      withData: true,
    );
    if (result != null) {
      return result.files.single.bytes;
    }
    return null;
  }

  Future<String?> _saveExcel(Excel excel, String prefix) async {
    try {
      final fileName =
          '${prefix}_${DateTime.now().millisecondsSinceEpoch}.xlsx';

      final fileBytes = excel.save();
      if (fileBytes == null) return null;
      final bytes = Uint8List.fromList(fileBytes);

      if (kIsWeb) {
        await fileUtils.saveFile(fileName, bytes);
        return fileName;
      }

      // Use FilePicker for path selection on Windows
      String? outputFile = await FilePicker.saveFile(
        dialogTitle: 'اختر مكان حفظ الملف',
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
      );

      if (outputFile == null) return null;

      // Ensure .xlsx extension
      if (!outputFile.toLowerCase().endsWith('.xlsx')) {
        outputFile += '.xlsx';
      }

      await fileUtils.saveFile(outputFile, bytes);
      return outputFile;
    } catch (e) {
      return null;
    }
  }

  double _parseDouble(dynamic value) => _cellToNum(value)?.toDouble() ?? 0.0;

  /// يحوّل نسبة ضريبة مكتوبة بصيغة الكسر إلى نسبة مئوية.
  ///
  /// Excel يخزّن الخلية المنسَّقة كـ Percentage بقيمتها الكسرية: خلية كتب فيها
  /// المستخدم `16%` وتعرض `16%` تُقرأ من الملف كـ `0.16`. المستورِد يقرأ القيمة
  /// الخام، فملف مملوء **صح** كان يفشل في كل سطر برسالة
  /// «نسبة الضريبة "0.16" غير مسموح بها» — بلاغ ميداني بـ ٥٢٠ سطر فاشل.
  ///
  /// الإنقاذ هنا غير ملتبس: السلّم ليس فيه أي قيمة بين 0 و 1 حصراً، فأي قيمة في
  /// المدى ده مرفوضة يقيناً كما هي. الضرب في ١٠٠ لا يمكن إلا أن يحوّل فشلاً
  /// مؤكداً إلى نسبة صحيحة، وفقط لو وقع الناتج على السلّم فعلاً؛ وأي شيء آخر
  /// يفشل كما كان وبنفس القيمة الأصلية في الرسالة.
  ///
  /// نرجّع عضو السلّم نفسه لا حاصل الضرب: `0.16 * 100` يساوي
  /// `16.000000000000002` في الفاصلة العائمة، وتخزينها يزرع قيمة قذرة في عمود
  /// تُقارَن قيمه بالتساوي في التقارير الضريبية.
  double _normalizeTaxRate(double raw, {List<double>? allowed}) {
    if (raw <= 0 || raw >= 1) return raw;
    // `activeRates` لا `defaultAllowedRates`: التحويل لازم يقيس على نفس السلّم
    // اللي `assertAllowed` هيقيس عليه بعد سطرين، وإلا تركيب ضابط سلّم مخصّص
    // (0/14 مثلاً) يحوّل 0.14 لـ 14 ثم يرفضها — أو الأسوأ، ميحوّلهاش ويرفضها.
    final ladder = allowed ?? TaxRatePolicy.activeRates;
    final asPercent = raw * 100;
    for (final r in ladder) {
      if ((r - asPercent).abs() < 1e-6) return r;
    }
    return raw;
  }

  int _parseInt(dynamic value) => _cellToNum(value)?.round() ?? 0;

  /// Robustly coerce an Excel cell into a number.
  ///
  /// Spec 136 (field 2026-06-10): bulk product import was dropping the cost of
  /// SOME rows (importing 0). The `excel` package returns typed `CellValue`s,
  /// and the old code only handled raw int/double then fell back to
  /// `double.tryParse(value.toString())`. That `tryParse` returns null — and
  /// silently became 0 — for very common Arabic-ERP cell contents:
  ///   • Arabic-Indic digits  "١٢٣٤"  (U+0660-0669) / Extended "۱۲۳"
  ///   • thousands separators "1,500" / "1٬500" and currency "1500 ج.م"
  ///   • European decimals    "12,5" / "1.234,56"
  ///   • formula cells        (the package does NOT evaluate them)
  /// Plain numeric cells already worked, which is why only some rows lost cost.
  num? _cellToNum(dynamic value) {
    if (value == null) return null;
    if (value is num) return value;
    if (value is IntCellValue) return value.value;
    if (value is DoubleCellValue) return value.value;
    if (value is BoolCellValue) return value.value ? 1 : 0;
    if (value is FormulaCellValue) {
      // The excel package does NOT evaluate formulas — it only carries the
      // formula text. We must NOT fabricate a number from it; flag the row so
      // the operator can paste-as-values and re-import.
      debugPrint('[EXCEL-IMPORT] formula cell not evaluated: "${value.formula}"');
      return null;
    }
    // TextCellValue / anything else → parse its string form.
    final raw = value.toString();
    final parsed = normalizeNumericString(raw);
    if (parsed == null && raw.trim().isNotEmpty) {
      // Non-empty but unparseable (a typo or stray text) — surface it so the
      // operator can fix that row instead of silently getting 0.
      debugPrint('[EXCEL-IMPORT] unparseable numeric cell: "$raw"');
    }
    return parsed;
  }

  /// Normalise a human-typed numeric string (Arabic digits, grouping
  /// separators, currency text, European decimals) into a Dart double.
  @visibleForTesting
  static num? normalizeNumericString(String input) {
    var s = input.trim();
    if (s.isEmpty) return null;
    // 1) Map Arabic-Indic + Extended Arabic-Indic digits and separators.
    final sb = StringBuffer();
    for (final r in s.runes) {
      if (r >= 0x0660 && r <= 0x0669) {
        sb.writeCharCode(0x30 + (r - 0x0660)); // ٠-٩ → 0-9
      } else if (r >= 0x06F0 && r <= 0x06F9) {
        sb.writeCharCode(0x30 + (r - 0x06F0)); // ۰-۹ → 0-9
      } else if (r == 0x066B) {
        sb.write('.'); // Arabic decimal separator ٫
      } else if (r == 0x066C || r == 0x00A0 || r == 0x2009 || r == 0x202F) {
        // Arabic thousands ٬, NBSP, thin/narrow spaces → drop (grouping)
      } else {
        sb.writeCharCode(r);
      }
    }
    s = sb.toString();
    // 2) Strip known currency notations (symbols + common AR/EN abbreviations)
    //    and grouping whitespace — but NOT arbitrary letters/operators, so a
    //    formula or typo is rejected (step 3) instead of being mined for digits
    //    (e.g. "B2*1.1" must NOT become 21.1).
    const currencyTokens = [
      'ج.م.', 'ج.م', 'جنيه', 'ر.س', 'ريال', 'د.ك', 'دينار', 'درهم',
      'د.إ', 'د.ل', 'ل.س', 'ل.ل', 'egp', 'usd', 'sar', 'aed', 'kwd', 'le',
    ];
    var t = s.toLowerCase();
    for (final tok in currencyTokens) {
      t = t.replaceAll(tok, '');
    }
    t = t
        .replaceAll(RegExp(r'[\s   ]'), '') // any leftover spaces
        .replaceAll(RegExp(r'[$€£¥₺﷼%]'), ''); // currency symbols / percent
    if (t.isEmpty) return null;
    // 3) Reject anything that is not a bare (optionally grouped/signed) number —
    //    this is what keeps formulas ("=SUM(..)", "B2*1.1") and typos out.
    if (!RegExp(r'^[+-]?[0-9.,]+([eE][+-]?[0-9]+)?$').hasMatch(t)) return null;
    s = t;
    if (s == '-' || s == '+') return null;
    // 4) Resolve dot vs comma. When both appear, the LAST one is the decimal
    //    mark (covers both "1,234.56" and "1.234,56"); the other is grouping.
    final hasDot = s.contains('.');
    final hasComma = s.contains(',');
    if (hasDot && hasComma) {
      if (s.lastIndexOf(',') > s.lastIndexOf('.')) {
        s = s.replaceAll('.', '').replaceAll(',', '.'); // European
      } else {
        s = s.replaceAll(',', ''); // English grouping
      }
    } else if (hasComma) {
      final parts = s.split(',');
      // single comma with non-3-digit tail = decimal comma (e.g. "12,5");
      // otherwise treat commas as thousands grouping.
      if (parts.length == 2 && parts[1].length != 3) {
        s = '${parts[0]}.${parts[1]}';
      } else {
        s = s.replaceAll(',', '');
      }
    }
    return double.tryParse(s);
  }

  bool _parseBool(dynamic value) {
    if (value == null) return false;
    if (value is bool) return value;
    final str = value.toString().toLowerCase().trim();
    return str == 'نعم' || str == 'yes' || str == 'true' || str == '1';
  }

  String _productTypeToArabic(String type) {
    switch (type) {
      case 'raw_material': return 'خامة';
      case 'finished_goods': return 'منتج تام';
      case 'service': return 'خدمة';
      default: return 'عام';
    }
  }

  String _arabicToProductType(String arabic) {
    switch (arabic) {
      case 'خامة': return 'raw_material';
      case 'منتج تام': return 'finished_goods';
      case 'خدمة': return 'service';
      default: return 'general';
    }
  }

  Future<String> _getWarehouseName(int? warehouseId) async {
    if (warehouseId == null) return '';
    final wh = await branchRepo.getWarehouseById(warehouseId);
    return wh?.name ?? '';
  }

  Future<int?> _getWarehouseIdByName(String name) async {
    return branchRepo.getWarehouseIdByName(name);
  }

  /// Issue 5 (Feature 021): unified opening-stock entry for the Excel
  /// importer. Three guarantees vs. the legacy inline path:
  ///
  /// 1. **Warehouse presence is required.** The legacy code silently
  ///    skipped any row whose warehouse column was empty, so half the
  ///    operator's opening balances vanished without a warning. Now we
  ///    throw a row-level error with an Arabic message that the import
  ///    surface picks up via [lastError].
  /// 2. **Duplicate detection.** Re-importing the same file used to
  ///    create a second `opening_stock` movement — and a second
  ///    auto-posted JE — for every row. We check
  ///    `inventoryRepo.hasOpeningStockMovement` first and skip if the
  ///    pair already has one.
  /// 3. **Single canonical path.** Both the insert branch (new product)
  ///    and the update branch (existing product) call this helper.
  ///    Previously the update branch only wrote `currentStock` directly
  ///    via `updateProduct`, which bypassed `inventory_balances` +
  ///    `stock_movements` entirely.
  ///
  /// Throws a string message on warehouse-missing errors so the caller's
  /// per-row try/catch in `importProducts` records it via `lastError +
  /// errors++`. Quietly returns on duplicates.
  Future<void> _applyOpeningStock({
    required int productId,
    required int? warehouseId,
    required double quantity,
    required int rowIndex,
  }) async {
    if (quantity <= 0) return;
    if (warehouseId == null) {
      throw 'الصف ${rowIndex + 1}: لإدخال رصيد افتتاحي يجب تحديد المخزن '
          'في عمود "المخزن" — تم تخطي رصيد $quantity للصنف.';
    }
    if (inventoryRepo == null) {
      // Tolerated: the caller didn't wire an inventoryRepo (legacy unit
      // tests). Silently skip rather than crash.
      debugPrint('[ExcelImport] inventoryRepo missing — opening stock skipped');
      return;
    }
    final exists = await inventoryRepo!.hasOpeningStockMovement(
      productId: productId,
      warehouseId: warehouseId,
    );
    if (exists) {
      debugPrint(
          '[ExcelImport] opening_stock already exists for product=$productId '
          'warehouse=$warehouseId — skipped (idempotent re-import)');
      return;
    }
    // Fire-and-forget server sync (client mode only; no-op otherwise).
    ClientWriteInterceptor.adjustStock(
      productId: productId,
      warehouseId: warehouseId,
      quantity: quantity,
      type: 'opening_stock',
      notes: 'رصيد افتتاحى — استيراد Excel',
    ).catchError((e) {
      debugPrint('[ExcelImport] server adjustStock failed (queued): $e');
      return false;
    });
    // Local write so UI / sales see it immediately.
    try {
      await inventoryRepo!.adjustStock(
        productId: productId,
        warehouseId: warehouseId,
        quantity: quantity,
        type: 'opening_stock',
        notes: 'رصيد افتتاحى — استيراد Excel',
      );
    } catch (e) {
      debugPrint('[ExcelImport] local adjustStock failed: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // MODIFIER HELPERS (OPTIONS & ADDONS) FOR EXCEL
  // ═══════════════════════════════════════════════════════════════════════

  /// Build the "الخيارات" column value for export.
  /// Format: "مجموعة1:قيمة1/قيمة2;مجموعة2:قيمة1/قيمة2"
  /// Example: "الحجم:صغير/وسط/كبير;الصوص:كاتشب/مايونيز"
  Future<String> _buildOptionsColumn(int productId) async {
    if (modifierRepo == null) return '';
    try {
      final groups = await modifierRepo!.getProductModifiers(productId);
      final optionGroups = groups.where((g) => g.group.type == 'option').toList();
      if (optionGroups.isEmpty) return '';

      return optionGroups.map((g) {
        final values = g.items.map((i) => i.name).join('/');
        return '${g.group.name}:$values';
      }).join(';');
    } catch (_) {
      return '';
    }
  }

  /// Build the "الإضافات" column value for export.
  /// Format: "مجموعة:اسم=سعر/اسم=سعر;مجموعة2:..."
  /// Example: "الإضافات:جبنة إضافية=1.50/بيكون=2.00"
  Future<String> _buildAddonsColumn(int productId) async {
    if (modifierRepo == null) return '';
    try {
      final groups = await modifierRepo!.getProductModifiers(productId);
      final addonGroups = groups.where((g) => g.group.type == 'addon').toList();
      if (addonGroups.isEmpty) return '';

      return addonGroups.map((g) {
        final values = g.items.map((i) {
          if (i.extraPrice > 0) {
            return '${i.name}=${i.extraPrice}';
          }
          return i.name;
        }).join('/');
        return '${g.group.name}:$values';
      }).join(';');
    } catch (_) {
      return '';
    }
  }

  /// Import modifiers (options & addons) for a product from Excel text columns.
  /// Options format: "مجموعة:قيمة1/قيمة2;مجموعة2:قيمة1/قيمة2"
  /// Addons format: "مجموعة:اسم=سعر/اسم=سعر;مجموعة2:..."
  Future<void> _importModifiersForProduct(int productId, String optionsStr, String addonsStr) async {
    if (modifierRepo == null) return;
    if (optionsStr.isEmpty && addonsStr.isEmpty) return;

    try {
      // Parse OPTIONS: "الحجم:صغير/وسط/كبير;الصوص:كاتشب/مايونيز"
      if (optionsStr.isNotEmpty) {
        final groups = optionsStr.split(';');
        for (final groupDef in groups) {
          final parts = groupDef.split(':');
          if (parts.length < 2 || parts[0].trim().isEmpty) continue;

          final groupName = parts[0].trim();
          final values = parts[1].split('/');

          // Get or create the option group
          final groupId = await modifierRepo!.getOrCreateGroupByName(
            name: groupName,
            type: 'option',
            maxSelect: values.length,
          );

          // Create items (skip duplicates)
          final existingItems = await modifierRepo!.getItems(groupId);
          final existingNames = existingItems.map((i) => i.name).toSet();
          for (final val in values) {
            final itemName = val.trim();
            if (itemName.isEmpty || existingNames.contains(itemName)) continue;
            await modifierRepo!.createItem(
              groupId: groupId,
              name: itemName,
              extraPrice: 0,
              isDefault: false,
            );
          }

          // Link group to product
          await modifierRepo!.linkModifierToProduct(
            productId: productId,
            modifierGroupId: groupId,
          );
        }
      }

      // Parse ADDONS: "الإضافات:جبنة إضافية=1.50/بيكون=2.00"
      if (addonsStr.isNotEmpty) {
        final groups = addonsStr.split(';');
        for (final groupDef in groups) {
          final parts = groupDef.split(':');
          if (parts.length < 2 || parts[0].trim().isEmpty) continue;

          final groupName = parts[0].trim();
          final itemDefs = parts[1].split('/');

          // Get or create the addon group
          final groupId = await modifierRepo!.getOrCreateGroupByName(
            name: groupName,
            type: 'addon',
            maxSelect: itemDefs.length,
          );

          // Create items (skip duplicates)
          final existingItems = await modifierRepo!.getItems(groupId);
          final existingNames = existingItems.map((i) => i.name).toSet();
          for (final itemDef in itemDefs) {
            final trimmed = itemDef.trim();
            if (trimmed.isEmpty) continue;

            String itemName;
            double extraPrice = 0;

            // Parse "اسم=سعر" or just "اسم"
            if (trimmed.contains('=')) {
              final itemParts = trimmed.split('=');
              itemName = itemParts[0].trim();
              extraPrice = double.tryParse(itemParts[1].trim()) ?? 0;
            } else {
              itemName = trimmed;
            }

            if (itemName.isEmpty || existingNames.contains(itemName)) continue;
            await modifierRepo!.createItem(
              groupId: groupId,
              name: itemName,
              extraPrice: extraPrice,
              isDefault: false,
            );
          }

          // Link group to product
          await modifierRepo!.linkModifierToProduct(
            productId: productId,
            modifierGroupId: groupId,
          );
        }
      }
    } catch (e) {
      // Silently skip modifier errors — don't fail entire product import.
      // Day-18: gate behind kDebugMode; error detail is not relevant in production.
      if (kDebugMode) {
        debugPrint('[ExcelService] Modifier import error for product $productId: $e');
      }
    }
  }

  /// Generic method to export report data to Excel
  ///
  /// [periodFrom]/[periodTo] و[branchId] و[scopedBranchIds] تكتب كتلةَ سياقٍ
  /// فوق الرؤوس. بدونها كان الملفُّ لا يقول عن أيّ فترةٍ ولا أيّ فرعٍ هو، فملفٌّ
  /// على القرص باسم «تقرير المبيعات» لا يُعرف أهو يناير أم السنة كاملة.
  ///
  /// اسمُ الفرع يُحَلّ هنا من [branchRepo] لا في كلِّ شاشة: ستَّ عشرةَ شاشةً
  /// تُنادي هذه الدالة، وحلُّ الاسم في كلٍّ منها ستَّ عشرةَ فرصةً للاختلاف.
  /// والشاشةُ تمرّر ما تملكه أصلاً — معرِّفَ الفلتر ونطاقَ المستخدم.
  Future<String?> exportReport({
    required String title,
    required List<String> headers,
    required List<List<dynamic>> rows,
    DateTime? periodFrom,
    DateTime? periodTo,
    int? branchId,
    Set<int>? scopedBranchIds,
  }) async {
    try {
      final excel = Excel.createExcel();
      final sheet = excel[title];

      // كتلةُ السياق قبل الرؤوس. تُكتب فقط إن كان هناك سياقٌ يُذكر، فالمُنادي
      // الذي لم يُمرّر شيئاً يحصل على الشكل القديم بلا تغيير.
      if (periodFrom != null ||
          periodTo != null ||
          branchId != null ||
          scopedBranchIds != null) {
        final names = <int, String>{};
        try {
          for (final b in await branchRepo.getAllBranches()) {
            names[b.id] = b.name;
          }
        } catch (_) {
          // تعذّرُ قراءة الفروع لا يمنع التصدير — التسميةُ تسقط إلى «فرع #id».
        }
        final context = reportContextRows(
          title: title,
          periodFrom: periodFrom,
          periodTo: periodTo,
          branchLabel: reportBranchLabel(
            branchId: branchId,
            scopedBranchIds: scopedBranchIds,
            names: names,
          ),
          generatedAt: DateTime.now(),
        );
        for (final line in context) {
          sheet.appendRow(line.map((c) => TextCellValue(c)).toList());
        }
      }

      sheet.appendRow(headers.map((h) => TextCellValue(h)).toList());

      for (final row in rows) {
        sheet.appendRow(row.map(reportCellValue).toList());
      }

      return await _saveExcel(excel, title.replaceAll(' ', '_').toLowerCase());
    } catch (e) {
      return null;
    }
  }
}

class ImportResult {
  final bool success;
  final String message;
  final int imported;
  final int updated;
  final int errors;

  ImportResult({
    required this.success,
    required this.message,
    this.imported = 0,
    this.updated = 0,
    this.errors = 0,
  });
}

/// Internal parsed row for purchase invoice import
class _PurchaseImportRow {
  final String supplierInvoiceNumber;
  final String supplierName;
  final String? warehouseName;
  final String? dateStr;
  final String productCode;
  final String productName;
  final double quantity;
  final double unitCost;
  final double discount;
  final double taxRate;
  final double paid;
  final bool paidProvided;
  final String? notes;
  final String paymentMethod;

  const _PurchaseImportRow({
    required this.supplierInvoiceNumber,
    required this.supplierName,
    this.warehouseName,
    this.dateStr,
    required this.productCode,
    required this.productName,
    required this.quantity,
    required this.unitCost,
    required this.discount,
    required this.taxRate,
    required this.paid,
    required this.paidProvided,
    this.notes,
    this.paymentMethod = 'cash',
  });
}
