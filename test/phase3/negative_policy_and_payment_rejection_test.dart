import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/services/offline_sync_worker.dart';
import 'package:picpos_erp/services/stock_shortage_policy_service.dart';

void main() {
  setUp(StockShortagePolicyService.resetCacheForTest);
  tearDown(StockShortagePolicyService.resetCacheForTest);

  test('sale policy permits global allow_negative despite legacy false', () async {
    final values = <String, String?>{
      'stock_shortage_policy': 'allow_negative',
      'enable_negative_sales': 'false',
    };
    final policy = await StockShortagePolicyService.resolveForSaleWith(
      get: (key) async => values[key],
    );
    expect(policy, StockShortagePolicy.allowNegative);
  });

  test('terminal then branch override global sale policy', () async {
    final values = <String, String?>{
      'stock_shortage_policy': 'allow_negative',
      'stock_shortage_policy_per_branch': '{"7":"block"}',
      'stock_shortage_policy_per_terminal': '{"9":"clamp_to_zero"}',
      'enable_negative_sales': 'false',
    };
    Future<String?> get(String key) async => values[key];
    expect(
      await StockShortagePolicyService.resolveForSaleWith(
        get: get, terminalId: 9, branchId: 7,
      ),
      StockShortagePolicy.clampToZero,
    );
    StockShortagePolicyService.resetCacheForTest();
    expect(
      await StockShortagePolicyService.resolveForSaleWith(
        get: get, branchId: 7,
      ),
      StockShortagePolicy.block,
    );
  });

  test('legacy setting applies only when no policy tier is configured', () async {
    final legacy = <String, String?>{'enable_negative_sales': 'true'};
    expect(
      await StockShortagePolicyService.resolveForSaleWith(
        get: (key) async => legacy[key],
      ),
      StockShortagePolicy.allowNegative,
    );
    StockShortagePolicyService.resetCacheForTest();
    legacy['stock_shortage_policy'] = 'block';
    expect(
      await StockShortagePolicyService.resolveForSaleWith(
        get: (key) async => legacy[key],
      ),
      StockShortagePolicy.block,
    );
  });

  test('payment rejection codes are permanent offline errors', () {
    expect(isPermanentSalesRejection('422 PAYMENT_EXCEEDS_REMAINING'), isTrue);
    expect(isPermanentSalesRejection('422 PAYMENT_NOT_POSITIVE'), isTrue);
    expect(isPermanentSalesRejection('500 Internal Server Error'), isFalse);
  });
}
