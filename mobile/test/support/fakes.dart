import 'package:picpos_van/data/cloud_api.dart';
import 'package:picpos_van/data/local_store.dart';
import 'package:picpos_van/state/app_controller.dart';

/// Bootstrap payload in the cloud contract shape (server/README.md).
Map<String, dynamic> bootstrapFixture() => {
      'serverTime': 1000,
      'company': {'name': 'PicPos Demo', 'defaultTaxRate': 16.0},
      'employee': {'globalId': 'rep-1', 'name': 'مندوب ١'},
      'customers': [
        {'globalId': 'c2', 'name': 'سوبرماركت النور', 'balance': 0.0, 'creditLimit': 0.0, 'sequence': 2},
        {'globalId': 'c1', 'name': 'بقالة الأمل', 'balance': 90.0, 'creditLimit': 100.0, 'sequence': 1},
      ],
      'customerScope': ['c1', 'c2'],
      'products': [
        {'globalId': 'p1', 'name': 'مياه ٦ لتر', 'barcode': '6251234567890', 'salePrice': 2.5, 'taxRate': 16.0, 'taxExempt': false},
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
      'leases': [
        {'globalId': 'l1', 'docType': 'sales_invoice', 'prefix': 'VS-', 'rangeFrom': 100000, 'rangeTo': 100499,
         'nextNumber': 100000, 'status': 'active'},
      ],
    };

class FakeCloudApi implements CloudApi {
  final List<List<Map<String, Object?>>> pushed = [];
  Map<String, dynamic> pullPayload = {'serverTime': 2000};
  int bootstraps = 0;

  @override
  Future<({String deviceToken, String employeeGlobalId})> pair(String baseUrl, String code, String deviceId, String deviceName) async {
    if (code != 'ABCDEFGH') throw CloudApiException(401, 'invalid_code');
    return (deviceToken: 'tok', employeeGlobalId: 'rep-1');
  }

  @override
  Future<String> login(DeviceCredentials c, String pin) async {
    if (pin != '1234') throw CloudApiException(401, 'invalid_pin');
    return 'session';
  }

  @override
  Future<Map<String, dynamic>> bootstrap(DeviceCredentials c, String session) async {
    bootstraps++;
    return bootstrapFixture();
  }

  @override
  Future<Map<String, dynamic>> pull(DeviceCredentials c, String session, int since) async => pullPayload;

  @override
  Future<List<Map<String, dynamic>>> push(DeviceCredentials c, String session, List<Map<String, Object?>> documents) async {
    pushed.add(documents);
    return [
      for (final d in documents)
        d['customerGlobalId'] == 'reject-me'
            ? {'globalId': d['globalId'], 'status': 'rejected', 'code': 'customer_not_on_route'}
            : {'globalId': d['globalId'], 'status': 'accepted'},
    ];
  }
}

/// A logged-in controller with the bootstrap fixture applied.
Future<(AppController, FakeCloudApi)> readyController() async {
  final api = FakeCloudApi();
  final c = AppController(store: MemoryLocalStore(), api: api, clock: () => DateTime(2026, 5, 1, 10));
  await c.init();
  await c.pair('http://test', 'ABCDEFGH');
  await c.login('1234');
  return (c, api);
}
