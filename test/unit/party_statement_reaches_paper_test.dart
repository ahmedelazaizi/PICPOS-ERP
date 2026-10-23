// test/unit/party_statement_reaches_paper_test.dart
//
// كشفُ الحساب يصل الورقةَ من قالبه — امتدادُ `EXTENSION-SPEC.md` §٣.
//
// ── ما كان قبل هذا ───────────────────────────────────────────────────────
// الكشفُ يُطبع من مولّدٍ ثابتٍ في `report_pdf_generator.dart` **لا يقرأ جدولَ
// القوالب إطلاقاً**. وقالبا الكشف (`a4_customer_statement.json` و
// `a4_supplier_statement.json`) مكتوبان ومبذوران منذ حينها ولا يصلان ورقةً —
// «القالبُ جاهزٌ والمولِّدُ لا يقرأه».
//
// ── ولماذا يُقاس على الورقة لا على القيمة ────────────────────────────────
// المُحلِّلُ دالّةٌ خالصةٌ يسهل قياسُها، لكنّ العطبَ الذي يقع فعلاً ليس فيه:
// المفتاحُ يُحلّ صحيحاً ثمّ **يُخطَف** في `resolveContentValue` بـ
// `default: return ''`، أو يخرج جدولُ الحركة بأعمدة الفاتورة فيصير ستّةَ
// أعمدةٍ فارغة. ولا يُمسَك ذلك إلّا بقراءة المطبوع.
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/domain/printing/party_statement_snapshot.dart';
import 'package:picpos_erp/domain/printing/print_values.dart';
import 'package:picpos_erp/domain/printing/template_document.dart';
import 'package:picpos_erp/services/printing/layout_engine.dart';
import 'package:picpos_erp/services/printing/paint_plan.dart';
import 'package:picpos_erp/services/printing/template_render_pipeline.dart';

const _margins = MarginsMm(top: 10, right: 10, bottom: 10, left: 10);

PartyStatementSnapshot _snapshot({bool supplier = false}) =>
    PartyStatementSnapshot(
      partyName: 'سوبر ماركت النور',
      partyCode: 'C-1042',
      partyTaxNumber: '344-228-891',
      isSupplier: supplier,
      periodFrom: DateTime.utc(2026, 8, 1),
      periodTo: DateTime.utc(2026, 8, 31),
      creditLimit: 50000,
      openingBalance: 1200,
      closingBalance: 3450.75,
      totalDebit: 4250.75,
      totalCredit: 2000,
      overdueAmount: 900,
      outstandingPapers: 1500,
      ageingBuckets: const {'0-30': 1200.0, '31-60': 450.0},
      lines: [
        PartyStatementLine(
          date: DateTime.utc(2026, 8, 3),
          documentNumber: 'INV-2026-1040',
          description: 'فاتورة مبيعات',
          debit: 2500.50,
          credit: 0,
          runningBalance: 3700.50,
        ),
        PartyStatementLine(
          date: DateTime.utc(2026, 8, 12),
          documentNumber: 'RCV-2026-0088',
          description: 'سند قبض',
          debit: 0,
          credit: 2000,
          runningBalance: 1700.50,
        ),
        PartyStatementLine(
          date: DateTime.utc(2026, 8, 20),
          documentNumber: 'INV-2026-1077',
          description: 'فاتورة مبيعات',
          debit: 1750.25,
          credit: 0,
          runningBalance: 3450.75,
        ),
      ],
    );

