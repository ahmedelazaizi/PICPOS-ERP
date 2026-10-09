import 'package:picpos_van/data/cloud_api.dart';
import 'package:picpos_van/data/local_store.dart';
import 'package:picpos_van/state/app_controller.dart';

/// Bootstrap payload in the cloud contract shape (server/README.md).
Map<String, dynamic> bootstrapFixture() => {
      'serverTime': 1000,
      'company': {'name': 'PicPos Demo', 'defaultTaxRate': 16.0, 'pricesIncludeTax': false, 'decimalPlaces': 2},
      'employee': {'globalId': 'rep-1', 'name': 'مندوب ١', 'canOverridePrice': false},
      'noSaleReasons': ['closed', 'owner_absent', 'has_stock', 'no_cash', 'refused', 'other'],
      'customers': [
        {'globalId': 'c2', 'name': 'سوبرماركت النور', 'balance': 0.0, 'creditLimit': 0.0, 'sequence': 2},
        {'globalId': 'c1', 'name': 'بقالة الأمل', 'balance': 90.0, 'creditLimit': 100.0, 'sequence': 1},
      ],
      'customerScope': ['c1', 'c2'],
      'products': [
        {'globalId': 'p1', 'name': 'مياه ٦ لتر', 'barcode': '6251234567890', 'salePrice': 2.5, 'wholesalePrice': 2.2,
         'taxRate': 16.0, 'taxExempt': false},
        {'globalId': 'p2', 'name': 'خبز', 'barcode': '6250000000017', 'salePrice': 1.0, 'taxRate': 0.0, 'taxExempt': true},
      ],
      'vanStock': [
        {'productGlobalId': 'p1', 'quantity': 5.0},
        {'productGlobalId': 'p2', 'quantity': 20.0},
      ],
      'voucherBooks': [
        {'globalId': 'b1', 'prefix': 'R-', 'label': 'دفتر قبض', 'rangeFrom': 1001, 'rangeTo': 1050, 'nextNumber': 1001,
         'status': 'active', 'usedNumbers': [1001], 'cancelledNumbers': [1002]},
      ],
      'voucherBookScope': ['b1'],
      'priceLists': [
        {'globalId': 'pl1', 'name': 'جملة صغيرة', 'isDefault': true, 'isActive': true, 'startDate': null, 'endDate': null,
         'order': 1, 'items': [
           {'globalId': 'pli1', 'productGlobalId': 'p2', 'price': 0.9, 'minQuantity': 10.0},
         ]},
      ],
      'priceListScope': ['pl1'],
      // c2 bought 4 water + 2 bread (13.60, paid 5.00); 1 water already
      // returned and offset against the unpaid part.
      'invoices': [
        {'globalId': 'inv1', 'number': 'VS-99', 'date': '2026-04-30T09:00:00.000Z', 'customerGlobalId': 'c2',
         'total': 13.6, 'paid': 5.0, 'returnArOffset': 2.9, 'returnedTotal': 2.9, 'lines': [
           {'productGlobalId': 'p1', 'quantity': 4.0, 'total': 11.6, 'tax': 1.6,
            'returnedQuantity': 1.0, 'returnedTotal': 2.9, 'returnedTax': 0.4},
           {'productGlobalId': 'p2', 'quantity': 2.0, 'total': 2.0, 'tax': 0.0,
            'returnedQuantity': 0.0, 'returnedTotal': 0.0, 'returnedTax': 0.0},
         ]},
      ],
      'leases': [
        {'globalId': 'l1', 'docType': 'sales_invoice', 'prefix': 'VS-', 'rangeFrom': 100000, 'rangeTo': 100499,
         'nextNumber': 100000, 'status': 'active'},
        {'globalId': 'l2', 'docType': 'sales_return', 'prefix': 'VR-', 'rangeFrom': 100000, 'rangeTo': 100499,
         'nextNumber': 100000, 'status': 'active'},
      ],
    };

class FakeCloudApi implements CloudApi {
  final List<List<Map<String, Object?>>> pushed = [];
  Map<String, dynamic> pullPayload = {'serverTime': 2000};
  int bootstraps = 0;
  int rotations = 0;
  String token = 'tok';

  /// Next calls fail with this (e.g. `device_revoked`), or a network error
  /// when [offline].
  String? failWith;
  bool offline = false;

  /// Accept the push on the server but "lose" the response.
  bool dropPushResponse = false;
  final Set<String> serverDocs = {};

  void _gate() {
    if (offline) throw Exception('SocketException: network unreachable');
    if (failWith != null) throw CloudApiException(401, failWith!);
  }

  @override
  Future<({String deviceToken, String employeeGlobalId})> pair(String baseUrl, String code, String deviceId, String deviceName) async {
    _gate();
    if (code != 'ABCDEFGH') throw CloudApiException(401, 'invalid_code');
    return (deviceToken: token, employeeGlobalId: 'rep-1');
  }

  @override
  Future<String> login(DeviceCredentials c, String pin) async {
    _gate();
    if (pin != '1234') throw CloudApiException(401, 'invalid_pin');
    return 'session';
  }

  @override
  Future<String> rotateToken(DeviceCredentials c) async {
    _gate();
    rotations++;
    token = 'tok-$rotations';
    return token;
  }

  @override
  Future<Map<String, dynamic>> bootstrap(DeviceCredentials c, String session) async {
    _gate();
    bootstraps++;
    return bootstrapFixture();
  }

  @override
  Future<Map<String, dynamic>> pull(DeviceCredentials c, String session, int since) async {
    _gate();
    return {
      ...pullPayload,
      'documents': [
        for (final g in serverDocs) {'globalId': g, 'kind': 'x', 'status': 'accepted'},
      ],
    };
  }

  @override
  Future<List<Map<String, dynamic>>> push(DeviceCredentials c, String session, List<Map<String, Object?>> documents) async {
    _gate();
    pushed.add(documents);
    final results = [
      for (final d in documents)
        d['customerGlobalId'] == 'reject-me'
            ? {'globalId': d['globalId'], 'status': 'rejected', 'code': 'customer_not_on_route'}
            : {'globalId': d['globalId'], 'status': serverDocs.add(d['globalId'] as String) ? 'accepted' : 'duplicate'},
    ];
    if (dropPushResponse) throw Exception('connection reset after push');
    return results;
  }
}

/// A logged-in controller with the bootstrap fixture applied.
Future<(AppController, FakeCloudApi)> readyController({DateTime Function()? clock}) async {
  final api = FakeCloudApi();
  final c = AppController(store: MemoryLocalStore(), api: api, clock: clock ?? () => DateTime(2026, 5, 1, 10));
  await c.init();
  await c.pair('http://test', 'ABCDEFGH');
  await c.login('1234');
  return (c, api);
}
