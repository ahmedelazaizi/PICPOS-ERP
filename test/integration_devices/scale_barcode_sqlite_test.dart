// Integration review 2026-11-04: an embedded-weight / embedded-price label
// printed by a label scale (EAN-13, prefix + PLU + value + check digit) is read
// by the POS path the cashier actually uses — RepositoryBarcodeAdapter over the
// production repositories on a SQLite database, with the profile saved by the
// settings screen keys (ScaleBarcodeConfig.*Key).
import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/data/providers/providers.dart';
import 'package:picpos_erp/presentation/pos/services/scale_barcode_config.dart';
import 'package:picpos_erp/presentation/pos/services/scale_barcode_encoder.dart';
import 'package:picpos_erp/presentation/pos/services/scale_barcode_handler.dart';

void main() {
  late AppDatabase db;
  late ProviderContainer container;
  late ScaleBarcodeDataSource source;
  late int bananaId;

  setUp(() async {
    db = AppDatabase.forTesting();
    container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
    source = RepositoryBarcodeAdapter(container);
    bananaId = await db.insertProduct(
      ProductsCompanion.insert(
        code: 'BAN',
        name: 'موز',
        salePrice: const Value(12.5),
        scalePluNumber: const Value(1234),
      ),
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  Future<void> saveProfile(Map<String, String> settings) async {
    for (final e in settings.entries) {
      await db.setSetting(e.key, e.value);
    }
  }

  test('a weight label resolves the product by PLU and reads kilograms '
      '(prefix 21, 5-digit PLU, divider 1000)', () async {
    await saveProfile({ScaleBarcodeConfig.weightEnabledKey: 'true'});
    final label = ScaleBarcodeEncoder.encode(
      plu: '1234',
      value: 1.25,
      kind: ScaleBarcodeValueKind.weight,
    );
    expect(label, '2101234012505');

    // A wedge scanner appends CR/LF; the parser must ignore it.
    final r = await ScaleBarcodeHandler.tryParse(source, '$label\r\n');
    expect(r, isNotNull);
    expect(r!.product.id, bananaId);
    expect(r.quantity, closeTo(1.25, 1e-9));
  });

  test('a price label converts the printed amount into quantity using the '
      'product sale price (prefix 20, divider 100)', () async {
    await saveProfile({ScaleBarcodeConfig.priceEnabledKey: 'true'});
    final label = ScaleBarcodeEncoder.encode(
      plu: '1234',
      value: 25.00,
      kind: ScaleBarcodeValueKind.price,
    );
    final r = await ScaleBarcodeHandler.tryParse(source, label);
    expect(r!.product.id, bananaId);
    expect(r.quantity, closeTo(2.0, 1e-9)); // 25.00 / 12.5
  });

  test('a custom profile (prefix 27, 4-digit PLU, grams divider 1000) saved in '
      'settings is honoured', () async {
    await saveProfile({
      ScaleBarcodeConfig.weightEnabledKey: 'true',
      ScaleBarcodeConfig.weightPrefixKey: '27',
      ScaleBarcodeConfig.weightCodeLenKey: '4',
      ScaleBarcodeConfig.weightDividerKey: '1000',
    });
    final label = ScaleBarcodeEncoder.encode(
      plu: '1234',
      value: 0.75,
      kind: ScaleBarcodeValueKind.weight,
      prefix: '27',
      codeLength: 4,
    );
    final r = await ScaleBarcodeHandler.tryParse(source, label);
    expect(r!.product.id, bananaId);
    expect(r.quantity, closeTo(0.75, 1e-9));
  });

  test('labels that must NOT be read as scale labels fall through to normal '
      'lookup (null)', () async {
    await saveProfile({ScaleBarcodeConfig.weightEnabledKey: 'true'});
    final good = ScaleBarcodeEncoder.encode(
      plu: '1234',
      value: 1.25,
      kind: ScaleBarcodeValueKind.weight,
    );
    final badCheck =
        '${good.substring(0, 12)}${(int.parse(good[12]) + 1) % 10}';
    final unknownPlu = ScaleBarcodeEncoder.encode(
      plu: '9999',
      value: 1,
      kind: ScaleBarcodeValueKind.weight,
    );
    for (final code in [badCheck, unknownPlu, '6221234567890', '21012340123']) {
      expect(
        await ScaleBarcodeHandler.tryParse(source, code),
        isNull,
        reason: code,
      );
    }

    // Weight mode switched off: the same valid label is not a scale label.
    await saveProfile({ScaleBarcodeConfig.weightEnabledKey: 'false'});
    expect(await ScaleBarcodeHandler.tryParse(source, good), isNull);
  });

  test(
    'an install that only has the legacy keys (scale_barcode_prefix / '
    'scale_barcode_code_length) parses with its saved PLU length',
    () async {
      await saveProfile({
        'scale_barcode_prefix': '21',
        'scale_barcode_code_length': '4',
      });
      final cfg = await ScaleBarcodeHandler.readConfig(source);
      expect(cfg.weightEnabled, isTrue);
      expect(cfg.weightCodeLen, '4');
      final label = ScaleBarcodeEncoder.encode(
        plu: '1234',
        value: 1.5,
        kind: ScaleBarcodeValueKind.weight,
        codeLength: 4,
      );
      // Fixed INT-07: the parser uses the PLU length readConfig resolved.
      final r = await ScaleBarcodeHandler.tryParse(source, label);
      expect(r?.product.id, bananaId);
      expect(r!.quantity, closeTo(1.5, 1e-9));
    },
  );

  test('INT-07: a legacy price profile (scale_qty_prefix / '
      'scale_qty_code_length / scale_qty_divider) is parsed with its own '
      'PLU length and divider', () async {
    await saveProfile({
      'scale_qty_prefix': '20',
      'scale_qty_code_length': '4',
      'scale_qty_divider': '10',
    });
    final cfg = await ScaleBarcodeHandler.readConfig(source);
    expect(cfg.priceEnabled, isTrue);
    final label = ScaleBarcodeEncoder.encode(
      plu: '1234',
      value: 25.0,
      kind: ScaleBarcodeValueKind.price,
      codeLength: 4,
      divider: 10,
    );
    final r = await ScaleBarcodeHandler.tryParse(source, label);
    expect(r?.product.id, bananaId);
    expect(r!.quantity, closeTo(2.0, 1e-9)); // 25.0 / 12.5
  });
}
