// بطاقةُ الطاولة: القسم (A.6) + الحالة لوناً وأيقونةً ونصّاً + التمييز بلا
// إخفاء (A.7).
//
// الشاشةُ نفسُها (`TablesPicposScreen`) لا تُضخّ في الاختبارات (تحتاج قاعدةً
// حقيقيّة)، فالتركيبُ هنا يحاكي ما تفعله: عمودُ الحالات الحقيقيّ + `TableCard`
// الحقيقيّ + `TablesGridModel` الذي تستعمله الشاشةُ.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:picpos_erp/core/theme/table_status_palette.dart';
import 'package:picpos_erp/data/providers/providers.dart';
import 'package:picpos_erp/domain/models/table_status.dart';
import 'package:picpos_erp/domain/repositories/restaurant_repository.dart';
import 'package:picpos_erp/presentation/screens/tables/providers/tables_state_provider.dart';
import 'package:picpos_erp/presentation/screens/tables/widgets/table_card.dart';
import 'package:picpos_erp/presentation/tables_picpos/logic/tables_grid_model.dart';
import 'package:picpos_erp/presentation/tables_picpos/widgets/tables_status_rail.dart';

final _now = DateTime(2026, 10, 18);

RestaurantTable _table(int id, String name, String status,
        {int sectionId = 1, int capacity = 4}) =>
    RestaurantTable(
      id: id,
      sectionId: sectionId,
      name: name,
      capacity: capacity,
      status: status,
      x: 0,
      y: 0,
      shape: 'square',
      lastStatusAt: _now,
      isActive: true,
      createdAt: _now,
      rowVersion: 0,
      rotation: 0,
    );

class _Repo implements IRestaurantRepository {
  @override
  Future<TableOrder?> getActiveOrderForTable(int tableId) async => null;
  @override
  dynamic noSuchMethod(Invocation i) => null;
}

final _tables = [
  _table(1, 'T1', TableStatus.available, sectionId: 1),
  _table(2, 'T2', TableStatus.occupied, sectionId: 2),
  _table(3, 'T3', TableStatus.reserved, sectionId: 1),
  _table(4, 'T4', TableStatus.paid, sectionId: 2),
  _table(5, 'T5', TableStatus.outOfService, sectionId: 1),
  _table(6, 'T6', TableStatus.available, sectionId: 2),
];

const _sections = {1: 'الصالة', 2: 'التراس'};

