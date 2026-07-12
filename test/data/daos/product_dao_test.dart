import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' hide isNotNull;
import 'package:ural_erp/data/database/database.dart';

/// Unit Tests for ProductDao extension
/// Tests product-related database operations
void main() {
  late AppDatabase database;

  setUp(() async {
    // Create in-memory database for testing
    database = AppDatabase.forTesting();
  });

  tearDown(() async {
    await database.close();
  });

  group('ProductDao - CRUD Operations', () {
    test('insertProduct - should insert and return product ID', () async {
      final productId = await database.insertProduct(
        ProductsCompanion.insert(
          code: 'TEST001',
          name: 'Test Product',
          currentStock: const Value(100.0),
          salePrice: const Value(10.0),
        ),
      );

      expect(productId, isPositive);
    });

    test('getProductById - should return inserted product', () async {
      final productId = await database.insertProduct(
        ProductsCompanion.insert(
          code: 'TEST002',
          name: 'Test Product 2',
          currentStock: const Value(50.0),
          salePrice: const Value(25.0),
        ),
      );

      final product = await database.getProductById(productId);

      expect(product, isNotNull);
      expect(product!.code, 'TEST002');
      expect(product.name, 'Test Product 2');
      expect(product.currentStock, 50.0);
      expect(product.salePrice, 25.0);
    });

    test('getAllProducts - should return all active products', () async {
      // Insert multiple products
      await database.insertProduct(
        ProductsCompanion.insert(code: 'P1', name: 'Product 1'),
      );
      await database.insertProduct(
        ProductsCompanion.insert(code: 'P2', name: 'Product 2'),
      );
      await database.insertProduct(
        ProductsCompanion.insert(code: 'P3', name: 'Product 3'),
      );

      final products = await database.getAllProducts();

      expect(products.length, greaterThanOrEqualTo(3));
    });

    test('updateProductStock - should update stock level', () async {
      final productId = await database.insertProduct(
        ProductsCompanion.insert(
          code: 'STOCK01',
          name: 'Stock Test',
          currentStock: const Value(100.0),
        ),
      );

      await database.updateProductStock(productId, 150.0);
      final updatedProduct = await database.getProductById(productId);

      expect(updatedProduct!.currentStock, 150.0);
    });

    test('deleteProduct - should soft-delete product', () async {
      final productId = await database.insertProduct(
        ProductsCompanion.insert(code: 'DEL01', name: 'To Delete'),
      );

      await database.deleteProduct(productId);
      
      // Product should still exist but be inactive
      final allProducts = await database.getAllProducts();
      final deletedProduct = allProducts.where((p) => p.id == productId);
      
      expect(deletedProduct, isEmpty); // Soft-deleted should not appear in active list
    });
  });

  group('ProductDao - Barcode Operations', () {
    test('insertProductBarcode - should add barcode to product', () async {
      final productId = await database.insertProduct(
        ProductsCompanion.insert(code: 'BC01', name: 'Barcode Product'),
      );

      final barcodeId = await database.insertProductBarcode(
        productId, 
        '1234567890123',
        isPrimary: true,
      );

      expect(barcodeId, isPositive);
    });

    test('getProductByBarcode - should find product by barcode', () async {
      final productId = await database.insertProduct(
        ProductsCompanion.insert(code: 'BC02', name: 'Find By Barcode'),
      );
      await database.insertProductBarcode(productId, '9876543210987');

      final product = await database.getProductByBarcode('9876543210987');

      expect(product, isNotNull);
      expect(product!.code, 'BC02');
    });

    test('barcodeExists - should return true for existing barcode', () async {
      final productId = await database.insertProduct(
        ProductsCompanion.insert(code: 'BC03', name: 'Barcode Exists'),
      );
      await database.insertProductBarcode(productId, 'EXISTINGBC');

      final exists = await database.barcodeExists('EXISTINGBC');
      final notExists = await database.barcodeExists('NOTEXISTING');

      expect(exists, isTrue);
      expect(notExists, isFalse);
    });
  });

  group('ProductDao - Category Operations', () {
    test('insertCategory - should create category', () async {
      final categoryId = await database.insertCategory(
        CategoriesCompanion.insert(name: 'Electronics'),
      );

      expect(categoryId, isPositive);
    });

    test('getCategoryByName - should find category', () async {
      await database.insertCategory(
        CategoriesCompanion.insert(name: 'Beverages'),
      );

      final category = await database.getCategoryByName('Beverages');

      expect(category, isNotNull);
      expect(category!.name, 'Beverages');
    });

    test('getOrCreateCategory - should create if not exists', () async {
      final id1 = await database.getOrCreateCategory('New Category');
      final id2 = await database.getOrCreateCategory('New Category');

      expect(id1, equals(id2)); // Should return same ID
    });

    // Spec 150 BUG-3 — «عام» (General) must show uncategorized products.
    test('getOrCreateCategory - trims name so "عام " reuses "عام"', () async {
      final id1 = await database.getOrCreateCategory('عام');
      final id2 = await database.getOrCreateCategory('عام ');

      expect(id1, equals(id2)); // trailing space must not spawn a duplicate
    });
  });

  group('ProductDao - Spec 150 BUG-3 general-category grid', () {
    test('watchPosProducts includeUncategorized surfaces NULL-category and '
        '"عام" products but not other categories', () async {
      final generalId = await database.insertCategory(
        CategoriesCompanion.insert(
          name: 'عام',
          isSystemDefault: const Value(true),
        ),
      );
      final otherId = await database.getOrCreateCategory('مشروبات');

      final inGeneral = await database.insertProduct(ProductsCompanion.insert(
          code: 'G1', name: 'صنف عام', categoryId: Value(generalId)));
      final uncategorized = await database.insertProduct(
          ProductsCompanion.insert(code: 'U1', name: 'صنف بلا تصنيف'));
      final inOther = await database.insertProduct(ProductsCompanion.insert(
          code: 'O1', name: 'صنف مشروبات', categoryId: Value(otherId)));

      final withUncat = await database.watchPosProducts(
          categoryIds: [generalId], includeUncategorized: true).first;
      final ids = withUncat.map((p) => p.id).toSet();
      expect(ids, containsAll(<int>[inGeneral, uncategorized]));
      expect(ids, isNot(contains(inOther)));

      // Default (strict) still excludes NULL-category rows.
      final strict =
          await database.watchPosProducts(categoryIds: [generalId]).first;
      final strictIds = strict.map((p) => p.id).toSet();
      expect(strictIds, contains(inGeneral));
      expect(strictIds, isNot(contains(uncategorized)));
    });
  });
}
