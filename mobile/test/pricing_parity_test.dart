import 'dart:convert';
import 'dart:io';

import 'package:picpos_van/domain/pricing.dart';
import 'package:flutter_test/flutter_test.dart';

/// Same fixture and assertions as server/test/pricing_parity_test.dart: the
/// device computes exactly what the cloud gate accepts.
final Map<String, dynamic> fixture = jsonDecode(
        File('../docs/mobile/fixtures/pricing_parity.json').readAsStringSync())
    as Map<String, dynamic>;

double d(Object? v) => (v as num).toDouble();

void main() {
  group('taxRate', () {
    for (final c in fixture['taxRate'] as List) {
      test('${c['rate']}/${c['exempt']}/${c['companyDefault']}', () {
        expect(
            effectiveItemTaxRate(
                rate: d(c['rate']), exempt: c['exempt'] as bool, companyDefault: d(c['companyDefault'])),
            d(c['expect']));
      });
    }
  });

  group('totals', () {
    for (final c in fixture['totals'] as List) {
      test(c['name'], () {
        final t = computeTotals([
          for (final l in c['lines'] as List)
            LineInput(
                quantity: d(l['quantity']),
                unitPrice: d(l['unitPrice']),
                discount: d(l['discount']),
                taxRate: d(l['taxRate'])),
        ], pricesIncludeTax: c['pricesIncludeTax'] as bool, decimals: c['decimals'] as int);
        final e = c['expect'] as Map;
        expect([t.subtotal, t.discount, t.net, t.tax, t.total],
            [d(e['subtotal']), d(e['discount']), d(e['net']), d(e['tax']), d(e['total'])]);
        expect([for (final l in t.lines) [l.net, l.tax, l.total]],
            [for (final l in e['lines'] as List) [d(l['net']), d(l['tax']), d(l['total'])]]);
      });
    }
  });

  group('price resolution', () {
    for (final c in fixture['price'] as List) {
      test(c['name'], () {
        final r = resolveUnitPrice(
          salePrice: d(c['salePrice']),
          wholesalePrice: c['wholesalePrice'] == null ? null : d(c['wholesalePrice']),
          priceLevel: c['priceLevel'] as String?,
          quantity: d(c['quantity']),
          today: DateTime.parse(c['today'] as String),
          entries: [
            for (final l in c['lists'] as List)
              for (final i in l['items'] as List)
                PriceListEntry(
                  listGlobalId: l['globalId'] as String,
                  isDefault: l['isDefault'] as bool,
                  isActive: l['isActive'] as bool,
                  startDate: l['startDate'] as String?,
                  endDate: l['endDate'] as String?,
                  listOrder: l['order'] as int,
                  price: d(i['price']),
                  minQuantity: d(i['minQuantity']),
                ),
          ],
        );
        final e = c['expect'] as Map;
        expect((r.price, r.source, r.listGlobalId), (d(e['price']), e['source'], e['listGlobalId']));
      });
    }
  });

  group('return lines', () {
    for (final c in fixture['returnLines'] as List) {
      test(c['name'], () {
        final s = c['sold'] as Map;
        final r = returnLineAmounts(
            SoldProduct(
              soldQty: d(s['soldQty']),
              soldTotal: d(s['soldTotal']),
              soldTax: d(s['soldTax']),
              returnedQty: d(s['returnedQty']),
              returnedTotal: d(s['returnedTotal']),
              returnedTax: d(s['returnedTax']),
            ),
            d(c['quantity']),
            decimals: c['decimals'] as int);
        final e = c['expect'] as Map?;
        if (e == null) {
          expect(r, isNull);
        } else {
          expect([r!.total, r.tax, r.net], [d(e['total']), d(e['tax']), d(e['net'])]);
        }
      });
    }
  });

  group('return settlement', () {
    for (final c in fixture['settlement'] as List) {
      test(c['name'], () {
        final r = returnSettlement(
          invoiceTotal: d(c['invoiceTotal']),
          invoicePaid: d(c['invoicePaid']),
          previousArOffset: d(c['previousArOffset']),
          returnTotal: d(c['returnTotal']),
        );
        final e = c['expect'] as Map;
        expect((r.arOffset, r.cashRefund), (d(e['arOffset']), d(e['cashRefund'])));
      });
    }
  });
}
