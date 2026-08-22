// لوحُ المرتجعات المشترك — يستعمله توأما المبيعات والمشتريات معاً، فأيُّ
// انحرافٍ فيه يكسر شاشتَين لا واحدة.
//
// ما يُقاس:
//  ‏١) الصفُّ يعرض الرقمَ والتفاصيلَ والإجماليَّ وشارةَ الحالة.
//  ‏٢) النقرُ يُبلِّغ **بالصفِّ الصحيح** — لا بفهرسٍ أزاحه الترشيح.
//  ‏٣) المنتقاةُ تتميّز فعلاً (لا بلونٍ وحدَه: `Semantics.selected`).
//  ‏٤) **لا فيضانَ** عند عرضِ ٣٠٠ — عمودُ القائمة يضيق على لوحٍ صغير.
//  ‏٥) الفراغُ يعرض رسالتَه لا شبكةً عمياء.
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsFlag;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/domain/models/picpos_return_view.dart';
import 'package:ural_erp/presentation/picpos_shell/picpos_returns_panel.dart';

PicPosReturnInvoiceRow _row({
  int id = 1,
  String number = '# INV-1',
  DateTime? date,
  double total = 100,
  PicPosReturnStatus status = PicPosReturnStatus.completed,
  String? partyName,
}) =>
    PicPosReturnInvoiceRow(
      id: id,
      number: number,
      date: date ?? DateTime(2026, 8, 18),
      total: total,
      status: status,
      partyName: partyName,
    );

