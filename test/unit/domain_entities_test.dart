// ISS-QA-01: Domain entity unit tests to raise coverage threshold to 50%
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/domain/usecases/hr/manage_employee_usecase.dart';
import 'package:picpos_erp/domain/usecases/hr/payroll_usecase.dart';
import 'package:picpos_erp/domain/usecases/treasury/close_safe_usecase.dart';
import 'package:picpos_erp/domain/usecases/fixed_assets/manage_asset_usecase.dart';
import 'package:picpos_erp/domain/usecases/manufacturing/execute_production_usecase.dart';
import 'package:picpos_erp/domain/usecases/e_invoicing/submit_einvoice_usecase.dart';
import 'package:picpos_erp/domain/usecases/sales/add_to_cart_usecase.dart';
import 'package:picpos_erp/domain/usecases/purchases/create_purchase_usecase.dart' hide ValidationResult;
import 'package:picpos_erp/domain/entities/invoice_entity.dart';
import 'package:picpos_erp/domain/entities/product_entity.dart';
import 'package:picpos_erp/domain/entities/category_entity.dart';
import 'package:picpos_erp/domain/entities/warehouse_entity.dart';
import 'package:picpos_erp/domain/entities/party_entity.dart';
import 'package:picpos_erp/domain/entities/stock_requisition_entity.dart';
import 'package:picpos_erp/domain/entities/stock_requisition_item_entity.dart';
import 'package:picpos_erp/domain/entities/quotation_entity.dart';
import 'package:picpos_erp/domain/entities/sync_dtos.dart';
import 'package:picpos_erp/domain/entities/accounting_entities.dart';
import 'package:picpos_erp/domain/entities/safe_entity.dart';
import 'package:picpos_erp/domain/entities/user_entity.dart';
import 'package:picpos_erp/domain/entities/branch_entity.dart';
import 'package:picpos_erp/domain/entities/transaction_entity.dart';
import 'package:picpos_erp/domain/entities/cart_item_entity.dart';
import 'package:picpos_erp/domain/entities/purchases_state.dart';
import 'package:picpos_erp/domain/repositories/treasury_repository.dart';
import 'package:picpos_erp/services/e_invoicing/e_invoice_service_wrapper.dart';
import 'package:picpos_erp/core/enums/requisition_status.dart';

// ─── Minimal fake for ITreasuryRepository ────────────────────────────────────
// Only getSafeById and closeSafe are implemented; all other methods are unused
// in these tests and handled by noSuchMethod.
class _FakeTreasuryRepo implements ITreasuryRepository {
  final SafeData? _safe;
  _FakeTreasuryRepo({SafeData? safe}) : _safe = safe;

  @override
  Future<SafeData?> getSafeById(int id) async => _safe;

  @override
  Future<void> closeSafe(int safeId, {double? cashAmount, double? bankAmount, String? notes}) async {}

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError(i.memberName.toString());
}

