import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/providers/providers.dart';
import 'package:picpos_erp/domain/repositories/settings_repository.dart';
import 'package:picpos_erp/presentation/pos/services/scale_barcode_config.dart';
import 'package:picpos_erp/presentation/pos/services/scale_barcode_encoder.dart';
import 'package:picpos_erp/presentation/widgets/settings/scale_barcode_settings_panel.dart';

class _FakeSettings implements ISettingsRepository {
  _FakeSettings(this.values);
  final Map<String, String> values;

  @override
  Future<String?> getSetting(String key) async => values[key];

  @override
  Future<void> saveSetting(String key, String value) async =>
      values[key] = value;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _pump(WidgetTester tester, _FakeSettings repo, {bool dark = false}) async {
  tester.view.physicalSize = const Size(1400, 2000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [settingsRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(
        theme: dark ? ThemeData.dark() : ThemeData.light(),
        home: const Scaffold(
          body: SingleChildScrollView(child: ScaleBarcodeSettingsPanel()),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

String _code(WidgetTester tester, String id) => tester
    .widget<Text>(find.byKey(Key('scale_cfg_preview_${id}_code')))
    .textSpan!
    .toPlainText()
    .replaceAll(' ', '');

void main() {
  testWidgets('disabled config still shows every field, preview and status', (
    tester,
  ) async {
    final repo = _FakeSettings({});
    await _pump(tester, repo);

    expect(find.text('غير مفعّل'), findsOneWidget);
    for (final k in [
      'scale_cfg_weight_enabled',
      'scale_cfg_weight_prefix',
      'scale_cfg_weight_code_len',
      'scale_cfg_weight_divider',
      'scale_cfg_weight_value_digits',
      'scale_cfg_fallback_prefix',
      'scale_cfg_price_enabled',
      'scale_cfg_price_prefix',
      'scale_cfg_price_code_len',
      'scale_cfg_price_divider',
    ]) {
      expect(find.byKey(Key(k)), findsOneWidget, reason: k);
    }
    expect(
      _code(tester, 'weight'),
      ScaleBarcodeEncoder.encode(
        plu: '12345',
        value: 1.234,
        kind: ScaleBarcodeValueKind.weight,
      ),
    );
    expect(
      _code(tester, 'price'),
      ScaleBarcodeEncoder.encode(
        plu: '12345',
        value: 12.34,
        kind: ScaleBarcodeValueKind.price,
      ),
    );
  });

  testWidgets('enable + edit prefix updates preview live and saves all keys', (
    tester,
  ) async {
    final repo = _FakeSettings({});
    await _pump(tester, repo);

    await tester.tap(find.byKey(const Key('scale_cfg_weight_enabled')));
    await tester.enterText(
      find.byKey(const Key('scale_cfg_weight_prefix')),
      '23',
    );
    await tester.pump();
    expect(find.text('ميزان الوزن مفعّل'), findsOneWidget);
    final expected = ScaleBarcodeEncoder.encode(
      plu: '12345',
      value: 1.234,
      kind: ScaleBarcodeValueKind.weight,
      prefix: '23',
    );
    expect(_code(tester, 'weight'), expected);

    await tester.tap(find.byKey(const Key('scale_cfg_save')));
    await tester.pumpAndSettle();
    expect(repo.values['scale_weight_enabled'], 'true');
    expect(repo.values['scale_weight_prefix'], '23');
    expect(repo.values['scale_price_prefix'], '20');
    expect(repo.values.keys, containsAll(ScaleBarcodeConfig.canonicalKeys));
    // ما حُفظ يعيد بناء نفس الباركود (قراءة = كتابة).
    expect(
      ScaleBarcodeConfig.fromSettings(repo.values)
          .sample(ScaleBarcodeValueKind.weight)
          .barcode,
      expected,
    );

    // إعادة الفتح تقرأ المحفوظ.
    await tester.pumpWidget(const SizedBox());
    await _pump(tester, repo);
    expect(find.text('ميزان الوزن مفعّل'), findsOneWidget);
    expect(_code(tester, 'weight'), expected);
  });

  testWidgets('conflicting prefixes / overflowing lengths block saving', (
    tester,
  ) async {
    final repo = _FakeSettings({'scale_weight_enabled': 'true'});
    await _pump(tester, repo, dark: true);

    await tester.enterText(
      find.byKey(const Key('scale_cfg_price_prefix')),
      '21',
    );
    await tester.pump();
    expect(find.byKey(const Key('scale_cfg_issues')), findsOneWidget);
    expect(find.textContaining('تعارض'), findsOneWidget);
    expect(
      tester
          .widget<ElevatedButton>(find.byKey(const Key('scale_cfg_save')))
          .onPressed,
      isNull,
    );
    expect(find.byKey(const Key('scale_cfg_preview_weight_error')), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('scale_cfg_price_prefix')),
      '20',
    );
    await tester.enterText(
      find.byKey(const Key('scale_cfg_weight_code_len')),
      '10',
    );
    await tester.pump();
    expect(find.textContaining('خانات PLU للوزن لا تتسع'), findsOneWidget);
    expect(
      tester
          .widget<ElevatedButton>(find.byKey(const Key('scale_cfg_save')))
          .onPressed,
      isNull,
    );

    // أرقام فقط: الحرف لا يدخل الحقل.
    await tester.enterText(
      find.byKey(const Key('scale_cfg_weight_code_len')),
      '5x',
    );
    await tester.pump();
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('scale_cfg_weight_code_len')))
          .controller!
          .text,
      '5',
    );
    expect(find.byKey(const Key('scale_cfg_issues')), findsNothing);
    expect(repo.values.containsKey('scale_price_prefix'), isFalse);
  });
}
