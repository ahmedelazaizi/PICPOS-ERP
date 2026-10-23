// كلُّ قالبٍ مبذورٍ يعبر المحرّكَ الجديد — على بياناتٍ حقيقيّةٍ لا مصنوعة.
//
// ── لماذا على الملفّات نفسِها ─────────────────────────────────────────────
// اختباراتُ المحرّك السابقةُ تبني قوالبَ بيدها، فتقيس المحرّكَ على ما تخيّلتُه
// عنه. وهذا يقيسه على **ما في المستودع فعلاً**: تسعةَ عشرَ ملفَّ JSON، ثمانيةٌ
// منها قديمةٌ مبذورةٌ وأحدَ عشرَ جديدة.
//
// وقيمةُ ذلك أنّ فئةَ العطب هنا «قالبٌ يفلت من الاشتقاق»: مقطعٌ لم يخطر
// بالبال، أو نوعُ عنصرٍ غيرُ معروف، أو نطاقٌ يخرج فارغاً فيسقط نصفُ الفاتورة
// بلا شكوى. ولا يمسكها إلّا المرورُ على الملفّات كلِّها.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/domain/printing/template_document.dart';
import 'package:picpos_erp/domain/printing/template_mapper.dart';
import 'package:picpos_erp/services/printing/layout_engine.dart';

const _dir = 'assets/invoice_templates';

/// الأحدَ عشرَ الجديدةُ — مكتوبةٌ أصلاً بالبنية الصحيحة وبمفاتيحَ سليمة.
const _newOnes = <String>[
  'a4_sales_tax_invoice.json',
  'a5_sales_tax_invoice.json',
  'a4_purchase_invoice.json',
  'thermal80_quick_sale.json',
  'thermal58_quick_sale.json',
  'a4_sales_return.json',
  'thermal80_sales_return.json',
  'a4_purchase_return.json',
  'a4_customer_statement.json',
  'a4_supplier_statement.json',
  'a4_report_generic.json',
];

List<File> _files() => Directory(_dir)
    .listSync()
    .whereType<File>()
    .where((f) => f.path.endsWith('.json'))
    .toList()
  ..sort((a, b) => a.path.compareTo(b.path));

Map<String, dynamic> _json(File f) =>
    jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;

/// يبني عناصرَ المحرّك من الصيغة المخزَّنة — نفسُ ما يفعله الـDAO.
List<LegacyElement> _elements(Map<String, dynamic> data) => [
      for (final raw in (data['elements'] as List<dynamic>? ?? []))
        LegacyElement(
          elementType: (raw as Map<String, dynamic>)['type'] as String? ?? 'text',
          content: raw['content'] as String?,
          section: raw['section'] as String? ?? 'body',
          sortOrder: raw['sortOrder'] as int? ?? 0,
          flexWidth: (raw['flexWidth'] as num?)?.toDouble() ?? 100,
          fontSize: (raw['fontSize'] as num?)?.toDouble() ?? 12,
          isBold: raw['isBold'] as bool? ?? false,
          isVisible: raw['isVisible'] as bool? ?? true,
          labelAr: raw['labelAr'] as String?,
          labelEn: raw['labelEn'] as String?,
          textAlign: raw['textAlign'] as String? ?? 'center',
        ),
    ];

PaperSpec _paper(Map<String, dynamic> data) {
  final w = (data['paperWidth'] as num?)?.toDouble() ?? 80;
  final h = (data['paperHeight'] as num?)?.toDouble();
  final margins = w < 100 ? const MarginsMm.all(3) : const MarginsMm.all(10);
  return h == null
      ? PaperSpec.continuous(widthMm: w, margins: margins)
      : PaperSpec(widthMm: w, heightMm: h, margins: margins);
}

void main() {
  test('الملفّاتُ كلُّها موجودةٌ ومعها الأحدَ عشرَ الجديدة', () {
    final names = _files().map((f) => f.uri.pathSegments.last).toSet();
    expect(names.length, greaterThanOrEqualTo(19));
    for (final n in _newOnes) {
      expect(names, contains(n), reason: 'القالبُ الجديد $n لم يُنسخ');
    }
  });

  for (final file in _files()) {
    final name = file.uri.pathSegments.last;

    group(name, () {
      late Map<String, dynamic> data;
      late TemplateDocument doc;

      setUp(() {
        data = _json(file);
        doc = TemplateMapper.fromLegacy(
          paper: _paper(data),
          elements: _elements(data),
          table: const TableSpec(
            columns: [
              TableColumn(key: 'name', labelAr: 'الصنف', flex: 3),
              TableColumn(key: 'qty', labelAr: 'العدد'),
              TableColumn(key: 'total', labelAr: 'الإجمالي'),
            ],
            rowHeightMm: 6,
          ),
        );
      });

      test('كلُّ عنصرٍ وصل نطاقاً — لا شيءَ يسقط في الاشتقاق', () {
        final placed =
            doc.bands.fold<int>(0, (s, b) => s + b.elements.length);
        expect(placed, _elements(data).length,
            reason: 'عنصرٌ ضاع بين الصيغة المخزَّنة والنطاقات');
      });

      test('النطاقاتُ الستّةُ كلُّها معرَّفة', () {
        expect(doc.bands.map((b) => b.id).toSet(), BandId.values.toSet(),
            reason: 'نطاقٌ غائبٌ يعني مكانَ إفلاتٍ مفقوداً في المحرّر');
      });

      test('details وحدَه يتمدّد', () {
        for (final b in doc.bands) {
          expect(b.growsWithData, b.id.isDetails, reason: b.id.name);
        }
      });

      test('لا عنصرَ يتجاوز عرضَ المحتوى', () {
        final max = doc.paper.contentWidthMm;
        for (final b in doc.bands) {
          for (final e in b.elements) {
            expect(e.xMm + e.wMm, lessThanOrEqualTo(max + 0.001),
                reason: '${e.contentKey} في ${b.id.name} يفيض عن الورق');
          }
        }
      });

      test('والتخطيطُ يمرّ ببيانات — صفحةٌ واحدةٌ على الأقلّ', () {
        final pages = LayoutEngine.paginate(
          document: doc,
          rows: List.generate(4, (i) => ['صنف $i', '2', '50.00']),
          values: const {},
        );
        expect(pages, isNotEmpty);
        expect(pages.first.widthMm, doc.paper.widthMm);
      });
    });
  }

  group('القوالبُ الجديدةُ تحمل مفاتيحَ سليمة', () {
    for (final n in _newOnes) {
      test('$n — كلُّ عنصرٍ نصّيٍّ له content', () {
        final data = _json(File('$_dir/$n'));
        final missing = <String>[];

        for (final raw in (data['elements'] as List<dynamic>)) {
          final m = raw as Map<String, dynamic>;
          final type = m['type'] as String? ?? 'text';
          if (!TemplateMapper.isTextBearing(type)) continue;
          final c = (m['content'] as String?)?.trim() ?? '';
          if (c.isEmpty) missing.add(type);
        }

        expect(missing, isEmpty,
            reason: 'عنصرٌ نصّيٌّ بلا content يظهر مُطفأً في المحرّر رغم أنّه '
                'على الورق — وهو عطبُ القوالب الثمانيةِ القديمة');
      });
    }
  });
}
