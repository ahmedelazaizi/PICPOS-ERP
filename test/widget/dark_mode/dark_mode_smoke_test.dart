import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/core/theme/app_theme.dart';
import 'package:ural_erp/l10n/app_localizations.dart';
import 'package:ural_erp/data/providers/providers.dart';
import 'package:ural_erp/presentation/manufacturing_picpos/manufacturing_picpos_screen.dart';
import 'package:ural_erp/presentation/products_picpos/screens/products_picpos_screen.dart';
import 'package:ural_erp/presentation/screens/login_screen.dart';
import 'package:ural_erp/presentation/screens/settings_screen.dart';
import 'package:ural_erp/presentation/screens/widgets/sales_invoices/sales_invoice_form.dart';
import 'package:ural_erp/presentation/treasury/widgets/payment_voucher_dialog.dart';
import 'package:ural_erp/presentation/pos/screens/pos_main_screen.dart';

const _coveredScreens = <String>[
  'POS main screen',
  'sales invoice form',
  'treasury voucher dialog',
  'settings',
  'manufacturing PicPos screen',
  'PicPos products/data-table screen',
  'login',
];

final _darkTheme = AppTheme.darkTheme;

Widget _shell(Widget child, AppDatabase database) {
  return ProviderScope(
    overrides: [databaseProvider.overrideWithValue(database)],
    child: MaterialApp(
      locale: const Locale('ar', 'EG'),
      supportedLocales: const [Locale('ar', 'EG'), Locale('en', 'US')],
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: _darkTheme,
      themeMode: ThemeMode.dark,
      home: Directionality(textDirection: TextDirection.rtl, child: child),
    ),
  );
}

Future<List<String>> _pumpAndCheck(
  WidgetTester tester,
  AppDatabase database,
  String screenName,
  Widget child,
) async {
  tester.view.physicalSize = const Size(3840, 2160);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(_shell(child, database));
  await tester.pump(const Duration(milliseconds: 250));
  final violations = _contrastViolations(tester, screenName);
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 1));
  return violations;
}

double _contrast(Color first, Color second) {
  final a = first.computeLuminance();
  final b = second.computeLuminance();
  final high = a > b ? a : b;
  final low = a > b ? b : a;
  return (high + 0.05) / (low + 0.05);
}

Color _backgroundFor(Element element) {
  var background = Theme.of(element).scaffoldBackgroundColor;
  element.visitAncestorElements((ancestor) {
    final widget = ancestor.widget;
    final candidate = switch (widget) {
      Material(:final color) => color,
      Container(:final color) => color,
      DecoratedBox(:final decoration) => _decorationColor(decoration),
      ColoredBox(:final color) => color,
      _ => null,
    };
    if (candidate != null && candidate.a > 0) {
      background = candidate;
      return false;
    }
    return true;
  });
  return background;
}

Color? _decorationColor(Decoration decoration) {
  return decoration is BoxDecoration ? decoration.color : null;
}

List<String> _contrastViolations(WidgetTester tester, String screenName) {
  final violations = <String>[];
  for (final textFinder in find.byType(Text).evaluate()) {
    final text = textFinder.widget as Text;
    final ink = text.style?.color;
    if (ink == null) continue;
    // White/light foregrounds are intentionally allowed on brand/status and
    // paper-like surfaces by the structural guard. This runtime probe focuses
    // on the dark-ink regression that disappears against dark surfaces.
    if (ink.computeLuminance() > 0.1) continue;
    final background = _backgroundFor(textFinder);
    if (_contrast(ink, background) < 3.0) {
      violations.add('$screenName: "${text.data ?? ''}" contrast '
          '${_contrast(ink, background).toStringAsFixed(2)}');
    }
  }
  return violations;
}

Widget _salesInvoiceForm() {
  return Scaffold(
    body: SalesInvoiceForm(
      customers: const [],
      initialProducts: const [],
      categories: const [],
      warehouses: const [],
      costCenters: const [],
      systemTaxRate: 0.14,
      onSaveQuotation: ({
        required dialogContext,
        required existingId,
        required existingNumber,
        required customerId,
        required notes,
        required invoiceItems,
        required subtotal,
        required discount,
        required tax,
        required total,
      }) async {},
      onSaveInvoice: ({
        required dialogContext,
        required customerId,
        required paymentMethod,
        required notes,
        required invoiceItems,
        required subtotal,
        required discount,
        required tax,
        required total,
        required paid,
        required isReturnMode,
        required printAfterSave,
        required taxEnabled,
        convertingQuotationId,
        required products,
        warehouseId,
        costCenterId,
      }) async {},
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('dark mode smoke covers representative screens', (tester) async {
    final database = AppDatabase.forTesting();
    final violations = <String>[];
    violations.addAll(await _pumpAndCheck(
      tester,
      database,
      'POS main screen',
      const PosScreenV2(),
    ));
    violations.addAll(await _pumpAndCheck(
      tester,
      database,
      'sales invoice form',
      _salesInvoiceForm(),
    ));
    violations.addAll(await _pumpAndCheck(
      tester,
      database,
      'treasury voucher dialog',
      const Scaffold(body: PaymentVoucherDialog()),
    ));
    violations.addAll(await _pumpAndCheck(
      tester,
      database,
      'settings',
      const SettingsScreen(),
    ));
    violations.addAll(await _pumpAndCheck(
      tester,
      database,
      'manufacturing PicPos screen',
      const ManufacturingPicposScreen(),
    ));
    violations.addAll(await _pumpAndCheck(
      tester,
      database,
      'PicPos products/data-table screen',
      const ProductsPicposScreen(),
    ));
    violations.addAll(await _pumpAndCheck(
      tester,
      database,
      'login',
      const LoginScreen(),
    ));

    expect(
      violations,
      isEmpty,
      reason: 'WCAG contrast threshold is 3.0. Covered screens: '
          '${_coveredScreens.join(', ')}.\n${violations.join('\n')}',
    );
  });
}
