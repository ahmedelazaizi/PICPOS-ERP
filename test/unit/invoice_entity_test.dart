// ═══════════════════════════════════════════════════════════════════════════
// InvoiceEntity — Unit Tests (coverage: invoice_entity.dart)
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/domain/entities/invoice_entity.dart';

// Helper to build a minimal InvoiceEntity without optional fields
InvoiceEntity _makeInvoice({
  String invoiceNumber = 'INV-001',
  double subtotal = 100,
  double discountAmount = 0,
  double taxAmount = 0,
  double total = 100,
  double paid = 0,
  InvoiceStatus status = InvoiceStatus.pending,
  List<InvoiceLineEntity> lines = const [],
}) {
  return InvoiceEntity(
    invoiceNumber: invoiceNumber,
    type: InvoiceType.sale,
    invoiceDate: DateTime(2026, 1, 1),
    lines: lines,
    subtotal: subtotal,
    discountAmount: discountAmount,
    taxAmount: taxAmount,
    total: total,
    paid: paid,
    status: status,
  );
}

void main() {
  // ── Computed properties ────────────────────────────────────────────────────
  group('InvoiceEntity.remaining', () {
    test('is total - paid when paid < total', () {
      final inv = _makeInvoice(total: 500, paid: 200);
      expect(inv.remaining, closeTo(300, 0.001));
    });

    test('is zero when fully paid', () {
      final inv = _makeInvoice(total: 300, paid: 300);
      expect(inv.remaining, closeTo(0, 0.001));
    });

    test('is negative when overpaid', () {
      final inv = _makeInvoice(total: 200, paid: 250);
      expect(inv.remaining, closeTo(-50, 0.001));
    });
  });

  group('InvoiceEntity.isFullyPaid', () {
    test('true when paid == total', () {
      final inv = _makeInvoice(total: 400, paid: 400);
      expect(inv.isFullyPaid, isTrue);
    });

    test('true when overpaid', () {
      final inv = _makeInvoice(total: 100, paid: 150);
      expect(inv.isFullyPaid, isTrue);
    });

    test('false when unpaid', () {
      final inv = _makeInvoice(total: 100, paid: 0);
      expect(inv.isFullyPaid, isFalse);
    });

    test('false when partially paid', () {
      final inv = _makeInvoice(total: 100, paid: 60);
      expect(inv.isFullyPaid, isFalse);
    });
  });

  group('InvoiceEntity.hasPayment', () {
    test('true when paid > 0', () {
      final inv = _makeInvoice(paid: 1);
      expect(inv.hasPayment, isTrue);
    });

    test('false when paid == 0', () {
      final inv = _makeInvoice(paid: 0);
      expect(inv.hasPayment, isFalse);
    });
  });

  // ── copyWith ───────────────────────────────────────────────────────────────
  group('InvoiceEntity.copyWith', () {
    test('changes specified fields', () {
      final inv = _makeInvoice(
          invoiceNumber: 'INV-100', total: 500, paid: 0);

      final updated = inv.copyWith(
        invoiceNumber: 'INV-200',
        paid: 250,
        status: InvoiceStatus.partial,
      );

      expect(updated.invoiceNumber, 'INV-200');
      expect(updated.paid, 250);
      expect(updated.status, InvoiceStatus.partial);
    });

    test('preserves unchanged fields', () {
      final inv = _makeInvoice(
        invoiceNumber: 'INV-001',
        subtotal: 800,
        total: 880,
        taxAmount: 80,
        paid: 0,
      );

      final updated = inv.copyWith(paid: 880);

      expect(updated.invoiceNumber, 'INV-001');
      expect(updated.subtotal, 800);
      expect(updated.total, 880);
      expect(updated.taxAmount, 80);
      expect(updated.type, InvoiceType.sale);
    });

    test('can set isLocked flag', () {
      final inv = _makeInvoice();
      expect(inv.isLocked, isFalse);

      final locked = inv.copyWith(isLocked: true);
      expect(locked.isLocked, isTrue);
    });

    test('can set optional fields via copyWith', () {
      final inv = _makeInvoice();
      final withSeller = inv.copyWith(
        sellerId: 3,
        sellerName: 'Omar',
        notes: 'Test note',
        paymentMethod: 'cash',
      );
      expect(withSeller.sellerId, 3);
      expect(withSeller.sellerName, 'Omar');
      expect(withSeller.notes, 'Test note');
      expect(withSeller.paymentMethod, 'cash');
    });
  });

  // ── InvoiceLineEntity ───────────────────────────────────────────────────────
  group('InvoiceLineEntity', () {
    test('stores fields correctly', () {
      const line = InvoiceLineEntity(
        productId: 5,
        productName: 'Rice 1kg',
        quantity: 3,
        unitPrice: 10,
        total: 30,
      );
      expect(line.productId, 5);
      expect(line.productName, 'Rice 1kg');
      expect(line.quantity, 3);
      expect(line.unitPrice, 10);
      expect(line.total, 30);
      expect(line.discountPercent, 0);
      expect(line.id, isNull);
    });

    test('discountPercent default is 0', () {
      const line = InvoiceLineEntity(
        productId: 1,
        productName: 'X',
        quantity: 1,
        unitPrice: 50,
        total: 50,
      );
      expect(line.discountPercent, 0);
    });
  });

  // ── Enum values ─────────────────────────────────────────────────────────────
  group('InvoiceType enum', () {
    test('has expected values', () {
      expect(InvoiceType.values, contains(InvoiceType.sale));
      expect(InvoiceType.values, contains(InvoiceType.purchase));
      expect(InvoiceType.values, contains(InvoiceType.saleReturn));
      expect(InvoiceType.values, contains(InvoiceType.purchaseReturn));
    });
  });

  group('InvoiceStatus enum', () {
    test('has expected values', () {
      const expected = [
        InvoiceStatus.draft,
        InvoiceStatus.pending,
        InvoiceStatus.partial,
        InvoiceStatus.paid,
        InvoiceStatus.cancelled,
        InvoiceStatus.returned,
        InvoiceStatus.partialReturn,
      ];
      for (final s in expected) {
        expect(InvoiceStatus.values, contains(s));
      }
    });
  });

  // ── InvoiceEntity optional fields ──────────────────────────────────────────
  group('InvoiceEntity defaults', () {
    test('cashPaid, bankPaid, clickPaid default to 0', () {
      final inv = _makeInvoice();
      expect(inv.cashPaid, 0);
      expect(inv.bankPaid, 0);
      expect(inv.clickPaid, 0);
    });

    test('isLocked defaults to false', () {
      final inv = _makeInvoice();
      expect(inv.isLocked, isFalse);
    });

    test('discountAmount defaults to 0', () {
      final inv = _makeInvoice();
      expect(inv.discountAmount, 0);
    });
  });
}
