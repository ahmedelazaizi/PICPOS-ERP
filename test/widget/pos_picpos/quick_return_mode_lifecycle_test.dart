import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/domain/models/returnable_line.dart';
import 'package:picpos_erp/presentation/pos_picpos/providers/pos_return_mode_provider.dart';
import 'package:picpos_erp/presentation/pos_picpos/screens/picpos_pos_screen.dart'
    as picpos;
import 'package:picpos_erp/presentation/pos_picpos/state/pos_return_mode.dart';

final _returnMode = PosReturnMode.fromLines(
  invoiceId: 12,
  lines: const [
    ReturnableLine(
      invoiceItemId: 1,
      productId: 2,
      productName: 'صنف تجريبي',
      soldQty: 1,
      alreadyReturnedQty: 0,
      unitPrice: 5,
      lineTotal: 5,
    ),
  ],
);

class _QuickReturnScreen extends ConsumerStatefulWidget {
  const _QuickReturnScreen();

  @override
  ConsumerState<_QuickReturnScreen> createState() => _QuickReturnScreenState();
}

class _QuickReturnScreenState extends ConsumerState<_QuickReturnScreen> {
  late final void Function() _clearMode;
  @override
  void initState() {
    super.initState();
    _clearMode = picpos.createQuickReturnModeExitReset(ref);
  }

  @override
  void dispose() {
    _clearMode();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ElevatedButton(
    onPressed: () =>
        ref.read(posReturnModeProvider.notifier).state = _returnMode,
    child: const Text('دخول المرتجع'),
  );
}

class _NavigationHarness extends ConsumerStatefulWidget {
  const _NavigationHarness();

  @override
  ConsumerState<_NavigationHarness> createState() => _NavigationHarnessState();
}

class _NavigationHarnessState extends ConsumerState<_NavigationHarness> {
  bool _screenVisible = true;

  @override
  Widget build(BuildContext context) {
    final mode = ref.watch(posReturnModeProvider);
    return Column(
      children: [
        Text(mode == null ? 'بيع عادي' : 'مرتجع نشط'),
        if (_screenVisible) const _QuickReturnScreen(),
        ElevatedButton(
          onPressed: () => setState(() => _screenVisible = !_screenVisible),
          child: Text(_screenVisible ? 'مغادرة' : 'عودة'),
        ),
      ],
    );
  }
}

void main() {
  testWidgets('مغادرة شاشة المرتجع تصفّر الوضع قبل العودة', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: const MaterialApp(home: Scaffold(body: _NavigationHarness())),
      ),
    );
    await tester.tap(find.text('دخول المرتجع'));
    await tester.pump();
    expect(find.text('مرتجع نشط'), findsOneWidget);

    await tester.tap(find.text('مغادرة'));
    await tester.pump();
    await tester.pump();
    expect(find.text('بيع عادي'), findsOneWidget);

    await tester.tap(find.text('عودة'));
    await tester.pump();
    expect(find.text('بيع عادي'), findsOneWidget);
    expect(find.text('مرتجع نشط'), findsNothing);
  });

  test('شاشة البيع تستدعي تصفير المرتجع من dispose', () {
    final source = File(
      'lib/presentation/pos_picpos/screens/picpos_pos_screen.dart',
    ).readAsStringSync();
    expect(source, contains('createQuickReturnModeExitReset('));
    expect(source, contains('_clearOnExit();'));
  });
}
