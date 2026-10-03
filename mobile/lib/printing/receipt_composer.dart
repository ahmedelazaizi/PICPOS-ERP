/// Builds the printable [Receipt] of a saved field document (outbox entry)
/// from the device's last-synced data — so printing works offline and a
/// reprint shows the same values (plus the cloud signature once accepted).
library;

import '../data/local_store.dart';
import '../state/app_controller.dart';
import 'receipt_model.dart';

/// Kinds that have a receipt.
const kPrintableKinds = {'sales_invoice', 'sales_return', 'collection', kExpenseKind};

double _d(Object? v) => ((v as num?) ?? 0).toDouble();

class ReceiptComposer {
  ReceiptComposer(this.c);
  final AppController c;

  ReceiptCompany get company => ReceiptCompany.fromProfile(c.company);

  Future<ReceiptParty> _party(Map<String, Object?> p) async {
    final customer = await c.store.get(Kinds.customers, '${p['customerGlobalId']}');
    // J3 — a cash-customer sale prints its one-time name instead.
    final oneTime = p['customerName'];
    return ReceiptParty(
      customerName: oneTime is String && oneTime.trim().isNotEmpty ? oneTime.trim() : '${customer?['name'] ?? ''}',
      repName: c.repName,
      routeName: c.routeNames[customer?['routeGlobalId']],
    );
  }

  DateTime _date(OutboxEntry e) => DateTime.tryParse('${e.payload['date']}')?.toLocal() ?? e.createdAt;

  Future<Receipt> compose(OutboxEntry e, {String locale = 'ar', bool reprint = false}) async {
    final p = e.payload;
    final b = ReceiptBuilder(company, locale: locale);
    switch (e.kind) {
      case 'sales_invoice':
        final lines = <ReceiptLineData>[];
        for (final l in (p['lines'] as List).cast<Map>()) {
          final q = _d(l['quantity']), price = _d(l['unitPrice']);
          lines.add(ReceiptLineData(
            name: (l['_name'] as String?) ?? await c.nameOf(Kinds.products, l['productGlobalId']),
            quantity: q,
            unitPrice: price,
            total: l['_total'] is num ? _d(l['_total']) : q * price,
          ));
        }
        final total = _d(p['total']);
        final tax = _d(p['_tax']);
        return b.salesInvoice(
          globalId: e.globalId,
          number: '${p['number']}',
          date: _date(e),
          party: await _party(p),
          lines: lines,
          net: p['_net'] is num ? _d(p['_net']) : total - tax,
          tax: tax,
          total: total,
          paid: _d(p['paid']),
          newBalance: p['_balanceAfter'] is num ? _d(p['_balanceAfter']) : null,
          integrityHash: p['_integrityHash'] as String?,
          reprint: reprint,
        );
      case 'sales_return':
        final inv = await c.store.get(Kinds.invoices, '${p['originalInvoiceGlobalId']}');
        final sold = {
          for (final l in ((inv?['lines'] as List?) ?? const []).cast<Map>()) l['productGlobalId']: l,
        };
        final lines = <ReceiptLineData>[];
        for (final l in (p['lines'] as List).cast<Map>()) {
          final q = _d(l['quantity']);
          final total = _d(l['_total']);
          final s = sold[l['productGlobalId']];
          lines.add(ReceiptLineData(
            name: await c.nameOf(Kinds.products, l['productGlobalId']),
            quantity: q,
            unitPrice: s != null && _d(s['quantity']) > 0 ? _d(s['total']) / _d(s['quantity']) : (q > 0 ? total / q : 0),
            total: total,
          ));
        }
        final total = _d(p['total']);
        return b.salesReturn(
          number: '${p['number']}',
          date: _date(e),
          party: await _party(p),
          originalNumber: (p['_originalNumber'] ?? inv?['number']) as String?,
          lines: lines,
          total: total,
          tax: _d(p['_tax']),
          arOffset: _d(p['_arOffset']),
          cashRefund: _d(p['cashRefund']),
          newBalance: p['_balanceAfter'] is num ? _d(p['_balanceAfter']) : null,
          reason: p['reason'] as String?,
          integrityHash: p['_integrityHash'] as String?,
          reprint: reprint,
        );
      case 'collection':
        return b.collection(
          number: '${p['_bookPrefix'] ?? ''}${p['bookNumber']}',
          date: _date(e),
          party: await _party(p),
          amount: _d(p['amount']),
          newBalance: p['_balanceAfter'] is num ? _d(p['_balanceAfter']) : null,
          reprint: reprint,
        );
      case kExpenseKind:
        final en = locale == 'en' && p['_categoryNameEn'] is String;
        return b.expense(
          number: '${p['_bookPrefix'] ?? ''}${p['bookNumber']}',
          date: _date(e),
          repName: c.repName,
          routeName: c.routeNames[p['routeGlobalId']],
          category: '${en ? p['_categoryNameEn'] : p['_categoryName'] ?? ''}',
          amount: _d(p['amount']),
          note: p['note'] as String?,
          custodyAfter: p['_custodyAfter'] is num ? _d(p['_custodyAfter']) : null,
          overCustody: p['_overCustody'] == true,
          reprint: reprint,
        );
    }
    throw ArgumentError('no receipt for ${e.kind}');
  }
}