/// مستندُ كشفٍ بنطاقاتٍ — يحمل الحقولَ التي يحملها القالبُ المبذور.
TemplateDocument _statementDocument() => const TemplateDocument(
      paper: PaperSpec(widthMm: 210, heightMm: 297, margins: _margins),
      bands: [
        TemplateBand(id: BandId.header, heightMm: 24, elements: [
          TemplateElement(
              id: 'h1', contentKey: 'company_name',
              xMm: 0, yMm: 2, wMm: 90, hMm: 8),
        ]),
        TemplateBand(id: BandId.party, heightMm: 30, elements: [
          TemplateElement(
              id: 'p1', contentKey: 'party_name',
              xMm: 0, yMm: 0, wMm: 90, hMm: 6),
          TemplateElement(
              id: 'p2', contentKey: 'party_code',
              xMm: 0, yMm: 7, wMm: 60, hMm: 6),
          TemplateElement(
              id: 'p3', contentKey: 'period_from',
              xMm: 100, yMm: 0, wMm: 60, hMm: 6),
          TemplateElement(
              id: 'p4', contentKey: 'period_to',
              xMm: 100, yMm: 7, wMm: 60, hMm: 6),
          TemplateElement(
              id: 'p5', contentKey: 'overdue_amount',
              xMm: 0, yMm: 14, wMm: 60, hMm: 6),
          TemplateElement(
              id: 'p6', contentKey: 'outstanding_papers',
              xMm: 100, yMm: 14, wMm: 60, hMm: 6),
          TemplateElement(
              id: 'p7', contentKey: 'ageing_buckets',
              xMm: 0, yMm: 21, wMm: 160, hMm: 6),
        ]),
        TemplateBand(id: BandId.details, heightMm: 120, growsWithData: true),
        TemplateBand(id: BandId.totals, heightMm: 30, elements: [
          TemplateElement(
              id: 't1', contentKey: 'opening_balance',
              xMm: 100, yMm: 0, wMm: 70, hMm: 6),
          TemplateElement(
              id: 't2', contentKey: 'total_debit',
              xMm: 100, yMm: 7, wMm: 70, hMm: 6),
          TemplateElement(
              id: 't3', contentKey: 'total_credit',
              xMm: 100, yMm: 14, wMm: 70, hMm: 6),
          TemplateElement(
              id: 't4', contentKey: 'closing_balance',
              xMm: 100, yMm: 21, wMm: 70, hMm: 8),
        ]),
      ],
      // جدولُ الحركة — بأعمدة `ledger` لا بأعمدة الفاتورة.
      table: TableSpec(kind: TableKind.ledger, columns: [
        TableColumn(key: 'date', labelAr: 'التاريخ', flex: 1.1, decimals: 0),
        TableColumn(
            key: 'document', labelAr: 'المستند', flex: 1.1, decimals: 0),
        TableColumn(
            key: 'description', labelAr: 'البيان', flex: 2.4, decimals: 0),
        TableColumn(key: 'debit', labelAr: 'مدين', flex: 1.1),
        TableColumn(key: 'credit', labelAr: 'دائن', flex: 1.1),
        TableColumn(key: 'balance', labelAr: 'الرصيد', flex: 1.2),
      ]),
    );

final _payload = PrintPayload(
  invoiceNumber: '',
  date: DateTime.utc(2026, 8, 31),
  companyName: 'شركة بيك بوس للتجارة',
  companyAddress: 'المعادي',
  companyPhone: '0100 000 0000',
  subtotal: 0,
  discount: 0,
  tax: 0,
  deliveryFee: 0,
  total: 0,
  paid: 0,
  remaining: 0,
);

/// صفُّ إعداداتِ جدولٍ كما يبذره `a4_customer_statement.json`: `tableKind`
/// «ledger» و`columnWidths` القديمةُ و**بلا** `columnsJson`.
InvoiceTableSetting _ledgerSettings({
  String kind = 'ledger',
  String? widths =
      '{"_decimalPlaces":2,"date":1.1,"document":1.1,"description":2.4,'
          '"debit":1.1,"credit":1.1,"balance":1.2}',
}) =>
    InvoiceTableSetting(
      id: 1,
      templateId: 1,
      xPosition: 20,
      yPosition: 280,
      width: 555,
      fontSize: 9.5,
      showIndex: true,
      showProductCode: false,
      showProductName: true,
      showQuantity: true,
      showUnitPrice: true,
      showDiscount: false,
      showTax: false,
      showTotal: true,
      showUnit: false,
      showBarcode: false,
      showNotes: false,
      headerBgColor: '#FFFFFF',
      headerTextColor: '#0B1220',
      headerFontSize: 9.5,
      rowBgColor: '#FFFFFF',
      rowHeight: 20,
      tableKind: kind,
      columnWidths: widths,
    );

List<PaintOp> _paint(PartyStatementSnapshot s) {
  final doc = _statementDocument();
  final pages = LayoutEngine.paginate(
    document: doc,
    rows: TemplateRenderPipeline.buildRows(s.rowMaps, doc.table, 2),
    values:
        TemplateRenderPipeline.buildValues(doc, _payload, statement: s),
  );
  return [for (final p in pages) ...planPage(p)];
}

String _allText(List<PaintOp> ops) => ops.map((o) => o.text).join(' | ');

