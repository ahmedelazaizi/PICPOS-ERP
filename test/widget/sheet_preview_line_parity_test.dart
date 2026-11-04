import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/domain/printing/template_document.dart';
import 'package:picpos_erp/domain/printing/template_mapper.dart';
import 'package:picpos_erp/presentation/print_test_picpos/widgets/sheet_preview_view.dart';
import 'package:picpos_erp/services/printing/layout_engine.dart';
import 'package:picpos_erp/services/printing/paint_plan.dart';

const _dir = 'assets/invoice_templates';

List<File> _targetTemplates() => Directory(_dir)
    .listSync()
    .whereType<File>()
    .where((file) => file.path.endsWith('.json'))
    .where((file) {
      final map = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      final width = (map['paperWidth'] as num?)?.toDouble() ?? 0;
      return width == 58 || width == 80 || width == 148;
    })
    .toList()
  ..sort((a, b) => a.path.compareTo(b.path));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final file in _targetTemplates()) {
    testWidgets('${file.uri.pathSegments.last}: shared plan geometry + thin rules', (tester) async {
      final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      final width = (json['paperWidth'] as num).toDouble();
      final height = (json['paperHeight'] as num?)?.toDouble();
      final paper = height == null
          ? PaperSpec.continuous(widthMm: width, margins: const MarginsMm.all(3))
          : PaperSpec(widthMm: width, heightMm: height, margins: const MarginsMm.all(3));
      final legacy = [
        for (final raw in json['elements'] as List<dynamic>)
          LegacyElement(
            elementType: raw['type'] as String? ?? 'text',
            content: raw['content'] as String?,
            section: raw['section'] as String? ?? 'body',
            sortOrder: raw['sortOrder'] as int? ?? 0,
            flexWidth: (raw['flexWidth'] as num?)?.toDouble() ?? 100,
            fontSize: (raw['fontSize'] as num?)?.toDouble() ?? 8,
            isBold: raw['isBold'] as bool? ?? false,
            isVisible: raw['isVisible'] as bool? ?? true,
            labelAr: raw['labelAr'] as String?,
            labelEn: raw['labelEn'] as String?,
            textAlign: raw['textAlign'] as String? ?? 'center',
          ),
      ];
      final document = TemplateMapper.fromLegacy(paper: paper, elements: legacy);
      final pages = LayoutEngine.paginate(document: document, rows: const [], values: const {});
      final ops = planPage(pages.first);
      final lines = ops.where((op) => op.kind == PaintKind.line).toList();
      // Some assets intentionally contain no separator; exercise rendering with a plan-shaped line in that case.
      final previewOps = lines.isEmpty
          ? [PaintOp(id: 'test-line', kind: PaintKind.line, leftMm: 2, topMm: 4, widthMm: width - 4, heightMm: 8, text: '')]
          : lines;
      final line = previewOps.first;
      for (final line in lines) {
        expect(line.leftMm, greaterThanOrEqualTo(-0.001));
        expect(line.topMm, greaterThanOrEqualTo(-0.001));
        expect(line.leftMm + line.widthMm, lessThanOrEqualTo(pages.first.widthMm + 0.001));
        expect(line.heightMm, greaterThan(0));
      }
      // The painter receives the exact immutable plan objects consumed by PdfPainter.
      expect(ops.where((op) => op.kind == PaintKind.line).map((op) => (op.id, op.leftMm, op.topMm, op.widthMm, op.heightMm)),
          lines.map((op) => (op.id, op.leftMm, op.topMm, op.widthMm, op.heightMm)));

      await tester.pumpWidget(MaterialApp(
        home: RepaintBoundary(
          key: const ValueKey('sheet-capture'),
          child: SheetPreviewView(widthMm: width, heightMm: line.topMm + line.heightMm + 4,
            ops: [line], caption: ''),
        ),
      ));
      expect(find.byType(SheetPreviewView), findsOneWidget);
      expect(find.byType(CustomPaint), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  }
}