void main() {
  Future<void> show(
    WidgetTester tester,
    Widget child, {
    Size size = const Size(1000, 800),
    // ‏`pumpAndSettle` **لا تستقرّ أبداً** مع دوّارةٍ لا نهائيّة، فتتوقّف
    // الاختباراتُ بمهلة. حالةُ التحميل تُضخّ إطاراً واحداً فقط.
    bool settle = true,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Directionality(
            textDirection: TextDirection.rtl,
            child: child,
          ),
        ),
      ),
    );
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
  }

  group('PicPosReturnInvoiceTile', () {
    testWidgets('يعرض الرقمَ والتفاصيلَ والإجماليَّ والحالة', (tester) async {
      await show(
        tester,
        SizedBox(
          width: 400,
          child: PicPosReturnInvoiceTile(
            row: _row(
              number: '# INV-0842',
              partyName: 'أحمد سولا',
              total: 250,
              status: PicPosReturnStatus.partialReturn,
            ),
            selected: false,
            onTap: () {},
          ),
        ),
      );
      expect(find.text('# INV-0842'), findsOneWidget);
      expect(find.text('أحمد سولا · 18/8'), findsOneWidget);
      expect(find.text('مرتجع جزئي'), findsOneWidget);
    });

    testWidgets('بلا اسمِ طرفٍ يعرض التاريخَ وحدَه', (tester) async {
      await show(
        tester,
        SizedBox(
          width: 400,
          child: PicPosReturnInvoiceTile(
            row: _row(date: DateTime(2026, 8, 21)),
            selected: false,
            onTap: () {},
          ),
        ),
      );
      expect(find.text('21/8'), findsOneWidget);
    });

    testWidgets('المنتقاةُ تُعلَن منتقاةً لقارئ الشاشة لا بلونٍ وحدَه',
        (tester) async {
      // ‏`addTearDown(handle.dispose)` **لا يكفي**: تحقُّقُ الإطار من
      // المقابض يقع في جسم الاختبار قبل تشغيل الـtearDowns، فيسقط الاختبارُ
      // بـ«‏SemanticsHandle was active». فالتخلّصُ صريحٌ في النهاية.
      final handle = tester.ensureSemantics();
      await show(
        tester,
        SizedBox(
          width: 400,
          child: PicPosReturnInvoiceTile(
            row: _row(),
            selected: true,
            onTap: () {},
          ),
        ),
      );
      // النصُّ المجمَّعُ في العقدة تفصيلُ تنفيذٍ يتغيّر مع أيّ إعادةِ ترتيب؛
      // المقيسُ هو **علَمُ الانتقاء** نفسُه — وهو ما يقرؤه قارئُ الشاشة.
      final node =
          tester.getSemantics(find.byType(PicPosReturnInvoiceTile).first);
      expect(node.hasFlag(SemanticsFlag.hasSelectedState), isTrue);
      expect(node.hasFlag(SemanticsFlag.isSelected), isTrue);
      handle.dispose();
    });

    testWidgets('غيرُ المنتقاةِ تُعلَن غيرَ منتقاة', (tester) async {
      final handle = tester.ensureSemantics();
      await show(
        tester,
        SizedBox(
          width: 400,
          child: PicPosReturnInvoiceTile(
            row: _row(),
            selected: false,
            onTap: () {},
          ),
        ),
      );
      final node =
          tester.getSemantics(find.byType(PicPosReturnInvoiceTile).first);
      expect(node.hasFlag(SemanticsFlag.hasSelectedState), isTrue);
      expect(node.hasFlag(SemanticsFlag.isSelected), isFalse);
      handle.dispose();
    });

    testWidgets('لا يفيض عند عرضٍ ضيّقٍ مع نصوصٍ طويلة', (tester) async {
      await show(
        tester,
        SizedBox(
          width: 300,
          child: PicPosReturnInvoiceTile(
            row: _row(
              number: '# PUR-2026-000000842-REV-3',
              partyName: 'مؤسسة النور التجارية للمواد الغذائية والاستيراد',
              total: 9876543.21,
              status: PicPosReturnStatus.partialReturn,
            ),
            selected: true,
            onTap: () {},
          ),
        ),
      );
      expect(tester.takeException(), isNull,
          reason: 'الصفُّ يقصُّ بالحذف لا يفيض بالشريط الأصفر');
    });
  });

  group('PicPosReturnsInvoicePanel', () {
    testWidgets('يعرض الرأسَ وعدّادَ الصفوف', (tester) async {
      await show(
        tester,
        SizedBox(
          width: 420,
          height: 600,
          child: PicPosReturnsInvoicePanel(
            rows: [for (var i = 1; i <= 7; i++) _row(id: i, number: '# I$i')],
            selectedId: null,
            onSelect: (_) {},
            filters: const SizedBox.shrink(),
          ),
        ),
      );
      expect(find.text('الفواتير'), findsOneWidget);
      expect(find.text('7'), findsOneWidget);
    });

    // ⚠️ النقرُ يُبلِّغ بالصفِّ **بمعرّفه**. لو مُرِّر فهرسٌ بدل معرّفٍ لاختير
    // صفٌّ آخرُ متى أزاح الترشيحُ الفهارسَ — وهو عطبٌ صامتٌ في شاشةٍ ماليّة.
    testWidgets('النقرُ يُبلِّغ بالصفِّ المنقور لا بغيره', (tester) async {
      PicPosReturnInvoiceRow? picked;
      await show(
        tester,
        SizedBox(
          width: 420,
          height: 600,
          child: PicPosReturnsInvoicePanel(
            rows: [
              _row(id: 11, number: '# A'),
              _row(id: 22, number: '# B'),
              _row(id: 33, number: '# C'),
            ],
            selectedId: null,
            onSelect: (r) => picked = r,
            filters: const SizedBox.shrink(),
          ),
        ),
      );
      await tester.tap(find.text('# B'));
      await tester.pumpAndSettle();
      expect(picked?.id, 22);
    });

    testWidgets('الفراغُ يعرض رسالتَه', (tester) async {
      await show(
        tester,
        const SizedBox(
          width: 420,
          height: 600,
          child: PicPosReturnsInvoicePanel(
            rows: [],
            selectedId: null,
            onSelect: _noop,
            filters: SizedBox.shrink(),
            emptyMessage: 'لا توجد فواتير مشتريات في هذه الفترة',
          ),
        ),
      );
      expect(find.text('لا توجد فواتير مشتريات في هذه الفترة'), findsOneWidget);
    });

    testWidgets('التحميلُ مع قائمةٍ فارغةٍ يعرض دوّارةً لا فراغاً',
        (tester) async {
      await show(
        tester,
        const SizedBox(
          width: 420,
          height: 600,
          child: PicPosReturnsInvoicePanel(
            rows: [],
            selectedId: null,
            onSelect: _noop,
            filters: SizedBox.shrink(),
            isLoading: true,
          ),
        ),
        settle: false,
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('شريطُ الترشيح المُمرَّرُ يُرسم داخل اللوح', (tester) async {
      await show(
        tester,
        SizedBox(
          width: 420,
          height: 600,
          child: PicPosReturnsInvoicePanel(
            rows: [_row()],
            selectedId: null,
            onSelect: (_) {},
            filters: const Text('شريطٌ مُمرَّر'),
          ),
        ),
      );
      expect(find.text('شريطٌ مُمرَّر'), findsOneWidget);
    });

    testWidgets('لوحٌ ضيّقٌ لا يفيض', (tester) async {
      await show(
        tester,
        SizedBox(
          width: 300,
          height: 500,
          child: PicPosReturnsInvoicePanel(
            rows: [
              for (var i = 1; i <= 4; i++)
                _row(
                  id: i,
                  number: '# PUR-2026-00084$i',
                  partyName: 'مؤسسة النور التجارية للمواد الغذائية',
                  total: 9876543.21,
                ),
            ],
            selectedId: 2,
            onSelect: (_) {},
            filters: const SizedBox.shrink(),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('PicPosReturnsSummaryCards', () {
    testWidgets('تعرض العدّاداتِ الأربعةَ بقيمها', (tester) async {
      await show(
        tester,
        const PicPosReturnsSummaryCards(
          isSales: true,
          kpis: PicPosReturnKpis(
            invoiceCount: 42,
            invoicesTotal: 1500,
            fullyReturned: 3,
            partiallyReturned: 7,
          ),
        ),
      );
      expect(find.text('فواتير الفترة'), findsOneWidget);
      expect(find.text('42'), findsOneWidget);
      expect(find.text('مرتجعة كليّاً'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      expect(find.text('مرتجعة جزئيّاً'), findsOneWidget);
      expect(find.text('7'), findsOneWidget);
    });

    testWidgets('على عرضٍ ضيّقٍ تنهار إلى عمودَين ولا تفيض', (tester) async {
      await show(
        tester,
        const PicPosReturnsSummaryCards(
          isSales: false,
          kpis: PicPosReturnKpis(
            invoiceCount: 999999,
            invoicesTotal: 987654321.123,
            fullyReturned: 12345,
            partiallyReturned: 6789,
          ),
        ),
        size: const Size(620, 800),
      );
      expect(tester.takeException(), isNull);
    });
  });
}

void _noop(PicPosReturnInvoiceRow _) {}
