// «إدارة الشيكات» — مرشِّحُ النوع · اختيارٌ مفردٌ · وسندُ الورقة.
//
// ═══ قراراتُ المالك 2026-09-18 المقيسةُ هنا ═══
//
// ‏• **مرشِّحُ نوعٍ يُظهر الكمبيالةَ وسندَ السحب.** النوعان معروفان في الكود
//   منذ زمن (`_typeLabels`) ويُعرضان سطراً خافتاً تحت رقم الورقة، **ولا
//   سبيلَ لعزلهما** — فمن عنده كمبيالاتٌ يقلّب الصفحاتِ كلَّها ليجدها.
// ‏• **اختيارٌ مفردٌ بزرّ راديو**، والإيداعُ الجماعيُّ يبقى زرّاً منفصلاً في
//   الرأس. والشكلُ عقدٌ: المربّعُ يَعِد بتعدّدٍ، والدائرةُ تقول «واحدٌ فقط».
// ‏• **وسندُ الورقة** يُقرأ من `sourceVoucherId` — عمودٌ مشحونٌ منذ v174 كان
//   بلا كاتبٍ ولا قارئ.
//
// ⚠️ **و«—» ليست عطباً**: ورقةٌ أُنشئت يدويّاً لا سندَ لها، وكذلك ورقةٌ
// أقدمُ من العمود، وكذلك وضعُ العميل (الكتابةُ على الخادم فلا معرّفَ
// محلّيّ). والزرُّ يتبع **وجودَ السند** لا وجودَ الورقة: زرٌّ يُعرَض ولا
// يقفز أسوأُ من غيابه.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/core/navigation/screen_id.dart';
import 'package:ural_erp/data/providers/providers.dart';
import 'package:ural_erp/domain/repositories/commercial_papers_repository.dart'
    show ICommercialPapersRepository;
import 'package:ural_erp/presentation/settings_picpos/screens/cheques_picpos_screen.dart';

CommercialPaperData _paper(
  int id,
  String number, {
  String direction = 'received',
  String status = 'pending',
  String type = 'cheque',
  int? sourceVoucherId,
}) =>
    CommercialPaperData(
      id: id,
      paperNumber: number,
      type: type,
      direction: direction,
      partyId: 5,
      amount: 1000,
      issueDate: DateTime(2026, 9, 1),
      dueDate: DateTime.now().add(const Duration(days: 20)),
      status: status,
      sourceVoucherId: sourceVoucherId,
      createdAt: DateTime(2026, 9, 1),
      rowVersion: 0,
    );

class _FakeRepo implements ICommercialPapersRepository {
  _FakeRepo(this.papers);
  final List<CommercialPaperData> papers;

  @override
  Stream<List<CommercialPaperData>> watchCommercialPapers({
    String? direction,
    String? status,
  }) =>
      Stream.value(papers);

  @override
  Stream<List<PaperStatusHistoryData>> watchPaperHistory(int paperId) =>
      Stream.value(const []);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeTreasury implements ITreasuryRepository {
  _FakeTreasury(this.numbers);

  /// معرّفُ السند ← رقمُه. وما ليس فيها يُقرأ «لا صفَّ بعد».
  final Map<int, String> numbers;

  @override
  Future<String?> getVoucherNumberById(int id) async => numbers[id];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  Future<List<String>> pump(
    WidgetTester tester,
    double width, {
    required List<CommercialPaperData> papers,
    Map<int, String> vouchers = const {},
  }) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final errors = <String>[];
    final previous = FlutterError.onError;
    FlutterError.onError = (d) => errors.add(d.exceptionAsString());
    try {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            commercialPapersRepositoryProvider
                .overrideWithValue(_FakeRepo(papers)),
            treasuryRepositoryProvider
                .overrideWithValue(_FakeTreasury(vouchers)),
            allPartiesProvider
                .overrideWith((ref) => Stream.value(const <Party>[])),
          ],
          child: const MaterialApp(home: ChequesPicposScreen()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
    } finally {
      FlutterError.onError = previous;
    }
    return errors;
  }

  Future<void> teardown(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  }

  final mixed = [
    _paper(1, 'CH-001', sourceVoucherId: 77),
    _paper(2, 'CH-002'),
    _paper(3, 'PN-010', type: 'promissory_note'),
    _paper(4, 'BE-020', type: 'bill_of_exchange'),
  ];

  testWidgets('الاسمُ «إدارة الشيكات» لا «الشيكات والأوراق التجارية»',
      (tester) async {
    await pump(tester, 1500, papers: mixed);
    expect(find.text(chequesScreenLabel), findsOneWidget);
    expect(find.text('الشيكات والأوراق التجارية'), findsNothing);
    await teardown(tester);
  });

