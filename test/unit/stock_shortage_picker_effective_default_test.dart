// B2 — fresh-install inconsistency: the stock-shortage picker showed
// "allow negative" when nothing was saved, while a sale resolved through
// `resolveForSaleWith` falls back to `enable_negative_sales` (false on a new
// install) and BLOCKS. The picker must display the value the sale uses.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/services/stock_shortage_policy_service.dart';

Future<String?> Function(String) _settings(Map<String, String> values) =>
    (key) async => values[key];

void main() {
  setUp(StockShortagePolicyService.resetCacheForTest);
  tearDown(StockShortagePolicyService.resetCacheForTest);

  Future<void> expectPickerMatchesSale(
    Map<String, String> values,
    StockShortagePolicy expected,
  ) async {
    final get = _settings(values);
    final shown = await StockShortagePolicyService.effectiveGlobalWith(get);
    StockShortagePolicyService.resetCacheForTest();
    final sale = await StockShortagePolicyService.resolveForSaleWith(get: get);
    expect(shown, expected, reason: 'picker value for $values');
    expect(shown, sale, reason: 'picker must equal the sale policy');
  }

  test('fresh install (nothing saved) shows block — what sales enforce',
      () async {
    await expectPickerMatchesSale(const {}, StockShortagePolicy.block);
  });

  test('legacy enable_negative_sales=false shows block', () async {
    await expectPickerMatchesSale(
      const {'enable_negative_sales': 'false'},
      StockShortagePolicy.block,
    );
  });

  test('legacy enable_negative_sales=true shows allow negative', () async {
    await expectPickerMatchesSale(
      const {'enable_negative_sales': 'true'},
      StockShortagePolicy.allowNegative,
    );
  });

  test('a saved global policy wins over the legacy flag', () async {
    await expectPickerMatchesSale(
      const {
        'stock_shortage_policy': 'clamp_to_zero',
        'enable_negative_sales': 'false',
      },
      StockShortagePolicy.clampToZero,
    );
  });

  test('only a per-branch tier saved → global tier is the service default',
      () async {
    final get = _settings(const {
      'stock_shortage_policy_per_branch': '{"7":"block"}',
      'enable_negative_sales': 'false',
    });
    expect(
      await StockShortagePolicyService.effectiveGlobalWith(get),
      StockShortagePolicyService.defaultPolicy,
    );
    // A sale with no branch override resolves to the same global tier.
    expect(
      await StockShortagePolicyService.resolveForSaleWith(get: get),
      StockShortagePolicyService.defaultPolicy,
    );
  });

  test('both global pickers load through effectiveGlobalWith', () {
    for (final path in const [
      'lib/presentation/settings_picpos/screens/general_settings_widgets_picpos.dart',
      'lib/presentation/screens/settings/general_settings_widgets.dart',
    ]) {
      final src = File(path).readAsStringSync();
      expect(src.contains('StockShortagePolicyService.effectiveGlobalWith('),
          isTrue,
          reason: '$path must display the effective sale policy');
      expect(src.contains("getSetting('stock_shortage_policy')"), isFalse,
          reason: '$path must not read the raw key and default to '
              'allowNegative');
    }
  });
}