void main() {
  // ─── InvoiceEntity ────────────────────────────────────────────────────────

  group('InvoiceEntity', () {
    final baseDate = DateTime(2024, 1, 15);

    InvoiceEntity make({
      double total = 100.0,
      double paid = 0.0,
      InvoiceStatus status = InvoiceStatus.pending,
    }) =>
        InvoiceEntity(
          id: 1,
          invoiceNumber: 'INV-001',
          type: InvoiceType.sale,
          invoiceDate: baseDate,
          lines: const [],
          subtotal: total,
          total: total,
          paid: paid,
          status: status,
        );

    test('remaining = total - paid', () {
      expect(make(total: 150, paid: 50).remaining, 100.0);
    });

    test('remaining is zero when fully paid', () {
      expect(make(total: 100, paid: 100).remaining, 0.0);
    });

    test('isFullyPaid when paid >= total', () {
      expect(make(total: 100, paid: 100).isFullyPaid, isTrue);
      expect(make(total: 100, paid: 120).isFullyPaid, isTrue);
    });

    test('isFullyPaid is false when balance remains', () {
      expect(make(total: 100, paid: 50).isFullyPaid, isFalse);
    });

    test('hasPayment when paid > 0', () {
      expect(make(paid: 1).hasPayment, isTrue);
    });

    test('hasPayment is false when paid = 0', () {
      expect(make(paid: 0).hasPayment, isFalse);
    });

    test('copyWith replaces specified fields', () {
      final original = make(total: 100, paid: 0);
      final updated = original.copyWith(paid: 60, invoiceNumber: 'INV-002');
      expect(updated.paid, 60.0);
      expect(updated.invoiceNumber, 'INV-002');
      expect(updated.total, 100.0); // unchanged
      expect(updated.type, InvoiceType.sale); // unchanged
    });

    test('copyWith preserves all unchanged fields', () {
      final original = make(total: 200, paid: 50, status: InvoiceStatus.partial);
      final copy = original.copyWith(notes: 'test note');
      expect(copy.total, 200.0);
      expect(copy.paid, 50.0);
      expect(copy.status, InvoiceStatus.partial);
      expect(copy.notes, 'test note');
    });

    test('InvoiceType.purchase is distinct from sale', () {
      final purchaseInvoice = InvoiceEntity(
        id: 2,
        invoiceNumber: 'PUR-001',
        type: InvoiceType.purchase,
        invoiceDate: baseDate,
        lines: const [],
        subtotal: 500,
        total: 500,
        paid: 500,
        status: InvoiceStatus.paid,
      );
      expect(purchaseInvoice.type, InvoiceType.purchase);
      expect(purchaseInvoice.isFullyPaid, isTrue);
    });

    test('default values: cashPaid, bankPaid, clickPaid = 0', () {
      final entity = make();
      expect(entity.cashPaid, 0.0);
      expect(entity.bankPaid, 0.0);
      expect(entity.clickPaid, 0.0);
    });

    test('copyWith with payment split fields', () {
      final updated = make().copyWith(
        cashPaid: 50.0,
        bankPaid: 30.0,
        clickPaid: 20.0,
      );
      expect(updated.cashPaid, 50.0);
      expect(updated.bankPaid, 30.0);
      expect(updated.clickPaid, 20.0);
    });
  });

  // ─── ProductEntity ────────────────────────────────────────────────────────

  group('ProductEntity', () {
    ProductEntity make({
      double salePrice = 100.0,
      double costPrice = 60.0,
      double currentStock = 10.0,
      double minStock = 5.0,
      bool trackInventory = true,
      bool allowNegativeSale = false,
    }) =>
        ProductEntity(
          id: 1,
          code: 'P001',
          name: 'Test Product',
          salePrice: salePrice,
          costPrice: costPrice,
          currentStock: currentStock,
          minStock: minStock,
          trackInventory: trackInventory,
          allowNegativeSale: allowNegativeSale,
        );

    test('profitMargin is correct', () {
      expect(make(salePrice: 100, costPrice: 80).profitMargin, closeTo(25.0, 0.001));
    });

    test('profitMargin is 0 when costPrice = 0', () {
      expect(make(costPrice: 0).profitMargin, 0.0);
    });

    test('stockValue = currentStock * costPrice', () {
      expect(make(currentStock: 10, costPrice: 50).stockValue, 500.0);
    });

    test('isLowStock when stock <= minStock', () {
      expect(make(currentStock: 3, minStock: 5).isLowStock, isTrue);
      expect(make(currentStock: 5, minStock: 5).isLowStock, isTrue);
    });

    test('isLowStock is false when stock > minStock', () {
      expect(make(currentStock: 6, minStock: 5).isLowStock, isFalse);
    });

    test('isLowStock is false when trackInventory = false', () {
      expect(make(currentStock: 1, minStock: 5, trackInventory: false).isLowStock, isFalse);
    });

    test('isOutOfStock when stock <= 0 and not allowNegativeSale', () {
      expect(make(currentStock: 0, allowNegativeSale: false).isOutOfStock, isTrue);
    });

    test('isOutOfStock is false when allowNegativeSale = true', () {
      expect(make(currentStock: 0, allowNegativeSale: true).isOutOfStock, isFalse);
    });

    test('isOutOfStock is false when trackInventory = false', () {
      expect(make(currentStock: 0, trackInventory: false).isOutOfStock, isFalse);
    });

    test('copyWith updates specified fields', () {
      final updated = make().copyWith(salePrice: 120.0, name: 'Updated');
      expect(updated.salePrice, 120.0);
      expect(updated.name, 'Updated');
      expect(updated.code, 'P001'); // unchanged
    });

    test('default fields have expected values', () {
      final p = make();
      expect(p.taxRate, 14.0);
      expect(p.isActive, isTrue);
      expect(p.isLocked, isFalse);
      expect(p.productType, 'general');
    });
  });

  // ─── CategoryEntity ───────────────────────────────────────────────────────

  group('CategoryEntity', () {
    test('isRoot is true when parentId is null', () {
      const cat = CategoryEntity(id: 1, name: 'Root Category');
      expect(cat.isRoot, isTrue);
    });

    test('isRoot is false when parentId is set', () {
      const cat = CategoryEntity(id: 2, name: 'Sub', parentId: 1);
      expect(cat.isRoot, isFalse);
    });

    test('default color and sortOrder', () {
      const cat = CategoryEntity(id: 1, name: 'Test');
      expect(cat.color, '#2563EB');
      expect(cat.sortOrder, 0);
      expect(cat.isActive, isTrue);
    });

    test('copyWith updates name and preserves rest', () {
      const original = CategoryEntity(id: 1, name: 'Old', sortOrder: 5);
      final updated = original.copyWith(name: 'New');
      expect(updated.name, 'New');
      expect(updated.sortOrder, 5);
      expect(updated.id, 1);
    });

    test('copyWith can deactivate category', () {
      const cat = CategoryEntity(id: 1, name: 'Active');
      final inactive = cat.copyWith(isActive: false);
      expect(inactive.isActive, isFalse);
    });
  });

  // ─── WarehouseEntity ──────────────────────────────────────────────────────

  group('WarehouseEntity', () {
    test('default flags', () {
      const wh = WarehouseEntity(id: 1, name: 'Main');
      expect(wh.isDefault, isFalse);
      expect(wh.isActive, isTrue);
    });

    test('copyWith sets isDefault', () {
      const wh = WarehouseEntity(id: 1, name: 'Storage');
      final updated = wh.copyWith(isDefault: true, location: 'Floor 1');
      expect(updated.isDefault, isTrue);
      expect(updated.location, 'Floor 1');
      expect(updated.name, 'Storage');
    });

    test('copyWith preserves branchId', () {
      const wh = WarehouseEntity(id: 1, name: 'WH', branchId: 3);
      final copy = wh.copyWith(isActive: false);
      expect(copy.branchId, 3);
      expect(copy.isActive, isFalse);
    });
  });

  // ─── PartyEntity ──────────────────────────────────────────────────────────

  group('PartyEntity', () {
    PartyEntity make({
      bool isCustomer = false,
      bool isSupplier = false,
      double balance = 0,
      double creditLimit = 0,
    }) =>
        PartyEntity(
          id: 1,
          name: 'Test Party',
          isCustomer: isCustomer,
          isSupplier: isSupplier,
          balance: balance,
          creditLimit: creditLimit,
        );

    test('isDualRole is true when both customer and supplier', () {
      expect(make(isCustomer: true, isSupplier: true).isDualRole, isTrue);
    });

    test('isDualRole is false for single role', () {
      expect(make(isCustomer: true).isDualRole, isFalse);
      expect(make(isSupplier: true).isDualRole, isFalse);
    });

    test('hasBalance when balance != 0', () {
      expect(make(balance: 100).hasBalance, isTrue);
      expect(make(balance: -50).hasBalance, isTrue);
      expect(make(balance: 0).hasBalance, isFalse);
    });

    test('owes when balance > 0', () {
      expect(make(balance: 100).owes, isTrue);
      expect(make(balance: 0).owes, isFalse);
      expect(make(balance: -100).owes, isFalse);
    });

    test('owed when balance < 0', () {
      expect(make(balance: -100).owed, isTrue);
      expect(make(balance: 0).owed, isFalse);
      expect(make(balance: 100).owed, isFalse);
    });

    test('creditExceeded when balance > creditLimit', () {
      expect(make(balance: 1500, creditLimit: 1000).creditExceeded, isTrue);
    });

    test('creditExceeded is false when balance <= creditLimit', () {
      expect(make(balance: 900, creditLimit: 1000).creditExceeded, isFalse);
    });

    test('creditExceeded is false when creditLimit = 0 (unlimited)', () {
      expect(make(balance: 9999, creditLimit: 0).creditExceeded, isFalse);
    });

    test('availableCredit = creditLimit - balance', () {
      expect(make(balance: 300, creditLimit: 1000).availableCredit, 700.0);
    });

    test('availableCredit is infinite when creditLimit = 0', () {
      expect(make(balance: 9999, creditLimit: 0).availableCredit, double.infinity);
    });

    test('copyWith updates balance', () {
      final updated = make(balance: 0).copyWith(balance: 250.0);
      expect(updated.balance, 250.0);
    });
  });

  // ─── StockRequisitionEntity ───────────────────────────────────────────────

  group('StockRequisitionEntity', () {
    final now = DateTime(2024, 3, 1);

    test('constructor stores all fields', () {
      final entity = StockRequisitionEntity(
        id: 10,
        requisitionNumber: 'REQ-001',
        requisitionDate: now,
        fromBranchId: 1,
        toBranchId: 2,
        status: RequisitionStatus.pending,
        createdByUserId: 5,
        createdAt: now,
      );
      expect(entity.id, 10);
      expect(entity.requisitionNumber, 'REQ-001');
      expect(entity.status, RequisitionStatus.pending);
      expect(entity.fromBranchId, 1);
      expect(entity.toBranchId, 2);
    });

    test('copyWith updates status', () {
      final entity = StockRequisitionEntity(
        id: 1,
        requisitionNumber: 'REQ-001',
        requisitionDate: now,
        fromBranchId: 1,
        toBranchId: 2,
        status: RequisitionStatus.pending,
        createdByUserId: 1,
        createdAt: now,
      );
      final updated = entity.copyWith(status: RequisitionStatus.fulfilled);
      expect(updated.status, RequisitionStatus.fulfilled);
      expect(updated.id, 1);
      expect(updated.requisitionNumber, 'REQ-001');
    });

    test('copyWith with branchNames', () {
      final entity = StockRequisitionEntity(
        id: 1,
        requisitionNumber: 'REQ-002',
        requisitionDate: now,
        fromBranchId: 1,
        toBranchId: 2,
        status: RequisitionStatus.pending,
        createdByUserId: 1,
        createdAt: now,
      );
      final named = entity.copyWith(fromBranchName: 'Cairo', toBranchName: 'Alex');
      expect(named.fromBranchName, 'Cairo');
      expect(named.toBranchName, 'Alex');
    });
  });

  // ─── StockRequisitionItemEntity ───────────────────────────────────────────

  group('StockRequisitionItemEntity', () {
    test('constructor defaults fulfilledQuantity to 0', () {
      const item = StockRequisitionItemEntity(
        id: 1,
        requisitionId: 10,
        productId: 5,
        quantity: 20.0,
      );
      expect(item.fulfilledQuantity, 0.0);
    });

    test('copyWith updates quantity', () {
      const item = StockRequisitionItemEntity(
        id: 1,
        requisitionId: 10,
        productId: 5,
        quantity: 10.0,
      );
      final updated = item.copyWith(quantity: 15.0, fulfilledQuantity: 5.0);
      expect(updated.quantity, 15.0);
      expect(updated.fulfilledQuantity, 5.0);
      expect(updated.productId, 5); // unchanged
    });

    test('copyWith preserves notes', () {
      const item = StockRequisitionItemEntity(
        id: 1,
        requisitionId: 1,
        productId: 1,
        quantity: 1.0,
        notes: 'Urgent',
      );
      final copy = item.copyWith(quantity: 2.0);
      expect(copy.notes, 'Urgent');
    });
  });

  // ─── QuotationEntity / QuotationItemEntity ────────────────────────────────

  group('QuotationEntity', () {
    final baseDate = DateTime(2024, 6, 1);
    final validDate = DateTime(2024, 6, 30);

    test('constructor stores all required fields', () {
      const item = QuotationItemEntity(
        id: 1,
        quotationId: 100,
        productId: 5,
        quantity: 3.0,
        unitPrice: 50.0,
        discount: 0.0,
        total: 150.0,
        taxRate: 14.0,
        taxAmount: 21.0,
        productName: 'Widget',
        productCode: 'W001',
      );
      expect(item.quantity, 3.0);
      expect(item.total, 150.0);
      expect(item.productName, 'Widget');
    });

    test('QuotationEntity default items is empty', () {
      final q = QuotationEntity(
        id: 1,
        quotationNumber: 'Q-001',
        warehouseId: 1,
        userId: 1,
        quotationDate: baseDate,
        validityDate: validDate,
        subtotal: 0,
        discount: 0,
        tax: 0,
        total: 0,
        status: 'draft',
      );
      expect(q.items, isEmpty);
      expect(q.customerId, isNull);
      expect(q.notes, isNull);
    });

    test('QuotationEntity stores joined fields', () {
      final q = QuotationEntity(
        id: 2,
        quotationNumber: 'Q-002',
        warehouseId: 1,
        userId: 1,
        quotationDate: baseDate,
        validityDate: validDate,
        subtotal: 500,
        discount: 10,
        tax: 69,
        total: 559,
        status: 'sent',
        customerName: 'Ahmed',
        userName: 'admin',
      );
      expect(q.customerName, 'Ahmed');
      expect(q.userName, 'admin');
      expect(q.total, 559.0);
    });
  });

  // ─── SyncSaleItem / SyncSaleRequest ──────────────────────────────────────

  group('SyncSaleItem.toJson', () {
    test('serializes all fields', () {
      final item = SyncSaleItem(
        productId: 1,
        quantity: 2.0,
        unitPrice: 50.0,
        discount: 5.0,
        taxRate: 14.0,
        taxAmount: 12.6,
        total: 95.0,
        note: 'no sugar',
        costPrice: 30.0,
      );
      final json = item.toJson();
      expect(json['productId'], 1);
      expect(json['quantity'], 2.0);
      expect(json['unitPrice'], 50.0);
      expect(json['discount'], 5.0);
      expect(json['taxRate'], 14.0);
      expect(json['taxAmount'], 12.6);
      expect(json['total'], 95.0);
      expect(json['note'], 'no sugar');
      expect(json['costPrice'], 30.0);
    });

    test('note defaults to null', () {
      final item = SyncSaleItem(
        productId: 2,
        quantity: 1.0,
        unitPrice: 10.0,
        discount: 0.0,
        taxRate: 0.0,
        taxAmount: 0.0,
        total: 10.0,
        costPrice: 7.0,
      );
      expect(item.toJson()['note'], isNull);
    });
  });

  group('SyncSaleRequest.toJson', () {
    SyncSaleItem makeItem() => SyncSaleItem(
          productId: 1,
          quantity: 1.0,
          unitPrice: 100.0,
          discount: 0,
          taxRate: 0,
          taxAmount: 0,
          total: 100.0,
          costPrice: 70.0,
        );

    test('serializes required fields', () {
      final req = SyncSaleRequest(
        invoiceNumber: 'INV-999',
        warehouseId: 1,
        userId: 2,
        subtotal: 100.0,
        discount: 0,
        tax: 0,
        total: 100.0,
        paid: 100.0,
        paymentMethod: 'cash',
        items: [makeItem()],
      );
      final json = req.toJson();
      expect(json['invoiceNumber'], 'INV-999');
      expect(json['warehouseId'], 1);
      expect(json['userId'], 2);
      expect(json['paymentMethod'], 'cash');
      expect((json['items'] as List).length, 1);
    });

    test('adhoc customer fields are serialized', () {
      final req = SyncSaleRequest(
        invoiceNumber: 'INV-888',
        warehouseId: 1,
        userId: 1,
        subtotal: 50.0,
        discount: 0,
        tax: 0,
        total: 50.0,
        paid: 50.0,
        paymentMethod: 'cash',
        items: [makeItem()],
        adhocCustomerName: 'Walk-in',
        adhocCustomerPhone: '0501234567',
        adhocCustomerNote: 'Table 3',
      );
      final json = req.toJson();
      expect(json['adhocCustomerName'], 'Walk-in');
      expect(json['adhocCustomerPhone'], '0501234567');
      expect(json['adhocCustomerNote'], 'Table 3');
    });

    test('optional fields default correctly', () {
      final req = SyncSaleRequest(
        invoiceNumber: 'INV-1',
        warehouseId: 1,
        userId: 1,
        subtotal: 10,
        discount: 0,
        tax: 0,
        total: 10,
        paid: 10,
        paymentMethod: 'cash',
        items: [],
      );
      final json = req.toJson();
      expect(json['customerId'], isNull);
      expect(json['branchId'], isNull);
      expect(json['deliveryFee'], 0.0);
      expect(json['saleType'], 'default');
      expect(json['adhocCustomerName'], isNull);
      expect(json['adhocCustomerPhone'], isNull);
      expect(json['adhocCustomerNote'], isNull);
    });
  });

  // ─── InvoiceLineEntity ────────────────────────────────────────────────────

  group('InvoiceLineEntity', () {
    test('stores all fields', () {
      const line = InvoiceLineEntity(
        id: 10,
        productId: 5,
        productName: 'Coffee',
        quantity: 3.0,
        unitPrice: 15.0,
        discountPercent: 10.0,
        total: 40.5,
      );
      expect(line.productName, 'Coffee');
      expect(line.quantity, 3.0);
      expect(line.discountPercent, 10.0);
      expect(line.total, 40.5);
    });

    test('discountPercent defaults to 0', () {
      const line = InvoiceLineEntity(
        productId: 1,
        productName: 'Tea',
        quantity: 1.0,
        unitPrice: 10.0,
        total: 10.0,
      );
      expect(line.discountPercent, 0.0);
    });
  });

  // ─── ProductEntity additional edge cases ─────────────────────────────────

  group('ProductEntity edge cases', () {
    test('negative profitMargin when cost > sale price', () {
      const p = ProductEntity(
        id: 1,
        code: 'X',
        name: 'X',
        salePrice: 50.0,
        costPrice: 80.0,
        currentStock: 10,
        minStock: 0,
      );
      expect(p.profitMargin, isNegative);
    });

    test('stockValue is 0 when currentStock = 0', () {
      const p = ProductEntity(
        id: 1,
        code: 'X',
        name: 'X',
        salePrice: 100,
        costPrice: 60,
        currentStock: 0,
        minStock: 0,
      );
      expect(p.stockValue, 0.0);
    });

    test('copyWith preserves all when nothing changed', () {
      const original = ProductEntity(
        id: 5,
        code: 'P5',
        name: 'Five',
        salePrice: 99.0,
        costPrice: 55.0,
        currentStock: 20.0,
        minStock: 5.0,
        taxRate: 5.0,
        productType: 'perishable',
      );
      final copy = original.copyWith();
      expect(copy.id, 5);
      expect(copy.salePrice, 99.0);
      expect(copy.taxRate, 5.0);
      expect(copy.productType, 'perishable');
    });
  });

  // ─── PartyEntity additional edge cases ───────────────────────────────────

  group('PartyEntity additional edge cases', () {
    test('availableCredit negative when over limit', () {
      const party = PartyEntity(id: 1, name: 'P', balance: 1200, creditLimit: 1000);
      expect(party.availableCredit, -200.0);
    });

    test('copyWith updates all fields', () {
      const original = PartyEntity(
        id: 1,
        name: 'Old',
        phone: '555',
        email: 'a@b.com',
        address: 'Street 1',
        isCustomer: true,
        balance: 100,
        creditLimit: 500,
        taxNumber: 'TX-1',
        notes: 'VIP',
      );
      final updated = original.copyWith(name: 'New', balance: 200, notes: 'Regular');
      expect(updated.name, 'New');
      expect(updated.balance, 200);
      expect(updated.notes, 'Regular');
      expect(updated.phone, '555'); // unchanged
      expect(updated.email, 'a@b.com'); // unchanged
      expect(updated.creditLimit, 500); // unchanged
    });
  });

  // ─── HR domain classes ────────────────────────────────────────────────────

  group('EmployeeInput', () {
    test('stores required fields with defaults', () {
      final input = EmployeeInput(name: 'Ahmed', salary: 3000);
      expect(input.name, 'Ahmed');
      expect(input.salary, 3000.0);
      expect(input.role, 'staff');
      expect(input.salaryType, 'monthly');
      expect(input.phone, isNull);
    });

    test('stores optional fields', () {
      final input = EmployeeInput(
        name: 'Sara',
        phone: '0501234567',
        role: 'manager',
        salary: 5000.0,
        salaryType: 'hourly',
      );
      expect(input.phone, '0501234567');
      expect(input.role, 'manager');
      expect(input.salaryType, 'hourly');
    });
  });

  group('EmployeeResult', () {
    test('success stores employeeId', () {
      final result = EmployeeResult.success(42);
      expect(result.isSuccess, isTrue);
      expect(result.employeeId, 42);
      expect(result.error, isNull);
    });

    test('success without employeeId', () {
      final result = EmployeeResult.success();
      expect(result.isSuccess, isTrue);
      expect(result.employeeId, isNull);
    });

    test('failure stores error message', () {
      final result = EmployeeResult.failure('خطأ في البيانات');
      expect(result.isSuccess, isFalse);
      expect(result.error, 'خطأ في البيانات');
      expect(result.employeeId, isNull);
    });
  });

  group('PayrollResult', () {
    test('success with netAmount', () {
      final result = PayrollResult.success(4500.0);
      expect(result.isSuccess, isTrue);
      expect(result.netAmount, 4500.0);
      expect(result.error, isNull);
    });

    test('success without netAmount', () {
      final result = PayrollResult.success();
      expect(result.isSuccess, isTrue);
      expect(result.netAmount, isNull);
    });

    test('failure stores error', () {
      final result = PayrollResult.failure('الراتب الصافي يجب أن يكون أكبر من صفر');
      expect(result.isSuccess, isFalse);
      expect(result.error, isNotNull);
      expect(result.netAmount, isNull);
    });
  });

  // ─── Treasury domain classes ──────────────────────────────────────────────

  group('SafeClosingResult', () {
    test('isBalanced is true when difference < 0.01', () {
      const result = SafeClosingResult(
        safeId: 1,
        expectedBalance: 1000.0,
        actualBalance: 1000.005,
        difference: 0.005,
        isBalanced: true,
      );
      expect(result.isBalanced, isTrue);
      expect(result.safeId, 1);
      expect(result.difference, 0.005);
    });

    test('isBalanced is false when difference >= 0.01', () {
      const result = SafeClosingResult(
        safeId: 2,
        expectedBalance: 1000.0,
        actualBalance: 999.0,
        difference: -1.0,
        isBalanced: false,
      );
      expect(result.isBalanced, isFalse);
      expect(result.difference, -1.0);
    });

    test('stores expected and actual balance', () {
      const result = SafeClosingResult(
        safeId: 3,
        expectedBalance: 500.0,
        actualBalance: 550.0,
        difference: 50.0,
        isBalanced: false,
      );
      expect(result.expectedBalance, 500.0);
      expect(result.actualBalance, 550.0);
    });
  });

  // ─── Fixed Assets domain classes ─────────────────────────────────────────

  group('AssetInput', () {
    test('stores required fields with defaults', () {
      final input = AssetInput(
        code: 'A001',
        name: 'Office Chair',
        categoryId: 2,
        purchasePrice: 500.0,
        purchaseDate: DateTime(2024, 1, 1),
        usefulLifeYears: 5.0,
      );
      expect(input.code, 'A001');
      expect(input.name, 'Office Chair');
      expect(input.categoryId, 2);
      expect(input.purchasePrice, 500.0);
      expect(input.usefulLifeYears, 5.0);
      expect(input.salvageValue, 0.0);
      expect(input.depreciationMethod, 'straight_line');
      expect(input.location, isNull);
    });

    test('stores optional fields', () {
      final input = AssetInput(
        code: 'A002',
        name: 'Server',
        categoryId: 3,
        purchasePrice: 10000.0,
        purchaseDate: DateTime(2023, 6, 15),
        usefulLifeYears: 3.0,
        location: 'IT Room',
        salvageValue: 1000.0,
        depreciationMethod: 'declining_balance',
        notes: 'Dell server',
        costCenterId: 5,
      );
      expect(input.location, 'IT Room');
      expect(input.salvageValue, 1000.0);
      expect(input.depreciationMethod, 'declining_balance');
      expect(input.costCenterId, 5);
    });
  });

  group('DisposeAssetInput', () {
    test('stores all fields', () {
      final input = DisposeAssetInput(
        assetId: 10,
        disposalValue: 200.0,
        disposalDate: DateTime(2024, 3, 1),
        costCenterId: 2,
      );
      expect(input.assetId, 10);
      expect(input.disposalValue, 200.0);
      expect(input.costCenterId, 2);
    });

    test('costCenterId defaults to null', () {
      final input = DisposeAssetInput(
        assetId: 5,
        disposalValue: 0.0,
        disposalDate: DateTime(2024, 1, 1),
      );
      expect(input.costCenterId, isNull);
    });
  });

  group('AssetResult', () {
    test('success stores assetId', () {
      final result = AssetResult.success(99);
      expect(result.isSuccess, isTrue);
      expect(result.assetId, 99);
      expect(result.error, isNull);
    });

    test('success without assetId', () {
      final result = AssetResult.success();
      expect(result.isSuccess, isTrue);
      expect(result.assetId, isNull);
    });

    test('failure stores error', () {
      final result = AssetResult.failure('يجب إدخال كود الأصل');
      expect(result.isSuccess, isFalse);
      expect(result.error, 'يجب إدخال كود الأصل');
      expect(result.assetId, isNull);
    });
  });

  // ─── Manufacturing domain classes ─────────────────────────────────────────

  group('ProductionOrderInput', () {
    test('stores required fields', () {
      final input = ProductionOrderInput(
        bomId: 3,
        orderedQty: 50.0,
        warehouseId: 1,
        startDate: DateTime(2024, 4, 1),
      );
      expect(input.bomId, 3);
      expect(input.orderedQty, 50.0);
      expect(input.warehouseId, 1);
      expect(input.notes, isNull);
    });

    test('stores optional notes', () {
      final input = ProductionOrderInput(
        bomId: 1,
        orderedQty: 10.0,
        warehouseId: 2,
        startDate: DateTime(2024, 5, 1),
        notes: 'Urgent batch',
      );
      expect(input.notes, 'Urgent batch');
    });
  });

  group('ProductionResult', () {
    test('success stores orderId', () {
      final result = ProductionResult.success(77);
      expect(result.isSuccess, isTrue);
      expect(result.orderId, 77);
      expect(result.error, isNull);
    });

    test('success without orderId', () {
      final result = ProductionResult.success();
      expect(result.isSuccess, isTrue);
      expect(result.orderId, isNull);
    });

    test('failure stores error', () {
      final result = ProductionResult.failure('مكونات المنتج غير كافية');
      expect(result.isSuccess, isFalse);
      expect(result.error, 'مكونات المنتج غير كافية');
    });
  });

  // ─── E-Invoice domain classes ─────────────────────────────────────────────

  group('EInvoiceResult', () {
    test('success stores submissionId and documentUuid', () {
      final result = EInvoiceResult.success(
        submissionId: 'SUB-123',
        documentUuid: 'UUID-456',
      );
      expect(result.isSuccess, isTrue);
      expect(result.submissionId, 'SUB-123');
      expect(result.documentUuid, 'UUID-456');
      expect(result.error, isNull);
    });

    test('success without optional fields', () {
      final result = EInvoiceResult.success();
      expect(result.isSuccess, isTrue);
      expect(result.submissionId, isNull);
      expect(result.documentUuid, isNull);
    });

    test('failure stores error message', () {
      final result = EInvoiceResult.failure('خدمة الفوترة الإلكترونية غير مفعلة');
      expect(result.isSuccess, isFalse);
      expect(result.error, 'خدمة الفوترة الإلكترونية غير مفعلة');
      expect(result.submissionId, isNull);
      expect(result.documentUuid, isNull);
    });
  });

  // ─── QuotationItemEntity ──────────────────────────────────────────────────

  group('QuotationItemEntity', () {
    test('constructor sets all fields', () {
      const item = QuotationItemEntity(
        id: 1,
        quotationId: 10,
        productId: 5,
        quantity: 2.0,
        unitPrice: 50.0,
        discount: 0.0,
        total: 100.0,
        taxRate: 0.0,
        taxAmount: 0.0,
      );
      expect(item.quotationId, 10);
      expect(item.productId, 5);
    });
  });

  // ─── JournalLine ──────────────────────────────────────────────────────────

  group('JournalLine', () {
    test('toString includes accountId and amounts', () {
      final line = JournalLine(accountId: 1001, debit: 500.0, credit: 0.0);
      final s = line.toString();
      expect(s, contains('1001'));
      expect(s, contains('500.0'));
    });
  });

  // ─── CloseSafeUseCase ─────────────────────────────────────────────────────

  group('CloseSafeUseCase', () {
    test('returns balanced result when difference is tiny', () async {
      final repo = _FakeTreasuryRepo(
        safe: const SafeData(
          id: 1, name: 'Cash', safeType: 'cash', balance: 1000.0,
          isDefault: true, isActive: true,
        ),
      );
      final useCase = CloseSafeUseCase(repo);
      final result = await useCase.execute(safeId: 1, actualBalance: 1000.0);
      expect(result.isBalanced, isTrue);
      expect(result.expectedBalance, 1000.0);
      expect(result.actualBalance, 1000.0);
    });

    test('throws when safe not found', () async {
      final repo = _FakeTreasuryRepo(safe: null);
      final useCase = CloseSafeUseCase(repo);
      await expectLater(
        useCase.execute(safeId: 99, actualBalance: 0),
        throwsA(isA<StateError>()),
      );
    });
  });

  // ─── AddToCartUseCase – offer note paths ──────────────────────────────────

  group('AddToCartUseCase – offer note merge', () {
    final useCase = AddToCartUseCase();
    const existingItem = CartItemEntity(
      productId: 1,
      productName: 'Tea',
      productCode: 'T1',
      quantity: 1,
      unitPrice: 10.0,
      note: 'عرض: buy 2',
    );

    test('merges with auto-discount offer item when same product', () {
      final result = useCase.execute(
        currentCart: [existingItem],
        productId: 1,
        productName: 'Tea',
        productCode: 'T1',
        unitPrice: 10.0,
        customPrice: 8.0,
      );
      expect(result.length, 1);
      expect(result[0].quantity, 2.0);
    });
  });

  // ─── PurchaseResult getters ───────────────────────────────────────────────

  group('PurchaseResult', () {
    test('invoiceId returns id for success', () {
      final result = PurchaseResult.success(
        invoiceId: 42,
        totals: const PurchaseTotals(subtotal: 100, itemCount: 1),
      );
      expect(result.invoiceId, 42);
      expect(result.errorMessage, isNull);
    });

    test('errorMessage returns message for failure', () {
      final result = PurchaseResult.failure('خطأ في الفاتورة');
      expect(result.errorMessage, 'خطأ في الفاتورة');
      expect(result.invoiceId, isNull);
    });
  });

  // ─── SubmitEInvoiceUseCase – validation ───────────────────────────────────

  group('SubmitEInvoiceUseCase – validation', () {
    final useCase = SubmitEInvoiceUseCase(EInvoiceServiceWrapper());

    UnifiedInvoice makeInvoice({String id = 'INV-001', List<UnifiedLineItem>? items}) =>
        UnifiedInvoice(
          internalId: id,
          issueDate: DateTime(2024, 1, 1),
          seller: const {'name': 'Test Co'},
          items: items ?? const [],
        );

    test('fails when internalId is empty', () async {
      final result = await useCase.submit(makeInvoice(id: ''));
      expect(result.isSuccess, isFalse);
      expect(result.error, contains('رقم الفاتورة'));
    });

    test('fails when totalAmount is zero', () async {
      final result = await useCase.submit(makeInvoice(items: const []));
      expect(result.isSuccess, isFalse);
      expect(result.error, contains('إجمالي الفاتورة'));
    });
  });

  // ─── SafeEntity copyWith – uncovered branch ───────────────────────────────

  group('SafeEntity copyWith', () {
    test('preserves balance when not overridden', () {
      const safe = SafeEntity(id: 1, name: 'Main', type: 'cash', balance: 500.0);
      final copy = safe.copyWith(name: 'Secondary');
      expect(copy.balance, 500.0);
    });
  });

  // ─── UserEntity copyWith – permissions branch ─────────────────────────────

  group('UserEntity copyWith', () {
    test('preserves permissions when not overridden', () {
      const user = UserEntity(
        id: 1, username: 'admin', displayName: 'Admin',
        permissions: ['pos', 'reports'],
      );
      final copy = user.copyWith(username: 'admin2');
      expect(copy.permissions, ['pos', 'reports']);
    });
  });

  // ─── BranchEntity copyWith – address/phone branches ──────────────────────

  group('BranchEntity copyWith', () {
    test('preserves address and phone when not overridden', () {
      const branch = BranchEntity(id: 1, name: 'Main', address: '123 St', phone: '555');
      final copy = branch.copyWith(name: 'Secondary');
      expect(copy.address, '123 St');
      expect(copy.phone, '555');
    });
  });

  // ─── TransactionEntity copyWith – amount branch ──────────────────────────

  group('TransactionEntity copyWith', () {
    test('preserves amount when not overridden', () {
      final tx = TransactionEntity(
        id: 1, safeId: 1, transactionType: 'receipt',
        amount: 200.0, category: 'sale', createdAt: DateTime(2024),
      );
      final copy = tx.copyWith(category: 'other');
      expect(copy.amount, 200.0);
    });
  });

  // ─── PurchaseCartItemEntity copyWith – unitCost/taxRate branches ──────────

  group('PurchaseCartItemEntity copyWith', () {
    test('preserves unitCost and taxRate when not overridden', () {
      const item = PurchaseCartItemEntity(
        productId: 1, productName: 'Item', productCode: 'I1',
        quantity: 2.0, unitCost: 50.0, taxRate: 10.0,
      );
      final copy = item.copyWith(productName: 'Item Updated');
      expect(copy.unitCost, 50.0);
      expect(copy.taxRate, 10.0);
    });
  });
}