/// يحاكي الشاشة: عمودُ الحالات + شبكةُ بطاقات تقرأ `statusFilter`.
class _Harness extends ConsumerWidget {
  const _Harness();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ui = ref.watch(tablesUIProvider);
    final filter = ui.statusFilter;
    final shown = TablesGridModel.visibleTables(_tables, filter);
    return Row(
      children: [
        SizedBox(
          width: 220,
          child: SingleChildScrollView(
            child: TablesStatusRail(
              counts: countByStatus([for (final t in _tables) t.status]),
              selected: filter == 'all' ? null : filter,
              onSelect: (s) =>
                  ref.read(tablesUIProvider.notifier).setStatusFilter(s ?? 'all'),
            ),
          ),
        ),
        Expanded(
          child: GridView.count(
            crossAxisCount: 3,
            childAspectRatio: 1,
            children: [
              for (final t in shown)
                TableCard(
                  table: t,
                  restaurantRepo: _Repo(),
                  onInteraction: (_) {},
                  sectionName: _sections[t.sectionId],
                  dimmed: TablesGridModel.isDimmed(t.status, filter),
                  highlighted: TablesGridModel.isHighlighted(t.status, filter),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

Future<void> _pump(WidgetTester tester, {Brightness? brightness}) async {
  tester.view.physicalSize = const Size(1400, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        theme: ThemeData(brightness: brightness ?? Brightness.light),
        home: const Scaffold(body: _Harness()),
      ),
    ),
  );
  await tester.pump();
}

double _opacityOfCard(WidgetTester tester, String tableName) {
  final card = find.ancestor(
    of: find.text(tableName),
    matching: find.byType(TableCard),
  );
  return tester
      .widget<AnimatedOpacity>(find
          .descendant(of: card, matching: find.byType(AnimatedOpacity))
          .first)
      .opacity;
}

void main() {
  testWidgets('A.6 — كلُّ بطاقةٍ تعرض اسمَ قسمها', (tester) async {
    await _pump(tester);
    for (final t in _tables) {
      final chip = find.byKey(Key('table_card_section_${t.id}'));
      expect(chip, findsOneWidget, reason: 'لا شريحةَ قسمٍ على ${t.name}');
      expect(
        find.descendant(of: chip, matching: find.text(_sections[t.sectionId]!)),
        findsOneWidget,
      );
    }
  });

  testWidgets('بلا sectionName لا شريحة (التوافق مع الشاشة القديمة)',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 200,
              height: 200,
              child: TableCard(
                table: _tables.first,
                restaurantRepo: _Repo(),
                onInteraction: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.byKey(const Key('table_card_section_1')), findsNothing);
  });

  testWidgets('A.7 — الحالةُ نصٌّ + أيقونةٌ + لونٌ على كلّ بطاقة', (tester) async {
    await _pump(tester);
    const expected = {
      'T1': ('متاحة', PhosphorIconsBold.checkCircle, 'available'),
      'T2': ('مشغولة', PhosphorIconsBold.users, 'occupied'),
      'T3': ('محجوزة', PhosphorIconsBold.calendarCheck, 'reserved'),
      'T4': ('مدفوعة', PhosphorIconsBold.currencyCircleDollar, 'paid'),
      'T5': ('خارج الخدمة', PhosphorIconsBold.prohibit, 'out_of_service'),
    };
    for (final e in expected.entries) {
      final card = find.ancestor(
        of: find.text(e.key),
        matching: find.byType(TableCard),
      );
      final (label, icon, status) = e.value;
      expect(find.descendant(of: card, matching: find.text(label)),
          findsOneWidget, reason: 'نصُّ الحالة غائبٌ عن ${e.key}');
      expect(find.descendant(of: card, matching: find.byIcon(icon)),
          findsWidgets, reason: 'أيقونةُ الحالة غائبةٌ عن ${e.key}');
      final color = TableStatusPalette.colorFor(Brightness.light, status);
      final nameText = tester.widget<Text>(
          find.descendant(of: card, matching: find.text(e.key)));
      expect(nameText.style?.color, color,
          reason: 'لونُ الحالة غائبٌ عن ${e.key}');
    }
  });

  test('الألوانُ تتبع سطوعَ الثيم وكلُّ حالةٍ تتميّز عن غيرها', () {
    for (final b in Brightness.values) {
      final colors = {
        for (final s in TableStatus.all) s: TableStatusPalette.colorFor(b, s),
      };
      expect(colors.values.toSet().length, TableStatus.all.length,
          reason: 'حالتان بلونٍ واحد في $b');
    }
    expect(TableStatusPalette.colorFor(Brightness.light, 'available'),
        isNot(TableStatusPalette.colorFor(Brightness.dark, 'available')));
    expect(TableStatusPalette.colorFor(Brightness.light, 'seated'),
        TableStatusPalette.colorFor(Brightness.light, 'occupied'));
  });

  testWidgets('A.7 — اختيارُ حالةٍ يُعتِّم الباقي ولا يُنقص عددَ البطاقات',
      (tester) async {
    await _pump(tester);
    expect(find.byType(TableCard), findsNWidgets(_tables.length));
    for (final t in _tables) {
      expect(_opacityOfCard(tester, t.name), 1.0);
    }

    // اختيار «متاحة» (T1 وT6).
    await tester.tap(find.byKey(TablesStatusRail.tileKey(TableStatus.available)));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(TableCard), findsNWidgets(_tables.length),
        reason: '🔴 الاختيارُ أخفى طاولاتٍ — يجب أن يُعتِّم فقط');
    for (final t in _tables) {
      final matches = t.status == TableStatus.available;
      expect(
        _opacityOfCard(tester, t.name),
        matches ? 1.0 : TableStatusPalette.dimmedOpacity,
        reason: '${t.name}: ${matches ? 'يجب أن تبقى واضحة' : 'يجب أن تُعتَّم'}',
      );
    }

    // حالةٌ أخرى، ثم «عرض الكل» تعيد كلَّ شيءٍ.
    await tester.tap(find.byKey(TablesStatusRail.tileKey(TableStatus.paid)));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(TableCard), findsNWidgets(_tables.length));
    expect(_opacityOfCard(tester, 'T4'), 1.0);
    expect(_opacityOfCard(tester, 'T1'), TableStatusPalette.dimmedOpacity);

    await tester.tap(find.byKey(TablesStatusRail.tileKey(TablesStatusRail.allKey)));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(TableCard), findsNWidgets(_tables.length));
    for (final t in _tables) {
      expect(_opacityOfCard(tester, t.name), 1.0, reason: '${t.name} بقيت معتَّمة');
    }
  });

  testWidgets('زرُّ «إلغاء التمييز» يظهر عند الاختيار فقط ويُعيد الكلّ',
      (tester) async {
    await _pump(tester);
    const clear = Key('tablesStatusClearHighlight');
    expect(find.byKey(clear), findsNothing);
    await tester.tap(find.byKey(TablesStatusRail.tileKey(TableStatus.reserved)));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(clear), findsOneWidget);
    expect(_opacityOfCard(tester, 'T1'), TableStatusPalette.dimmedOpacity);
    await tester.tap(find.byKey(clear));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(clear), findsNothing);
    expect(_opacityOfCard(tester, 'T1'), 1.0);
  });

  testWidgets('البطاقةُ المعتَّمةُ تبقى قابلةً للنقر', (tester) async {
    RestaurantTable? tapped;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 200,
              height: 200,
              child: TableCard(
                table: _tables[1],
                restaurantRepo: _Repo(),
                onInteraction: (t) => tapped = t,
                dimmed: true,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byType(TableCard));
    expect(tapped?.id, 2);
  });

  testWidgets('الداكن: تُرسَم البطاقاتُ بألوان الداكن بلا فيضان', (tester) async {
    await _pump(tester, brightness: Brightness.dark);
    final card = find.ancestor(of: find.text('T1'), matching: find.byType(TableCard));
    final name = tester.widget<Text>(
        find.descendant(of: card, matching: find.text('T1')));
    expect(name.style?.color,
        TableStatusPalette.colorFor(Brightness.dark, 'available'));
  });

  test('النموذجُ الخالص: كلُّ الطاولات تُعرَض أيّاً كان المرشِّح', () {
    for (final f in [null, 'all', TableStatus.available, TableStatus.paid]) {
      expect(TablesGridModel.visibleTables(_tables, f).length, _tables.length);
    }
    expect(TablesGridModel.isDimmed('paid', 'all'), isFalse);
    expect(TablesGridModel.isDimmed('paid', null), isFalse);
    expect(TablesGridModel.isDimmed('paid', 'available'), isTrue);
    expect(TablesGridModel.isHighlighted('paid', 'paid'), isTrue);
    expect(TablesGridModel.isHighlighted('paid', 'all'), isFalse);
  });
}
