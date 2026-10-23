import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/presentation/picpos_shell/picpos_data_table.dart';
import 'package:picpos_erp/presentation/picpos_shell/picpos_filter_strip.dart';
import 'package:picpos_erp/core/theme/picpos_theme.dart';

double _contrast(Color first, Color second) {
  final a = first.computeLuminance();
  final b = second.computeLuminance();
  final high = a > b ? a : b;
  final low = a > b ? b : a;
  return (high + 0.05) / (low + 0.05);
}

void main() {
  testWidgets(
    'dark report table secondary cell remains readable beside filters',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: PicPosTheme.darkTheme,
          home: const Scaffold(
            body: SizedBox(
              width: 900,
              child: Column(
                children: [
                  PicPosFilterStrip(
                    children: [
                      PicPosFilterPill(
                        icon: Icons.filter_alt_outlined,
                        label: 'المستودع',
                      ),
                    ],
                  ),
                  PicPosDataTable(
                    title: 'حركة المخزون',
                    columns: [PicPosTableColumn('الصنف')],
                    rows: [
                      PicPosTableRow(
                        cells: [PicPosTextCell('صنف', sub: 'مرجع صغير')],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final paragraph = tester.renderObject<RenderParagraph>(
        find.text('مرجع صغير'),
      );
      final ink = paragraph.text.style!.color!;
      final surface = PicPosTheme.darkTheme.cardColor;
      expect(_contrast(ink, surface), greaterThanOrEqualTo(4.5));
    },
  );
}
