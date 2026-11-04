import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:picpos_erp/services/printing/barcode_label_printer.dart';
import 'package:picpos_erp/services/printing/barcode_label_spec.dart';
import 'package:picpos_erp/services/printing/label_preset_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

BarcodeLabelItem _item(String n, int copies, {String? barcode}) =>
    BarcodeLabelItem(name: n, barcode: barcode ?? 'B$n', copies: copies);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LabelSpec', () {
    test('كل المقاسات الجاهزة صالحة ومعرّفاتها فريدة', () {
      for (final s in LabelSpec.presets) {
        expect(s.validate(), isNull, reason: s.id);
      }
      expect(LabelSpec.presets.map((s) => s.id).toSet().length,
          LabelSpec.presets.length);
    });

    test('الافتراضي يطابق السلوك القديم 50×25 هامش 2 ملصق واحد', () {
      const s = LabelSpec.defaultSpec;
      expect([s.pageWidthMm, s.pageHeightMm, s.innerPaddingMm, s.labelsPerPage],
          [50, 25, 2, 1]);
    });

    test('رول بعمودين: عرض الصفحة = عمودان + المسافة', () {
      const s = LabelSpec.roll(
          id: 'x', name: 'x', widthMm: 40, heightMm: 25, columns: 2, gapMm: 3);
      expect(s.pageWidthMm, 83);
      expect(s.labelsPerPage, 2);
    });

    test('A4 3×8: خلايا من الشبكة بعد الهوامش', () {
      final s = LabelSpec.presets.firstWhere((e) => e.id == 'a4_3x8');
      expect(s.labelsPerPage, 24);
      expect(s.cellWidthMm, closeTo((210 - 16) / 3, 1e-9));
      expect(s.cellHeightMm, closeTo((297 - 16) / 8, 1e-9));
    });

    test('التحقق يرفض الأبعاد غير المعقولة', () {
      LabelSpec roll(double w, double h, double m, int c) => LabelSpec.roll(
          id: 'c', name: 'c', widthMm: w, heightMm: h, marginMm: m, columns: c);
      expect(roll(5, 25, 2, 1).validate(), 'width');
      expect(roll(50, 5, 2, 1).validate(), 'height');
      expect(roll(50, 25, 2, 0).validate(), 'columns');
      expect(roll(30, 20, 12, 1).validate(), 'margin');
      expect(roll(50, 25, 2, 1).validate(), isNull);
    });

    test('JSON ذهاباً وإياباً، والتالف يُرجع null', () {
      const s = LabelSpec.roll(
          id: 'c1', name: 'مقاسي', widthMm: 45.5, heightMm: 30, columns: 2);
      final back = LabelSpec.fromJson(s.toJson());
      expect(back?.widthMm, 45.5);
      expect(back?.columns, 2);
      expect(back?.isCustom, isTrue);
      expect(LabelSpec.fromJson({'id': 'x'}), isNull);
      expect(LabelSpec.fromJson('junk'), isNull);
    });
  });

  group('LabelLayout', () {
    test('النسخ لكل صنف وتجاهل الصفر وغير الباركود', () {
      final jobs = LabelLayout.expand([
        _item('a', 3),
        _item('b', 0),
        _item('c', 2, barcode: ' '),
        _item('d', 1),
      ]);
      expect(jobs.map((j) => j.item.name).toList(), ['a', 'a', 'a', 'd']);
    });

    test('تقييد النسخ', () {
      expect(LabelLayout.clampCopies(-4), 0);
      expect(LabelLayout.clampCopies(100000), LabelSpec.maxCopiesPerItem);
    });

    test('رول عمود واحد: ملصق لكل صفحة', () {
      final pages = LabelLayout.paginate(
          LabelSpec.defaultSpec, [_item('a', 2), _item('b', 1)]);
      expect(pages.map((p) => p.length).toList(), [1, 1, 1]);
    });

    test('رول بعمودين: 5 ملصقات → 2+2+1', () {
      const spec = LabelSpec.roll(
          id: 'x', name: 'x', widthMm: 40, heightMm: 25, columns: 2);
      final pages = LabelLayout.paginate(spec, [_item('a', 5)]);
      expect(pages.map((p) => p.length).toList(), [2, 2, 1]);
    });

    test('A4 3×8 = 24 للصفحة: 30 ملصقاً → صفحتان 24+6', () {
      final spec = LabelSpec.presets.firstWhere((e) => e.id == 'a4_3x8');
      final pages =
          LabelLayout.paginate(spec, [_item('a', 20), _item('b', 10)]);
      expect(pages.map((p) => p.length).toList(), [24, 6]);
      // الترتيب محفوظ: الصنف a أولاً ثم b.
      expect(pages.first[19].item.name, 'a');
      expect(pages.first[20].item.name, 'b');
    });

    test('لا ملصقات → لا صفحات، والحد الأقصى الإجمالي', () {
      expect(LabelLayout.paginate(LabelSpec.defaultSpec, []), isEmpty);
      expect(LabelLayout.exceedsLimit([_item('a', 999)]), isFalse);
      expect(
          LabelLayout.exceedsLimit([for (var i = 0; i < 6; i++) _item('$i', 999)]),
          isTrue);
    });
  });

  group('LabelPresetStore', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('الحفظ والاستبدال والحذف والمقاس النشط', () async {
      expect((await LabelPresetStore.activeSpec()).id, 'roll_50x25');
      const s = LabelSpec.roll(
          id: 'c1', name: 'مخصص', widthMm: 60, heightMm: 30, isCustom: true);
      await LabelPresetStore.saveCustom(s);
      await LabelPresetStore.saveCustom(const LabelSpec.roll(
          id: 'c1', name: 'مخصص2', widthMm: 61, heightMm: 30, isCustom: true));
      final custom = await LabelPresetStore.loadCustom();
      expect(custom.length, 1);
      expect(custom.single.widthMm, 61);
      expect((await LabelPresetStore.loadAll()).length,
          LabelSpec.presets.length + 1);

      await LabelPresetStore.setActiveId('c1');
      expect((await LabelPresetStore.activeSpec()).widthMm, 61);
      await LabelPresetStore.deleteCustom('c1');
      expect(await LabelPresetStore.loadCustom(), isEmpty);
      expect((await LabelPresetStore.activeSpec()).id, 'roll_50x25');
    });

    test('مقاس غير صالح يُرفض، والبيانات التالفة تُتجاهل', () async {
      await expectLater(
          LabelPresetStore.saveCustom(const LabelSpec.roll(
              id: 'bad', name: 'bad', widthMm: 1, heightMm: 1)),
          throwsArgumentError);
      SharedPreferences.setMockInitialValues(
          {LabelPresetStore.customKey: '{not json'});
      expect(await LabelPresetStore.loadCustom(), isEmpty);
    });
  });

  group('BarcodeLabelPrinter.buildDocument', () {
    int pageCount(pw.Document doc) => doc.document.pdfPageList.pages.length;

    test('عدد الصفحات = ما يحسبه التخطيط (رول وA4)', () async {
      final items = [_item('a', 3), _item('b', 2)];
      final roll =
          await BarcodeLabelPrinter.buildDocument(items, LabelSpec.defaultSpec);
      expect(pageCount(roll), 5);
      final a4 = await BarcodeLabelPrinter.buildDocument(
          items, LabelSpec.presets.firstWhere((e) => e.id == 'a4_3x8'));
      expect(pageCount(a4), 1);
    });
  });
}
