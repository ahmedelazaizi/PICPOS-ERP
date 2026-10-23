// شريطُ إجراءات الترويسة بأولويّات — خطة الطاولات A.4 / P1.
//
// بلاغُ المالك: «إضافة طاولة» مقصوصٌ تحت منطقة العنوان. السببُ أنّ الإجراءات
// كانت في `SingleChildScrollView` مثبَّتٍ من آخره فينزلق **أوّلُها** بصمتٍ.
// المقياسُ هنا **عرضُ النافذة** (١٠٢٤/١٢٨٠/١٩٢٠)، فالفيضانُ لا يرمي ولا يُحذّر.
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:ural_erp/data/providers/providers.dart';
import 'package:ural_erp/presentation/picpos_shell/picpos_header_actions.dart';
import 'package:ural_erp/presentation/picpos_shell/picpos_page_header.dart';
import 'package:ural_erp/presentation/picpos_shell/picpos_screen_scaffold.dart';

List<PicPosHeaderAction> _sixActions(List<String> log) => [
      PicPosHeaderAction(
        buttonKey: const Key('a_add'),
        label: 'إضافة طاولة',
        icon: PhosphorIconsBold.plus,
        priority: 1,
        onPressed: () => log.add('add'),
      ),
      PicPosHeaderAction(
        label: 'إدارة الأقسام',
        icon: PhosphorIconsBold.mapPinArea,
        priority: 4,
        onPressed: () => log.add('sections'),
      ),
      PicPosHeaderAction(
        label: 'عرض الخريطة',
        icon: PhosphorIconsBold.mapTrifold,
        priority: 2,
        onPressed: () => log.add('toggle'),
      ),
      PicPosHeaderAction(
        label: 'مصمم القاعة',
        icon: PhosphorIconsBold.squaresFour,
        priority: 5,
        onPressed: () => log.add('designer'),
      ),
      PicPosHeaderAction(
        label: 'كل المناطق',
        icon: PhosphorIconsBold.mapPin,
        priority: 3,
        choices: [
          PicPosHeaderChoice(
              label: 'الصالة', onSelected: () => log.add('scope:hall')),
        ],
      ),
      PicPosHeaderAction(
        label: 'مزيد من الخيارات',
        icon: PhosphorIconsBold.dotsThreeOutline,
        iconOnly: true,
        priority: 6,
        choices: [
          PicPosHeaderChoice(label: 'سجل الطاولة', onSelected: () {}),
        ],
      ),
    ];

