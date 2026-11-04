// قماشُ الملصق في محرّر النماذج — من المكتبة إلى الحفظ وإعادة الفتح.
//
// ═══ ما يُقاس ═══
//
// ‏١) **تبويبُ «ملصقات الباركود» في المكتبة** يعرض الملصقاتِ وحدَها، و«تحرير»
//    يفتحها في قماش الملصق لا في محرّر النطاقات.
// ‏٢) **التعديلُ يصل التصميمَ المحفوظ**: سحبٌ على القماش، وخطٌّ وعريضٌ
//    ومحاذاة ⇒ ما يصل `saveLabelDesign` هو نفسُه ما يُقرأ عند إعادة الفتح.
// ‏٣) **التكافؤ**: كلُّ ملصقٍ من الستّة المبذورة يُفتح بكلِّ عناصره، ومعاينتُه
//    ترسمها كلَّها.
// ‏٤) **«ملصق جديد» بمقاسٍ مخصّص** من المكتبة ثمّ يُفتح.
// ‏٥) **الوضعُ الداكن** يُبنى بلا استثناء.
//
// التصاميمُ تُقرأ من قاعدةٍ حقيقيّةٍ مبذورةٍ مرّةً (‏`setUpAll` خارج الوقت
// المزيَّف)، والشاشةُ تعمل على مستودعٍ زائفٍ يحفظها في الذاكرة — قاعدةٌ حيّةٌ
// داخل اختبار ودجت تُعلّق `pumpAndSettle`.
//
// لقطاتُ التقرير: `--dart-define=LABEL_SNAPSHOTS=true` يكتبها في
// `docs/plans/barcode_editor_2026-11-03/`.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/data/providers/label_editor_providers.dart';
import 'package:picpos_erp/data/providers/repository_providers.dart';
import 'package:picpos_erp/data/providers/template_library_providers.dart';
import 'package:picpos_erp/data/repositories/invoice_templates_repository_impl.dart';
import 'package:picpos_erp/domain/models/picpos_template_card.dart';
import 'package:picpos_erp/domain/printing/label_design.dart';
import 'package:picpos_erp/domain/repositories/invoice_templates_repository.dart';
import 'package:picpos_erp/presentation/print_test_picpos/widgets/sheet_preview_view.dart';
import 'package:picpos_erp/presentation/template_editor_picpos/label/label_editor_view.dart';
import 'package:picpos_erp/presentation/template_editor_picpos/screens/template_editor_picpos_screen.dart';
import 'package:picpos_erp/presentation/template_library_picpos/screens/template_library_picpos_screen.dart';
import 'package:picpos_erp/presentation/template_library_picpos/widgets/template_gallery_card.dart';

const _kSnapshots = bool.fromEnvironment('LABEL_SNAPSHOTS');
const _shotKey = Key('shot');

const _seeded = <String>[
  'باركود قياسي',
  'بطاقة سعر',
  'ملصق كامل',
  'ملصق رف مضغوط',
  'ملصق مجوهرات',
  'ملصق كرتون كبير',
];

/// مستودعٌ يحفظ الملصقاتِ في الذاكرة — بنفس عقد الحفظ: الجديدُ ينال معرِّفاً.
class _FakeRepo implements IInvoiceTemplatesRepository {
  _FakeRepo(Map<int, LabelDesign> seed) : store = Map.of(seed);

  final Map<int, LabelDesign> store;
  final saves = <LabelDesign>[];
  ({String name, double w, double h})? created;
  var _nextId = 9000;

  @override
  Future<LabelDesign?> getLabelDesign(int templateId) async => store[templateId];

  @override
  Future<LabelDesign> saveLabelDesign(LabelDesign d) async {
    saves.add(d);
    final out = d.copyWith(elements: [
      for (final e in d.elements)
        if (e.id != null)
          e
        else
          () {
            final id = _nextId++;
            return LabelElement(
              key: 'e$id', id: id, type: e.type, xMm: e.xMm, yMm: e.yMm,
              wMm: e.wMm, hMm: e.hMm, fontSize: e.fontSize, bold: e.bold,
              italic: e.italic, align: e.align, color: e.color,
              content: e.content, borderWidth: e.borderWidth,
            );
          }(),
    ]);
    store[d.templateId] = out;
    return out;
  }

