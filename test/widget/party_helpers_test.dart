import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:ural_erp/presentation/screens/parties/party_helpers.dart';
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/core/theme/app_colors.dart';

/// Helper to build a Party instance for testing.
Party _makeParty({
  bool isCustomer = false,
  bool isSupplier = false,
  bool isDeliveryCompany = false,
}) {
  return Party(
    id: 1,
    name: 'Test Party',
    isCustomer: isCustomer,
    isSupplier: isSupplier,
    isDeliveryCompany: isDeliveryCompany,
    isFavorite: false,
    balance: 0,
    creditLimit: 0,
    fixedDiscount: 0,
    priceLevel: 'default',
    isActive: true,
    createdAt: DateTime(2026, 1, 1),
    isGlobal: true,
    isSystemDefault: false,
    rowVersion: 0,
  );
}

void main() {
  group('kPriceLevels', () {
    test('contains expected price level keys', () {
      expect(kPriceLevels.containsKey('default'), true);
      expect(kPriceLevels.containsKey('wholesale'), true);
      expect(kPriceLevels.containsKey('talabat'), true);
      expect(kPriceLevels.containsKey('careem'), true);
      expect(kPriceLevels.containsKey('ashyae'), true);
      expect(kPriceLevels.length, 5);
    });
  });

  group('getPartyTypeLabel', () {
    test('returns عميل for customer', () {
      final party = _makeParty(isCustomer: true);
      expect(getPartyTypeLabel(party), 'عميل');
    });

    test('returns مورد for supplier', () {
      final party = _makeParty(isSupplier: true);
      expect(getPartyTypeLabel(party), 'مورد');
    });

    test('returns عميل مورد for dual-type', () {
      final party = _makeParty(isCustomer: true, isSupplier: true);
      expect(getPartyTypeLabel(party), 'عميل مورد');
    });

    test('returns شركة توصيل for delivery company', () {
      final party = _makeParty(isDeliveryCompany: true);
      expect(getPartyTypeLabel(party), 'شركة توصيل');
    });

    test('returns غير محدد for unclassified', () {
      final party = _makeParty();
      expect(getPartyTypeLabel(party), 'غير محدد');
    });
  });

  group('getPartyTypeColor', () {
    test('returns teal for delivery company', () {
      final party = _makeParty(isDeliveryCompany: true);
      expect(getPartyTypeColor(party), Colors.teal);
    });

    test('returns purple for dual-type', () {
      final party = _makeParty(isCustomer: true, isSupplier: true);
      expect(getPartyTypeColor(party), Colors.purple);
    });

    test('returns primary for customer', () {
      final party = _makeParty(isCustomer: true);
      expect(getPartyTypeColor(party), AppColors.primary);
    });

    test('returns warning for supplier', () {
      final party = _makeParty(isSupplier: true);
      expect(getPartyTypeColor(party), AppColors.warning);
    });
  });

  group('getPartyIcon', () {
    test('returns moped icon for delivery company', () {
      final party = _makeParty(isDeliveryCompany: true);
      expect(getPartyIcon(party), PhosphorIconsBold.moped);
    });

    test('returns usersThree icon for dual-type', () {
      final party = _makeParty(isCustomer: true, isSupplier: true);
      expect(getPartyIcon(party), PhosphorIconsBold.usersThree);
    });

    test('returns user icon for customer', () {
      final party = _makeParty(isCustomer: true);
      expect(getPartyIcon(party), PhosphorIconsBold.user);
    });

    test('returns truck icon for supplier', () {
      final party = _makeParty(isSupplier: true);
      expect(getPartyIcon(party), PhosphorIconsBold.truck);
    });
  });

  group('getTypeArabicName', () {
    test('returns العميل for customer key', () {
      expect(getTypeArabicName('customer'), 'العميل');
    });

    test('returns المورد for supplier key', () {
      expect(getTypeArabicName('supplier'), 'المورد');
    });

    test('returns العميل المورد for both key', () {
      expect(getTypeArabicName('both'), 'العميل المورد');
    });

    test('returns الطرف for unknown key', () {
      expect(getTypeArabicName('unknown'), 'الطرف');
    });
  });
}
