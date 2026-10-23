import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/providers/providers.dart' show Category;
import 'package:picpos_erp/presentation/products_picpos/widgets/picpos_category_picker.dart';

/// Task 2 tests the ONE genuinely-new pure widget in the products PicPos fork:
/// the category picker. Everything else the screen shows (the products table,
/// the bulk bar, the shell chrome) is either reused UralCash code or covered by
/// Task 1's picpos_shell tests.
///
/// A full-screen render test is deliberately NOT used: `ProductsPicposScreen`
/// mounts the real products controller + drift-backed providers + platform
/// channels (path_provider, autoBackup), which hang/loop under flutter_test
/// without wholesale mocking — matching this repo's convention of testing
/// isolated widgets, never whole screens. The screen's real mount is verified
/// by `build_picpos.bat` + the manual run in Task 5.
void main() {
  Future<(bool, Category?)?> openPicker(
    WidgetTester tester, {
    required List<Category> categories,
    int? selectedId,
  }) async {
    (bool, Category?)? result;
    var opened = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                opened = true;
                result = await PicPosCategoryPicker.show(
                  context,
                  categories: categories,
                  selectedId: selectedId,
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(opened, isTrue);
    return result;
  }

  testWidgets('يعرض حوار التصنيفات وخيار «كل التصنيفات»', (tester) async {
    await openPicker(tester, categories: const []);
    expect(find.text('اختر التصنيف'), findsOneWidget);
    expect(find.text('كل التصنيفات'), findsOneWidget);
  });

  testWidgets('اختيار «كل التصنيفات» يرجّع (true, null)', (tester) async {
    late (bool, Category?)? result;
    var captured = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                result = await PicPosCategoryPicker.show(
                  context,
                  categories: const [],
                  selectedId: null,
                );
                captured = true;
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('كل التصنيفات'));
    await tester.pumpAndSettle();

    expect(captured, isTrue);
    expect(result, isNotNull);
    expect(result!.$1, isTrue);
    expect(result!.$2, isNull);
  });

  testWidgets('إلغاء الحوار يرجّع null', (tester) async {
    late (bool, Category?)? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                result = await PicPosCategoryPicker.show(
                  context,
                  categories: const [],
                  selectedId: null,
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('إلغاء'));
    await tester.pumpAndSettle();

    expect(result, isNull);
  });
}