  @override
  Future<int> createLabelTemplate({
    required String name,
    required double widthMm,
    required double heightMm,
  }) async {
    created = (name: name, w: widthMm, h: heightMm);
    final id = _nextId++;
    var d = LabelDesign(
        templateId: id, name: name, widthMm: widthMm, heightMm: heightMm,
        elements: const []);
    (d, _) = addLabelElement(d, LabelElementTypes.productName);
    (d, _) = addLabelElement(d, LabelElementTypes.barcode);
    store[id] = await saveLabelDesign(d);
    return id;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late Map<String, int> ids;
  late Map<int, LabelDesign> designs;
  late List<TemplateCard> cards;

  setUpAll(() async {
    final loader = FontLoader('Cairo')
      ..addFont(rootBundle.load('assets/fonts/Cairo-Regular.ttf'))
      ..addFont(rootBundle.load('assets/fonts/Cairo-Bold.ttf'));
    await loader.load();

    final db = AppDatabase.forTesting();
    await db.seedDefaultTemplates();
    final repo = InvoiceTemplatesRepositoryImpl(db);
    ids = {};
    designs = {};
    cards = [
      // بطاقةُ فاتورةٍ واحدة — كي يُقاس أنّ المرشّحَ يفصل بينهما.
      const TemplateCard(
        id: 1, name: 'فاتورة اختبار', type: 'a4', category: 'invoice',
        paperWidthMm: 210, paperHeightMm: 297, paperLabel: 'A4',
        elementCount: 10, columnCount: 5, layoutVersion: 2, isDefault: true,
      ),
    ];
    for (final t in await db.getAllTemplates()) {
      if (t.templateCategory != 'barcode') continue;
      final d = (await repo.getLabelDesign(t.id))!;
      ids[t.name] = t.id;
      designs[t.id] = d;
      cards.add(labelCardFor(t, d));
    }
    debugPrint('LABELS_IN_DB: ${ids.keys.join(' | ')}');
    await db.close();
  });

  late _FakeRepo repo;

  Future<void> pump(WidgetTester tester, Widget home,
      {ThemeData? theme, _FakeRepo? reuse}) async {
    repo = reuse ?? _FakeRepo(designs);
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      RepaintBoundary(
        key: _shotKey,
        child: ProviderScope(
          overrides: [
            invoiceTemplatesRepositoryProvider.overrideWithValue(repo),
            templateCardsProvider.overrideWith((ref) async => cards),
          ],
          child: MaterialApp(
            locale: const Locale('ar'),
            theme: theme ?? ThemeData(fontFamily: 'Cairo'),
            home: Directionality(textDirection: TextDirection.rtl, child: home),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> shot(WidgetTester tester, String name) async {
    if (!_kSnapshots) return;
    final boundary =
        tester.renderObject<RenderRepaintBoundary>(find.byKey(_shotKey));
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 1);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      File('docs/plans/barcode_editor_2026-11-03/$name.png')
        ..createSync(recursive: true)
        ..writeAsBytesSync(png!.buffer.asUint8List());
    });
  }

  Future<void> teardownTree(WidgetTester tester) async {
    // الإشعارُ يعيش خمسَ ثوانٍ بمؤقّتٍ حيّ — يُستهلَك قبل تفكيك الشجرة.
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }

  LabelEditorState editorState(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(LabelEditorView)))
          .read(labelEditorProvider)!;

  Finder elementBoxes() => find.byWidgetPredicate((w) =>
      w.key is ValueKey<String> &&
      (w.key as ValueKey<String>).value.startsWith('label-el-'));

  Future<void> tapPlus(WidgetTester tester, String propKey) async {
    await tester.tap(find.descendant(
        of: find.byKey(Key(propKey)), matching: find.byIcon(PhosphorIconsBold.plus)));
    await tester.pump();
  }

  group('المكتبة — تبويبُ «ملصقات الباركود»', () {
    testWidgets('يعرض الستّةَ وحدَها، و«تحرير» يفتح قماشَ الملصق', (tester) async {
      await pump(tester, const TemplateLibraryPicposScreen());

      // «الكل» يبقى للفواتير: الملصقاتُ لا تختلط بها.
      expect(find.byType(TemplateGalleryCard), findsOneWidget);

      await tester.tap(find.textContaining('ملصقات الباركود ('));
      await tester.pumpAndSettle();
      // كلُّ قوالب فئة barcode في القاعدة — والستّةُ المبذورةُ بينها.
      expect(ids.keys, containsAll(_seeded));
      expect(find.byType(TemplateGalleryCard), findsNWidgets(designs.length));
      expect(find.text('فاتورة اختبار'), findsNothing);
      await shot(tester, '01_library_barcode_tab');

      await tester.tap(find.text('بطاقة سعر').first);
      await tester.pumpAndSettle();
      // شاشةُ الطباعة التجريبيّة تمرّ بالنطاقات — لا تُعرض للملصق.
      expect(find.text('معاينة تجريبية'), findsNothing);

      await tester.tap(find.byKey(const Key('library-edit')));
      await tester.pumpAndSettle();

      expect(find.byType(LabelEditorView), findsOneWidget);
      expect(find.byKey(const Key('label-canvas')), findsOneWidget);
      final d = designs[ids['بطاقة سعر']]!;
      expect(elementBoxes(), findsNWidgets(d.elements.length));
      await shot(tester, '02_label_editor_price_card');
      await teardownTree(tester);
    });

    testWidgets('«ملصق جديد» بمقاسٍ مخصّص يُنشئ ويفتح', (tester) async {
      await pump(tester,
          const TemplateLibraryPicposScreen(initialFilter: TemplateFilter.barcode));
      expect(find.text('ملصق جديد'), findsOneWidget);

      await tester.tap(find.byKey(const Key('library-new-template')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('new-label-name')), 'رف ٧٠');
      await tester.enterText(find.byKey(const Key('new-label-w')), '70');
      await tester.enterText(find.byKey(const Key('new-label-h')), '35');
      await shot(tester, '03_new_label_dialog');
      await tester.tap(find.byKey(const Key('new-label-create')));
      await tester.pumpAndSettle();

      expect(repo.created, (name: 'رف ٧٠', w: 70.0, h: 35.0));
      expect(find.byType(LabelEditorView), findsOneWidget);
      final s = editorState(tester);
      expect([s.design.widthMm, s.design.heightMm], [70, 35]);
      expect(elementBoxes(), findsNWidgets(2));
      await teardownTree(tester);
    });

    testWidgets('مقاسٌ خارجَ الحدود يُرفض بسبب', (tester) async {
      await pump(tester,
          const TemplateLibraryPicposScreen(initialFilter: TemplateFilter.barcode));
      await tester.tap(find.byKey(const Key('library-new-template')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('new-label-w')), '5');
      await tester.tap(find.byKey(const Key('new-label-create')));
      await tester.pumpAndSettle();
      expect(repo.created, isNull);
      expect(find.textContaining('المقاسُ بين'), findsOneWidget);
      await teardownTree(tester);
    });
  });

  group('التعديلُ يصل المحفوظ ويعود بإعادة الفتح', () {
    testWidgets('سحبٌ وخطٌّ وعريضٌ ومحاذاة ⇒ حفظ ⇒ نفسُ القيم', (tester) async {
      final id = ids['بطاقة سعر']!;
      await pump(tester, TemplateEditorPicposScreen(templateId: id, labelMode: true));

      final before = editorState(tester).design;
      final name = before.elements.firstWhere((e) => e.type == 'product_name');
      final code = before.elements.firstWhere((e) => e.type == 'barcode_image');

      // الاسم: +٠٫٥ نقطة، بلا عريض، محاذاةٌ يمنى.
      await tester.tap(find.byKey(Key('label-row-${name.key}')));
      await tester.pump();
      await tapPlus(tester, 'label-prop-font');
      await tester.tap(find.byKey(const Key('label-prop-bold')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('label-prop-align-right')));
      await tester.pump();

      // الباركود: سحبٌ على القماش (٨ بكسل/مم) ثمّ «من الأعلى» −٠٫٥.
      await tester.drag(find.byKey(Key('label-el-${code.key}')), const Offset(-40, 24));
      await tester.pump();
      await tester.tap(find.descendant(
          of: find.byKey(const Key('label-prop-y')),
          matching: find.byIcon(PhosphorIconsBold.minus)));
      await tester.pump();

      final s = editorState(tester);
      expect(s.isDirty, isTrue);
      expect(find.text('تعديلات غير محفوظة'), findsOneWidget);
      final n2 = s.design.byKey(name.key)!;
      final c2 = s.design.byKey(code.key)!;
      expect([n2.fontSize, n2.bold, n2.align], [name.fontSize + 0.5, false, 'right']);
      // السحبُ يساراً وأسفل ثمّ −٠٫٥ — والقيمُ على شبكة نصف المليمتر.
      expect(c2.xMm, lessThan(code.xMm));
      expect(c2.yMm, greaterThan(code.yMm - 0.5));
      expect((c2.xMm * 2) % 1, 0);
      expect((c2.yMm * 2) % 1, 0);

      await tester.tap(find.byKey(const Key('label-save')));
      await tester.pumpAndSettle();
      expect(repo.saves, hasLength(1));
      expect(repo.saves.single, s.design);
      expect(editorState(tester).isDirty, isFalse);
      await teardownTree(tester);

      // إعادةُ الفتح على نفس المستودع — نفسُ القيم.
      await pump(tester, TemplateEditorPicposScreen(templateId: id, labelMode: true),
          reuse: repo);
      final reopened = editorState(tester).design;
      expect(reopened, s.design);
      expect(reopened.byKey(code.key)!.xMm, c2.xMm);
      await teardownTree(tester);
    });

    testWidgets('إضافةُ عنصرٍ وحذفُ آخر يصلان الحفظ', (tester) async {
      final id = ids['ملصق كامل']!;
      await pump(tester, TemplateEditorPicposScreen(templateId: id, labelMode: true));
      final n0 = editorState(tester).design.elements.length;

      await tester.tap(find.byKey(const Key('label-add-barcode_image-qrCode')));
      await tester.pump();
      var s = editorState(tester);
      expect(s.design.elements.length, n0 + 1);
      expect(s.selected!.isQr, isTrue);

      final first = s.design.elements.first.key;
      await tester.tap(find.byKey(Key('label-row-$first')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('label-prop-delete')));
      await tester.pump();

      await tester.tap(find.byKey(const Key('label-save')));
      await tester.pumpAndSettle();
      s = editorState(tester);
      expect(s.design.elements.length, n0);
      expect(s.design.elements.any((e) => e.key == first), isFalse);
      expect(s.design.elements.last.id, isNotNull, reason: 'الجديدُ لم ينل معرِّفاً');
      expect(repo.store[id]!.elements.last.content, 'qrCode');
      await teardownTree(tester);
    });
  });

  group('التكافؤ — الستّةُ المبذورة في قماش الملصق', () {
    for (final name in _seeded) {
      testWidgets('«$name» يُفتح بكلِّ عناصره ومعاينتُه ترسمها كلَّها',
          (tester) async {
        final id = ids[name]!;
        final d = designs[id]!;
        await pump(tester, TemplateEditorPicposScreen(templateId: id, labelMode: true));

        expect(elementBoxes(), findsNWidgets(d.elements.length));
        for (final e in d.elements) {
          expect(find.byKey(Key('label-el-${e.key}')), findsOneWidget,
              reason: '«$name» فقد ${e.type}');
        }
        expect(editorState(tester).design, d);

        await tester.tap(find.byKey(const Key('label-preview-toggle')));
        await tester.pumpAndSettle();
        final preview =
            tester.widget<SheetPreviewView>(find.byKey(const Key('label-preview')));
        expect(preview.ops.length, d.elements.length);
        expect([preview.widthMm, preview.heightMm], [d.widthMm, d.heightMm]);
        if (name == 'ملصق كرتون كبير') await shot(tester, '04_preview_large_carton');
        await teardownTree(tester);
      });
    }
  });

  // وما يُبذر بعد الستّة (‏«ملصق ميزان» مثلاً) يُفتح كذلك — بلا قائمةٍ مكتوبة.
  testWidgets('كلُّ قالبٍ من فئة barcode في القاعدة يُفتح بكلِّ عناصره',
      (tester) async {
    for (final e in ids.entries) {
      final d = designs[e.value]!;
      await pump(tester,
          TemplateEditorPicposScreen(templateId: e.value, labelMode: true));
      expect(elementBoxes(), findsNWidgets(d.elements.length),
          reason: '«${e.key}» فقد عناصر');
      expect(editorState(tester).design, d);
      await teardownTree(tester);
    }
  });

  testWidgets('الوضعُ الداكن يُبنى بلا استثناء', (tester) async {
    await pump(
      tester,
      TemplateEditorPicposScreen(templateId: ids['ملصق كامل']!, labelMode: true),
      theme: ThemeData.dark().copyWith(
          textTheme: ThemeData.dark().textTheme.apply(fontFamily: 'Cairo')),
    );
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('label-canvas')), findsOneWidget);
    await shot(tester, '05_label_editor_dark');
    await teardownTree(tester);
  });
}
