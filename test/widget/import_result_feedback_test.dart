import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/core/widgets/app_toast.dart';
import 'package:picpos_erp/data/services/excel_import_result.dart';
import 'package:picpos_erp/presentation/widgets/dialogs/import_result_feedback.dart';

ImportResult _result({int errors = 60, bool success = true}) => ImportResult(
      success: success,
      message: 'تمت العملية: 0 جديد، 1 تحديث، $errors أخطاء',
      updated: 1,
      errors: errors,
      rowErrors: [
        for (var i = 0; i < errors; i++)
          ImportRowError(
              row: i + 2, code: 'P$i', name: 'صنف $i', reason: 'سبب $i'),
      ],
    );

void main() {
  test('toast is never success-styled when errors > 0', () {
    expect(importToastType(_result()), ToastType.warning);
    expect(importToastType(_result(success: false)), ToastType.error);
    expect(importToastType(ImportResult(success: true, message: 'ok')),
        ToastType.success);
    expect(importToastType(ImportResult(success: false, message: 'x')),
        ToastType.error);
  });

  testWidgets('dialog lists the first 50 errors and copies all',
      (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    tester.view.physicalSize = const Size(1600, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (c) => TextButton(
            onPressed: () => showImportResultFeedback(c, _result()),
            child: const Text('go'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    expect(find.byType(ImportErrorsDialog), findsOneWidget);
    expect(find.textContaining('سبب 0'), findsOneWidget);
    // ListView is lazy: scroll to the last allowed item, not beyond.
    await tester.scrollUntilVisible(
        find.byKey(const ValueKey('import_error_49')), 200);
    expect(find.byKey(const ValueKey('import_error_50')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('import_errors_copy')));
    await tester.pump();
    expect(copied, isNotNull);
    expect(copied!.split('\n'), hasLength(60)); // copy has ALL, not 50
    expect(copied, contains('الصف 2 · P0 · صنف 0: سبب 0'));
    await tester.pumpAndSettle(const Duration(seconds: 5));
  });
}