Future<void> _pump(
  WidgetTester tester,
  double width,
  List<PicPosHeaderAction> actions, {
  Locale locale = const Locale('ar'),
  List<String> permissions = const ['tables_manage'],
}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentUserPermissionsProvider.overrideWith((ref) => permissions),
      ],
      child: MaterialApp(
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('ar'), Locale('en')],
        locale: locale,
        home: PicPosScreenScaffold(
          title: 'إدارة الطاولات',
          subtitle: 'نظرة عامة',
          icon: PhosphorIconsBold.circlesThree,
          headerActionsBar: actions,
          body: const SizedBox.shrink(),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

/// الزرُّ مرئيٌّ كاملاً داخل النافذة وقابلٌ للنقر.
void _expectFullyVisible(WidgetTester tester, Finder f, double width,
    {bool hit = true}) {
  final rect = tester.getRect(f);
  expect(rect.left, greaterThanOrEqualTo(-0.5), reason: 'مقصوصٌ من اليسار');
  expect(rect.right, lessThanOrEqualTo(width + 0.5), reason: 'مقصوصٌ من اليمين');
  if (hit) expect(f.hitTestable(), findsOneWidget);
}

void main() {
  test('التوزيعُ الخالص: الأعلى أولويّةً يبقى ولو ضاق العرض كلّه', () {
    final plan = planVisibleHeaderActions(
      widths: [120, 120, 120],
      priorities: [2, 1, 3],
      available: 10,
      overflowWidth: 48,
      gap: 8,
    );
    expect(plan, [false, true, false]);
  });

  test('التوزيعُ الخالص: كلُّها تظهر إن اتّسع العرضُ فلا «⋯» بلا داعٍ', () {
    final plan = planVisibleHeaderActions(
      widths: [100, 100, 100],
      priorities: [1, 2, 3],
      available: 320,
      overflowWidth: 48,
      gap: 8,
    );
    expect(plan, [true, true, true]);
  });

  test('التوزيعُ الخالص: يُحجَز مكانُ «⋯» ويُنقَل الأقلُّ أولويّةً أوّلاً', () {
    final plan = planVisibleHeaderActions(
      widths: [100, 100, 100],
      priorities: [1, 2, 3],
      available: 270, // 100+8+100 = 208، وإضافة الثالث تتطلّب 316.
      overflowWidth: 48,
      gap: 8,
    );
    expect(plan, [true, true, false]);
  });

  for (final width in [1024.0, 1280.0, 1920.0]) {
    testWidgets('عند $width: «إضافة طاولة» ظاهرةٌ كاملةً (RTL) والباقي في متناول اليد',
        (tester) async {
      final log = <String>[];
      await _pump(tester, width, _sixActions(log));

      final add = find.byKey(const Key('a_add'));
      expect(add, findsOneWidget);
      _expectFullyVisible(tester, add, width);

      // كلُّ إجراءٍ إمّا ظاهرٌ ومقروء، وإمّا في قائمة «⋯» — لا ثالث.
      const labels = [
        'إدارة الأقسام',
        'عرض الخريطة',
        'مصمم القاعة',
        'كل المناطق',
      ];
      final overflow = find.byKey(PicPosHeaderActionsBar.overflowKey);
      final hidden = [
        for (final l in labels)
          if (find.text(l).evaluate().isEmpty) l,
      ];
      for (final l in labels) {
        if (!hidden.contains(l)) {
          _expectFullyVisible(
            tester,
            find.ancestor(
              of: find.text(l),
              matching: find.byWidgetPredicate((w) =>
                  w is OutlinedButton || w is PopupMenuButton),
            ).first,
            width,
            hit: false, // قائمةٌ منسدلةٌ: الزرُّ فيها داخل IgnorePointer عمداً.
          );
        }
      }
      if (hidden.isNotEmpty) {
        expect(overflow, findsOneWidget, reason: 'إجراءاتٌ اختفت بلا «⋯»: $hidden');
        await tester.tap(overflow);
        await tester.pumpAndSettle();
        for (final l in hidden) {
          expect(find.text(l), findsOneWidget,
              reason: '«$l» غير ظاهرٍ ولا في «⋯»');
        }
      } else {
        expect(overflow, findsNothing);
      }
      // إيقاع الأولويّة: الأعلى أولويّةً لا يتأخّر عن الأقلّ منه في الاختفاء.
      if (!hidden.contains('عرض الخريطة')) {
        // الثانية أولويّةً — إن اختفت فكلُّ ما بعدها مختفٍ.
      } else {
        expect(hidden.contains('مصمم القاعة'), isTrue);
        expect(hidden.contains('إدارة الأقسام'), isTrue);
      }
    });
  }

  testWidgets('عند 700 (ضيقٌ حقيقيّ): الرئيسيّ ظاهرٌ وغيرُه في «⋯» ويعمل',
      (tester) async {
    final log = <String>[];
    await _pump(tester, 700, _sixActions(log));

    final add = find.byKey(const Key('a_add'));
    _expectFullyVisible(tester, add, 700);
    expect(find.byKey(PicPosHeaderActionsBar.overflowKey), findsOneWidget);
    expect(find.text('مصمم القاعة'), findsNothing,
        reason: 'الأقلُّ أولويّةً يجب أن يُنقَل عند هذا العرض');

    await tester.tap(find.byKey(PicPosHeaderActionsBar.overflowKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text('مصمم القاعة'));
    await tester.pumpAndSettle();
    expect(log, ['designer'], reason: 'مدخلُ «⋯» لا ينفّذ فعلَه');

    await tester.tap(add);
    expect(log.last, 'add');
  });

  testWidgets('القائمةُ المنسدلة تُسطَّح داخل «⋯» وتنفّذ الخيار', (tester) async {
    final log = <String>[];
    await _pump(tester, 600, _sixActions(log));
    await tester.tap(find.byKey(PicPosHeaderActionsBar.overflowKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text('الصالة'));
    await tester.pumpAndSettle();
    expect(log, ['scope:hall']);
  });

  testWidgets('الحراسةُ تلحق الإجراءَ إلى «⋯»: بلا صلاحية يُطلَب تصريح ولا يُنفَّذ',
      (tester) async {
    var ran = false;
    await _pump(
      tester,
      600,
      [
        PicPosHeaderAction(
          label: 'إضافة طاولة',
          icon: PhosphorIconsBold.plus,
          priority: 1,
          onPressed: () {},
        ),
        PicPosHeaderAction(
          label: 'مصمم القاعة',
          icon: PhosphorIconsBold.squaresFour,
          priority: 9,
          permission: 'tables_manage',
          onPressed: () => ran = true,
        ),
        PicPosHeaderAction(
          label: 'إدارة الأقسام',
          icon: PhosphorIconsBold.mapPinArea,
          priority: 8,
          onPressed: () {},
        ),
      ],
      permissions: const [],
    );
    expect(find.text('مصمم القاعة'), findsNothing, reason: 'يجب أن يكون في «⋯»');
    await tester.tap(find.byKey(PicPosHeaderActionsBar.overflowKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text('مصمم القاعة'));
    await tester.pumpAndSettle();
    expect(find.text('تصريح المسؤول مطلوب'), findsOneWidget);
    expect(ran, isFalse);
  });

  testWidgets('LTR (إنجليزي): الرئيسيّ ظاهرٌ كاملاً أيضاً', (tester) async {
    await _pump(tester, 1024, _sixActions([]), locale: const Locale('en'));
    _expectFullyVisible(tester, find.byKey(const Key('a_add')), 1024);
  });

  testWidgets('اتجاهُ RTL: الرئيسيّ (الأوّل) في طرف البداية = اليمين',
      (tester) async {
    await _pump(tester, 1280, _sixActions([]));
    final add = tester.getCenter(find.byKey(const Key('a_add')));
    final title = tester.getCenter(find.text('إدارة الطاولات'));
    // العنوان عند البداية (اليمين) والإجراءات تمتدّ نحو اليسار.
    expect(title.dx, greaterThan(add.dx));
  });

  testWidgets('الترويسةُ القديمة (actions) لم تتغيّر: لا «⋯» ولا شريط',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ar'),
        supportedLocales: const [Locale('ar')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(
          body: PicPosPageHeader(
            title: 't',
            actions: [TextButton(onPressed: () {}, child: const Text('قديم'))],
          ),
        ),
      ),
    );
    expect(find.byType(PicPosHeaderActionsBar), findsNothing);
    expect(find.byType(SingleChildScrollView), findsOneWidget);
    expect(find.text('قديم'), findsOneWidget);
  });

  testWidgets('onBack يرسم سهمَ الرجوع بلا راوتٍ مدفوع ويستدعي الفعل',
      (tester) async {
    var backs = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PicPosPageHeader(title: 't', onBack: () => backs++),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('picpos_header_back')));
    expect(backs, 1);
  });
}