  group('🔴 مرشِّحُ النوع يعزل الكمبيالةَ وسندَ السحب', () {
    testWidgets('الشرائحُ الأربعُ معروضةٌ بعدّاداتها', (tester) async {
      final errors = await pump(tester, 1500, papers: mixed);
      expect(find.textContaining('كمبيالة'), findsWidgets,
          reason: 'النوعُ لا سبيلَ لعزله — وهو معروفٌ في الكود منذ زمن');
      expect(find.textContaining('سند سحب'), findsWidgets);
      expect(errors, isEmpty, reason: 'عطبُ تخطيط: $errors');
      await teardown(tester);
    });

    testWidgets('🔴 واختيارُ «كمبيالة» يُخفي الشيكات', (tester) async {
      await pump(tester, 1500, papers: mixed);
      expect(find.text('CH-001'), findsWidgets, reason: 'خطُّ الأساس');

      await tester.tap(find.textContaining('كمبيالة').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('PN-010'), findsWidgets);
      expect(find.text('CH-001'), findsNothing,
          reason: 'المرشِّحُ لا يُرشِّح — وشريحةٌ لا تفعل تكذب كزرٍّ لا يعمل');
      await teardown(tester);
    });
  });

  group('والاختيارُ مفردٌ — وشريطُه يتبع المختار', () {
    testWidgets('لا شريطَ قبل اختيارِ شيء', (tester) async {
      await pump(tester, 1500, papers: mixed);
      expect(find.text('عرض السند'), findsNothing);
      expect(find.text('إيداع للتحصيل'), findsNothing);
      await teardown(tester);
    });

    testWidgets('🔴 واختيارُ ورقةٍ يُظهر رقمَ سندها وزرَّ فتحه',
        (tester) async {
      final errors = await pump(tester, 1500,
          papers: mixed, vouchers: const {77: 'RCPT-51'});

      await tester.tap(find.text('CH-001').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('RCPT-51'), findsOneWidget,
          reason: 'السندُ لا يُقرأ — والعمودُ كان بلا قارئ');
      expect(find.text('عرض السند'), findsOneWidget);
      expect(find.text('سند القبض'), findsOneWidget);
      expect(errors, isEmpty, reason: 'عطبُ تخطيط: $errors');
      await teardown(tester);
    });

    testWidgets('🔴 وورقةٌ بلا سندٍ: «—» ولا زرَّ يقفز إلى لا شيء',
        (tester) async {
      await pump(tester, 1500, papers: mixed);

      await tester.tap(find.text('CH-002').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('—'), findsWidgets, reason: 'غيابُ السند لا يُقال');
      expect(find.text('عرض السند'), findsNothing,
          reason: 'زرٌّ يُعرَض ولا يقفز — أسوأُ من غيابه');
      // والإيداعُ يبقى: الورقةُ `pending` فهي مؤهَّلة.
      expect(find.text('إيداع للتحصيل'), findsOneWidget);
      await teardown(tester);
    });

    testWidgets('🔴 واختيارُ ورقةٍ ثانيةٍ يستبدل الأولى لا يضيف إليها',
        (tester) async {
      await pump(tester, 1500,
          papers: mixed, vouchers: const {77: 'RCPT-51'});

      await tester.tap(find.text('CH-001').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('RCPT-51'), findsOneWidget);

      await tester.tap(find.text('CH-002').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('RCPT-51'), findsNothing,
          reason: 'الشريطُ ما زال يعرض الورقةَ الأولى — فالاختيارُ متعدّدٌ '
              'وشريطُ إجراءاتٍ يعمل على ورقةٍ غيرِ التي يراها المستخدم');
      await teardown(tester);
    });

    testWidgets('والنقرةُ الثانيةُ على نفس الورقة تُلغي الاختيار',
        (tester) async {
      // بلا هذا يبقى الشريطُ مفتوحاً بلا سبيلٍ لإغلاقه.
      await pump(tester, 1500,
          papers: mixed, vouchers: const {77: 'RCPT-51'});

      await tester.tap(find.text('CH-001').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('عرض السند'), findsOneWidget);

      await tester.tap(find.text('CH-001').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('عرض السند'), findsNothing);
      await teardown(tester);
    });

    testWidgets('🔴 والاختيارُ يسقط حين يُخفيه الترشيح', (tester) async {
      // ورقةٌ اختيرت ثمّ أُخفيت تترك شريطاً يعمل على ما لا يُرى.
      await pump(tester, 1500,
          papers: mixed, vouchers: const {77: 'RCPT-51'});

      await tester.tap(find.text('CH-001').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('عرض السند'), findsOneWidget);

      await tester.tap(find.textContaining('كمبيالة').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('عرض السند'), findsNothing,
          reason: 'شريطُ الإجراءات يعمل على ورقةٍ لم تعد معروضة');
      await teardown(tester);
    });
  });

  // ⚠️ **وزرُّ «إيداع دفعة شيكات» لا يُقاس هنا**: يلفّه `PermissionGuard`
  //    فلا يُرسَم بلا مستخدمٍ مُصرَّح، وتجهيزةُ الصلاحيّات أثقلُ ممّا يقيسه
  //    هذا الملفّ. بقاؤه منفصلاً محروسٌ في
  //    `test/structural/cheques_screen_is_named_and_selectable_test.dart`.

  testWidgets('ومرساةُ تركيبٍ — عرضٌ ضيّقٌ بلا فيض', (tester) async {
    final errors = await pump(tester, 820, papers: mixed);
    expect(errors, isEmpty, reason: 'عطبُ تخطيطٍ عند ٨٢٠: $errors');
    await teardown(tester);
  });
}
