// معالجات القراءة العامة المستخرجة من `api_handler.dart`: القائمة الرقمية،
// شاشة العميل (CFD) والعروض. السلوك مطابق لما كان داخل ApiHandler حرفيًا.
import 'dart:convert';

import 'package:shelf/shelf.dart';

import '../../data/database/database.dart';
import '../cfd_service.dart';
import 'api_html_templates.dart';
import 'web_security_headers.dart';

class ApiDisplayHandler {
  ApiDisplayHandler(this._db);

  final AppDatabase _db;

  Response _json(Map<String, dynamic> data) => Response(
        200,
        body: json.encode(data),
        headers: {'Content-Type': 'application/json'},
      );

  Response _error(String message) => Response(
        500,
        body: json.encode({'error': message}),
        headers: {'Content-Type': 'application/json'},
      );

  // ── Digital Menu ──

  Future<Response> getMenuData(Request request) async {
    try {
      final categories = await _db.select(_db.categories).get();
      final products = _db.select(_db.products)
        ..where((u) => u.isActive.equals(true));
      final productsList = await products.get();

      return _json({
        'categories': categories
            .map((c) => {'id': c.id, 'name': c.name, 'icon': c.iconName})
            .toList(),
        'products': productsList
            .map(
              (p) => {
                'id': p.id,
                'name': p.name,
                'price': p.salePrice,
                'categoryId': p.categoryId,
                'description': p.description,
              },
            )
            .toList(),
      });
    } catch (e) {
      return _error('Failed to fetch menu data: $e');
    }
  }

  Future<Response> getMenuDisplay(Request request) async {
    return Response.ok(
      menuHtmlTemplate,
      headers: {
        'Content-Type': 'text/html; charset=utf-8',
        ...WebSecurityHeaders.forInlinePage(),
      },
    );
  }

  // ── CFD Display & Stream ──

  Future<Response> cfdStream(Request request) async {
    final stream = CfdService.instance.connect();
    return Response.ok(
      stream,
      headers: {
        'Content-Type': 'text/event-stream',
        'Cache-Control': 'no-cache',
        'Connection': 'keep-alive',
      },
    );
  }

  Future<Response> getCfdDisplay(Request request) async {
    return Response.ok(
      cfdHtmlTemplate,
      headers: {
        'Content-Type': 'text/html; charset=utf-8',
        ...WebSecurityHeaders.forInlinePage(),
      },
    );
  }

  // ── Offers (GET) — serves all offers + items for client sync ──

  Future<Response> getOffers(Request request) async {
    try {
      final offers = await _db.select(_db.offers).get();
      final items = await _db.select(_db.offerItems).get();

      final offersJson = offers.map((o) => <String, dynamic>{
        'id': o.id,
        'name': o.name,
        'barcode': o.barcode,
        'offerPrice': o.offerPrice,
        'startDate': o.startDate != null
            ? o.startDate!.millisecondsSinceEpoch ~/ 1000
            : null,
        'endDate': o.endDate != null
            ? o.endDate!.millisecondsSinceEpoch ~/ 1000
            : null,
        'isActive': o.isActive,
        'offerType': o.offerType,
        'discountValue': o.discountValue,
        'buyQuantity': o.buyQuantity,
        'getQuantity': o.getQuantity,
        'minQuantity': o.minQuantity,
        'maxUses': o.maxUses,
        'currentUses': o.currentUses,
        'timeStart': o.timeStart,
        'timeEnd': o.timeEnd,
        'categoryId': o.categoryId,
      }).toList();

      final itemsJson = items.map((i) => <String, dynamic>{
        'id': i.id,
        'offerId': i.offerId,
        'productId': i.productId,
        'quantity': i.quantity,
      }).toList();

      return _json({
        'offers': offersJson,
        'offerItems': itemsJson,
        'count': offersJson.length,
      });
    } catch (e) {
      return _error('Failed to fetch offers: $e');
    }
  }
}
