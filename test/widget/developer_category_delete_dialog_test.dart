// بند 10 — حوار تأكيد حذف التصنيف في أدوات المطوّر.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/presentation/screens/developer_categories/category_delete_reasons.dart';
import 'package:picpos_erp/presentation/screens/developer_categories/developer_categories_section.dart';

Category _cat({String name = 'حلويات', bool locked = false, bool sys = false}) =>
    Category(
      id: 7,
      name: name,
      color: '#2563EB',
      sortOrder: 0,
      isActive: true,
      isLocked: locked,
      isExcluded: false,
      showInPos: true,
      isGlobal: true,
      isSystemDefault: sys,
      globalId: 'gid-7',
      rowVersion: 0,
    );

Future<bool?> _open(WidgetTester t, CategoryDeleteAnalysis a) async {
  bool? result;
  await t.pumpWidget(MaterialApp(
    home: Builder(
      builder: (ctx) => TextButton(
        onPressed: () async => result = await showDialog<bool>(
          context: ctx,
          builder: (_) => CategoryDeleteDialog(analysis: a),
        ),
        child: const Text('open'),
      ),
    ),
  ));
  await t.tap(find.text('open'));
  await t.pumpAndSettle();
  return result;
}

void main() {
  testWidgets('تصنيف فارغ: الزر معطّل حتى كتابة الاسم ثم يُرجع true',
      (t) async {
    bool? result;
    await t.pumpWidget(MaterialApp(
      home: Builder(
        builder: (ctx) => TextButton(
          onPressed: () async => result = await showDialog<bool>(
            context: ctx,
            builder: (_) => CategoryDeleteDialog(
                analysis: CategoryDeleteAnalysis(category: _cat())),
          ),
          child: const Text('open'),
        ),
      ),
    ));
    await t.tap(find.text('open'));
    await t.pumpAndSettle();

    FilledButton btn() =>
        t.widget<FilledButton>(find.byKey(const ValueKey('dev-cat-confirm-btn')));
    expect(btn().onPressed, isNull);

    await t.enterText(find.byKey(const ValueKey('dev-cat-confirm-field')), 'خطأ');
    await t.pump();
    expect(btn().onPressed, isNull);

    await t.enterText(
        find.byKey(const ValueKey('dev-cat-confirm-field')), 'حلويات');
    await t.pump();
    expect(btn().onPressed, isNotNull);

    await t.tap(find.byKey(const ValueKey('dev-cat-confirm-btn')));
    await t.pumpAndSettle();
    expect(result, isTrue);
  });

  testWidgets('تصنيف به أصناف: تُعرض الأعداد ولا يوجد زر تأكيد', (t) async {
    await _open(
        t,
        CategoryDeleteAnalysis(
          category: _cat(),
          activeProducts: 3,
          inactiveProducts: 2,
        ));
    expect(find.byKey(const ValueKey('dev-cat-confirm-btn')), findsNothing);
    expect(find.byKey(const ValueKey('dev-cat-confirm-field')), findsNothing);
    expect(find.textContaining('5'), findsWidgets);
    expect(find.textContaining('3'), findsWidgets);
    expect(find.textContaining('2'), findsWidgets);
  });

  testWidgets('الافتراضي والمقفل والأبناء: أسباب المنع ظاهرة', (t) async {
    final a = CategoryDeleteAnalysis(
        category: _cat(name: 'عام', locked: true), activeChildren: 4);
    await _open(t, a);
    for (final b in a.strictBlocks) {
      expect(find.text('• ${categoryDeleteBlockText(b, a)}'), findsOneWidget);
    }
    expect(a.strictBlocks, {
      CategoryDeleteBlock.systemDefault,
      CategoryDeleteBlock.locked,
      CategoryDeleteBlock.hasChildren,
    });
    expect(find.byKey(const ValueKey('dev-cat-confirm-btn')), findsNothing);
  });
}