void main() {
  group('المُحلِّلُ لا يخطف أنواعَ الفاتورة', () {
    test('يُرجع `null` لكلِّ ما ليس له', () {
      final s = _snapshot();
      for (final t in const [
        'company_name',
        'invoice_number',
        'total',
        'customer_name',
        'date',
      ]) {
        expect(resolvePartyStatementValue(t, s), isNull,
            reason: 'خطف «$t» فتخرج الورقةُ بلا شركةٍ ولا تاريخ');
      }
    });

    test('ويُرجع قيمةً لحقول الكشف', () {
      final s = _snapshot();
      expect(resolvePartyStatementValue('party_name', s), 'سوبر ماركت النور');
      expect(resolvePartyStatementValue('party_code', s), 'C-1042');
      expect(resolvePartyStatementValue('closing_balance', s), '3450.75');
      expect(resolvePartyStatementValue('period_from', s), '1/8/2026');
    });

    test('والحقلان المتبادلان يتبعان نوعَ الطرف', () {
      final customer = _snapshot();
      final supplier = _snapshot(supplier: true);

      expect(resolvePartyStatementValue('overdue_amount', customer), '900.00');
      expect(resolvePartyStatementValue('outstanding_papers', customer), isNull,
          reason: 'كشفُ عميلٍ لا يطبع «أوراقٌ قائمة»');

      expect(resolvePartyStatementValue('overdue_amount', supplier), isNull,
          reason: 'كشفُ موردٍ لا يطبع «متأخّرات: 0.00»');
      expect(
          resolvePartyStatementValue('outstanding_papers', supplier), '1500.00');
    });

    test('والمنازلُ تتبع المستندَ لا العنصر', () {
      final s = _snapshot();
      expect(resolvePartyStatementValue('closing_balance', s, decimals: 0),
          '3451');
    });
  });

  group('الكشفُ يبلغ الورقةَ', () {
    test('حقولُ الطرف والفترةُ والأرصدةُ كلُّها مطبوعة', () {
      final text = _allText(_paint(_snapshot()));

      for (final expected in const [
        'سوبر ماركت النور',
        'C-1042',
        '1/8/2026',
        '31/8/2026',
        '1200.00', // الرصيدُ الافتتاحيّ
        '4250.75', // مجموعُ المدين
        '2000.00', // مجموعُ الدائن
        '3450.75', // الرصيدُ الختاميّ
      ]) {
        expect(text, contains(expected), reason: '«$expected» لم يصل الورقة');
      }
    });

    test('وحقلُ الفاتورة يبقى يعمل — المُحلِّلُ لم يخطفه', () {
      expect(_allText(_paint(_snapshot())),
          contains('شركة بيك بوس للتجارة'));
    });

    test('وأعمارُ الدين تُنسَّق سطراً واحداً', () {
      expect(_allText(_paint(_snapshot())), contains('0-30: 1200.00'));
    });

    test('وكشفُ المورد لا يحمل «المتأخّرات»', () {
      // ‏٩٠٠ قيمةُ `overdueAmount` وحدَها في هذه التجهيزة، فغيابُها دليلٌ
      // على أنّ العنصرَ طُوي لا أنّه طُبع فارغاً.
      final supplier = _allText(_paint(_snapshot(supplier: true)));
      expect(supplier, contains('1500.00'), reason: 'الأوراقُ القائمة');
      expect(supplier, isNot(contains('900.00')));
    });
  });

  group('جدولُ الحركة أعمدتُه أعمدةُ كشفٍ لا أعمدةُ فاتورة', () {
    test('الرؤوسُ الستّةُ على الورقة', () {
      final ops = _paint(_snapshot());
      final headers = ops
          .where((o) => o.kind == PaintKind.tableHeader)
          .map((o) => o.text)
          .toList();

      expect(headers, hasLength(6));
      expect(headers, containsAll(
          ['التاريخ', 'المستند', 'البيان', 'مدين', 'دائن', 'الرصيد']));
      expect(headers, isNot(contains('الصنف')),
          reason: 'أعمدةُ الفاتورة تسرّبت إلى الكشف');
    });

    test('وثلاثةُ صفوفٍ بقيمها — لا خلايا فارغة', () {
      final cells = _paint(_snapshot())
          .where((o) => o.kind == PaintKind.tableCell)
          .map((o) => o.text)
          .toList();

      expect(cells, hasLength(18), reason: '٣ صفوفٍ × ٦ أعمدة');
      expect(cells.where((c) => c.trim().isEmpty), isEmpty,
          reason: 'خليّةٌ فارغةٌ تعني مفتاحاً في العمود لا يقابله مفتاحٌ في '
              'الصفّ — وهو صامتٌ تماماً');

      final joined = cells.join(' ');
      expect(joined, contains('INV-2026-1040'));
      expect(joined, contains('سند قبض'));
      expect(joined, contains('2500.50'));
    });

    test('والرصيدُ الجاري آخرُه هو الرصيدُ الختاميُّ — لا مجموعُ الأرصدة', () {
      // ⚠️ مجموعُ الأرصدة التراكميّة (‏٨٨٥١٫٧٥) رقمٌ بلا معنى، ولا يجوز أن
      //    يظهر على الورقة. والختاميُّ هو قيمةُ آخر سطر.
      final s = _snapshot();
      expect(s.lines.last.runningBalance, s.closingBalance);

      final text = _allText(_paint(s));
      final wrongSum = s.lines
          .fold<double>(0, (a, l) => a + l.runningBalance)
          .toStringAsFixed(2);
      expect(text, isNot(contains(wrongSum)),
          reason: 'مجموعُ الأرصدة التراكميّة طُبع — وهو رقمٌ بلا معنى');
    });
  });

  group('القالبُ المبذورُ بلا `columnsJson` يأخذ أعمدةَ الحركة', () {
    // ⚠️ **هذا هو العطبُ الذي كان يُخرج الجدولَ فارغاً**: `a4_customer_statement.json`
    //    لا يحمل `columnsJson` — يحمل `columnWidths` و`showDate`/`showDebit`
    //    وهي ليست أعمدةً في الجدول. فكان القالبُ يرث أعلامَ `show*` الخاصّةَ
    //    بالفاتورة، فيخرج بستّةِ أعمدةٍ لا يقابل أيٌّ منها مفتاحاً في صفوف
    //    الحركة — ورقةٌ بجدولٍ كاملِ الإطار فارغِ الخلايا.
    const paper = PaperSpec(widthMm: 210, heightMm: 297, margins: _margins);

    test('`tableKind: ledger` وحدَه يكفي', () {
      final table = TemplateRenderPipeline.buildTable(
        _ledgerSettings(),
        paper,
      );

      expect(table, isNotNull);
      expect(table!.kind, TableKind.ledger);
      expect(table.columns.map((c) => c.key).toList(), ledgerColumnKeys,
          reason: 'الأعمدةُ ليست أعمدةَ حركة — الجدولُ سيخرج فارغاً');
    });

    test('والعرضُ النسبيُّ يُقرأ من `columnWidths` القديم', () {
      final table =
          TemplateRenderPipeline.buildTable(_ledgerSettings(), paper)!;
      expect(table.columns.firstWhere((c) => c.key == 'description').flex, 2.4);
      expect(table.columns.firstWhere((c) => c.key == 'date').flex, 1.1);
    });

    test('و`columnWidths` معطوبةٌ لا تُسقط الأعمدة', () {
      final table = TemplateRenderPipeline.buildTable(
        _ledgerSettings(widths: 'ليست JSON'),
        paper,
      )!;
      expect(table.columns.map((c) => c.key).toList(), ledgerColumnKeys);
    });

    test('وقالبُ فاتورةٍ لا يتأثّر — يبقى على أعلام `show*`', () {
      final table = TemplateRenderPipeline.buildTable(
        _ledgerSettings(kind: 'items'),
        paper,
      )!;
      expect(table.columns.map((c) => c.key), contains('name'),
          reason: 'أعمدةُ الحركة تسرّبت إلى الفاتورة');
      expect(table.columns.map((c) => c.key), isNot(contains('debit')));
    });
  });

  group('ضابط: القياسُ يمرّ بالورقة فعلاً', () {
    test('الرسمُ يُنتج عمليّاتٍ ورؤوساً وخلايا', () {
      final ops = _paint(_snapshot());
      expect(ops, isNotEmpty);
      expect(ops.where((o) => o.kind == PaintKind.tableHeader), isNotEmpty);
      expect(ops.where((o) => o.kind == PaintKind.tableCell), isNotEmpty);
    });
  });
}
