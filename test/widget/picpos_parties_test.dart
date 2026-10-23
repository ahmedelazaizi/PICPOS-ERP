// شاشةُ «العملاء والموردين» بهويّة PicPos — مكوّناتُها الثلاثةُ تُختبَر
// **بلا قاعدةٍ ولا مزوِّد**: كلُّها تستقبل [PicPosPartyCard] الخالص، والتحويلُ
// من `Party` يقع في الشاشة وحدَها.
//
// ما يُقاس هنا:
//  ‏١) البطاقةُ تعرض ما أُعطيت — ولا تعرض بانرَ التجاوز إلّا حين يقع فعلاً.
//  ‏٢) الإجراءاتُ الأربعةُ كلُّها موصولةٌ — بما فيها الاثنان تحت النقاط
//     الثلاث. (‏زرٌّ يُنقَر بلا أثرٍ كان عطبَ الجلسة السابقة الحقيقيّ.)
//  ‏٣) **لا فيضانَ تخطيطٍ** عند الضيق: الفيضُ لا يُسقط اختباراً إلّا إن فُحص
//     صراحةً بـ`tester.takeException`.
//  ‏٤) الشريطُ ينتقي ترشيحاً واحداً ويُبلِّغ به.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:picpos_erp/domain/models/picpos_party_view.dart';
import 'package:picpos_erp/presentation/parties_picpos/screens/parties_picpos_screen.dart';

PicPosPartyCard _card({
  int id = 1,
  String name = 'أحمد سولا',
  double balance = 120,
  double creditLimit = 0,
  String? phone = '0790123456',
  String? address = 'عمّان',
  bool isCustomer = true,
  bool isSupplier = false,
  bool isDeliveryCompany = false,
}) =>
    PicPosPartyCard(
      id: id,
      name: name,
      balance: balance,
      creditLimit: creditLimit,
      phone: phone,
      address: address,
      isCustomer: isCustomer,
      isSupplier: isSupplier,
      isDeliveryCompany: isDeliveryCompany,
    );

void main() {
  Future<void> show(
    WidgetTester tester,
    Widget child, {
    Size size = const Size(1400, 900),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: Directionality(
          textDirection: TextDirection.rtl,
          child: child,
        )),
      ),
    );
    await tester.pumpAndSettle();
  }

  PartyCardActions recordingActions(List<String> log) => PartyCardActions(
        onStatement: (c) => log.add('statement:${c.id}'),
        onEdit: (c) => log.add('edit:${c.id}'),
        onVoucher: (c) => log.add('voucher:${c.id}'),
        onDelete: (c) => log.add('delete:${c.id}'),
        onWhatsApp: (c) => log.add('whatsapp:${c.id}'),
      );

  group('PartyCard — العرض', () {
    testWidgets('يعرض الاسمَ والتفاصيلَ والشارةَ والرصيد', (tester) async {
      await show(
        tester,
        SizedBox(
          width: 360,
          child: PartyCard(
            party: _card(name: 'شركة الأمل', balance: 250),
            actions: recordingActions([]),
          ),
        ),
      );

      expect(find.text('شركة الأمل'), findsOneWidget);
      expect(find.text('0790123456 · عمّان'), findsOneWidget);
      expect(find.text('عميل'), findsOneWidget);
      expect(find.text('الرصيد'), findsOneWidget);
      expect(find.text('بلا حدّ ائتمان'), findsOneWidget);
    });

    testWidgets('الأحرفُ الأولى تظهر بدل الصورة', (tester) async {
      await show(
        tester,
        SizedBox(
          width: 360,
          child: PartyCard(
            party: _card(name: 'أحمد سولا'),
            actions: recordingActions([]),
          ),
        ),
      );
      expect(find.text('أس'), findsOneWidget);
    });

    testWidgets('بانرُ التجاوز يغيب حين لا تجاوز', (tester) async {
      await show(
        tester,
        SizedBox(
          width: 360,
          child: PartyCard(
            party: _card(balance: 50, creditLimit: 100),
            actions: recordingActions([]),
          ),
        ),
      );
      expect(find.text('تجاوز حد الائتمان'), findsNothing);
    });

    testWidgets('بانرُ التجاوز يظهر حين يقع التجاوزُ فعلاً', (tester) async {
      await show(
        tester,
        SizedBox(
          width: 360,
          child: PartyCard(
            party: _card(balance: 500, creditLimit: 100),
            actions: recordingActions([]),
          ),
        ),
      );
      expect(find.text('تجاوز حد الائتمان'), findsOneWidget);
      expect(find.text('حد 100'), findsOneWidget);
    });

    // ⚠️ الحدُّ الصفريُّ = بلا حدّ. لولا هذا لظهر البانرُ على كلّ طرفٍ عليه
    // مبلغٌ مهما صغُر — وهو أسوأُ من غيابه: تحذيرٌ دائمٌ لا يُقرَأ.
    testWidgets('حدٌّ صفريٌّ لا يُظهر البانرَ مهما كبُر الرصيد',
        (tester) async {
      await show(
        tester,
        SizedBox(
          width: 360,
          child: PartyCard(
            party: _card(balance: 999999, creditLimit: 0),
            actions: recordingActions([]),
          ),
        ),
      );
      expect(find.text('تجاوز حد الائتمان'), findsNothing);
    });
  });

  group('PartyCard — الإجراءات', () {
    testWidgets('«كشف حساب» يُنادى بالطرف الصحيح', (tester) async {
      final log = <String>[];
      await show(
        tester,
        SizedBox(
          width: 360,
          child: PartyCard(
            party: _card(id: 42),
            actions: recordingActions(log),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('party-statement')));
      await tester.pumpAndSettle();
      expect(log, ['statement:42']);
    });

    testWidgets('«تعديل» يُنادى بالطرف الصحيح', (tester) async {
      final log = <String>[];
      await show(
        tester,
        SizedBox(
          width: 360,
          child: PartyCard(
            party: _card(id: 7),
            actions: recordingActions(log),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('party-edit')));
      await tester.pumpAndSettle();
      expect(log, ['edit:7']);
    });

    // الإجراءان اللذان انتقلا تحت النقاط الثلاث. لولا هذا الفحصُ لكان
    // «اختصارُ» الصفِّ قد أسقط قدرتَين قائمتَين بصمت.
    testWidgets('«سند مالي» تحت النقاط الثلاث موصولٌ', (tester) async {
      final log = <String>[];
      await show(
        tester,
        SizedBox(
          width: 360,
          child: PartyCard(
            party: _card(id: 5),
            actions: recordingActions(log),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('party-more')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('سند مالي'));
      await tester.pumpAndSettle();
      expect(log, ['voucher:5']);
    });

    testWidgets('«حذف» تحت النقاط الثلاث موصولٌ', (tester) async {
      final log = <String>[];
      await show(
        tester,
        SizedBox(
          width: 360,
          child: PartyCard(
            party: _card(id: 9),
            actions: recordingActions(log),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('party-more')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('حذف'));
      await tester.pumpAndSettle();
      expect(log, ['delete:9']);
    });
  });

  group('لا فيضانَ تخطيط', () {
    testWidgets('بطاقةٌ ضيّقةٌ باسمٍ طويلٍ وبانرِ تجاوزٍ لا تفيض',
        (tester) async {
      await show(
        tester,
        SizedBox(
          width: 240,
          child: PartyCard(
            party: _card(
              name: 'مؤسسة النور التجارية للمواد الغذائية والاستيراد',
              address: 'عمّان — شارع المدينة المنوّرة — مجمّع الحسيني',
              balance: 987654.321,
              creditLimit: 100,
            ),
            actions: recordingActions([]),
          ),
        ),
      );
      expect(tester.takeException(), isNull,
          reason: 'البطاقةُ تقصُّ بالحذف لا تفيض بالشريط الأصفر');
    });

    testWidgets('الشبكةُ على عرضٍ ضيّقٍ تنهار إلى عمودٍ ولا تفيض',
        (tester) async {
      await show(
        tester,
        PartiesCardGrid(
          parties: [for (var i = 0; i < 6; i++) _card(id: i)],
          actions: recordingActions([]),
        ),
        size: const Size(600, 900),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('شريطُ الترشيح على عرضٍ ضيّقٍ يلتفّ ولا يفيض', (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await show(
        tester,
        PartiesFilterBar(
          controller: controller,
          filter: PicPosPartyFilter.all,
          onFilterChanged: (_) {},
          onSearchChanged: (_) {},
          onGroupsPressed: () {},
        ),
        size: const Size(760, 900),
      );
      expect(tester.takeException(), isNull,
          reason: 'الالتفافُ هو ما يمنع الشريطَ الأصفرَ والأسود');
    });

    testWidgets('بطاقاتُ العدّادات على عرضٍ ضيّقٍ تنهار إلى عمودَين',
        (tester) async {
      await show(
        tester,
        const PartiesSummaryCards(
          kpis: PicPosPartyKpis(
            total: 1234,
            customers: 900,
            suppliers: 334,
            totalDebit: 987654.321,
            totalCredit: 12345.678,
            overLimitCount: 17,
          ),
        ),
        size: const Size(640, 900),
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('PartiesFilterBar', () {
    testWidgets('يعرض الحبّاتِ الخمسَ كلَّها', (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await show(
        tester,
        PartiesFilterBar(
          controller: controller,
          filter: PicPosPartyFilter.all,
          onFilterChanged: (_) {},
          onSearchChanged: (_) {},
          onGroupsPressed: () {},
        ),
      );
      for (final f in PicPosPartyFilter.values) {
        expect(find.text(f.label), findsOneWidget, reason: f.id);
      }
    });

    testWidgets('نقرُ حبّةٍ يُبلِّغ بترشيحِها لا بغيره', (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      PicPosPartyFilter? picked;
      await show(
        tester,
        PartiesFilterBar(
          controller: controller,
          filter: PicPosPartyFilter.all,
          onFilterChanged: (f) => picked = f,
          onSearchChanged: (_) {},
          onGroupsPressed: () {},
        ),
      );
      await tester.tap(find.text('موردين'));
      await tester.pumpAndSettle();
      expect(picked, PicPosPartyFilter.supplier);
    });

    testWidgets('الكتابةُ في البحث تُبلَّغ نصّاً', (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      String? typed;
      await show(
        tester,
        PartiesFilterBar(
          controller: controller,
          filter: PicPosPartyFilter.all,
          onFilterChanged: (_) {},
          onSearchChanged: (v) => typed = v,
          onGroupsPressed: () {},
        ),
      );
      await tester.enterText(find.byType(TextField), 'سولا');
      await tester.pumpAndSettle();
      expect(typed, 'سولا');
    });

    testWidgets('زرُّ المجموعات موصولٌ', (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      var tapped = false;
      await show(
        tester,
        PartiesFilterBar(
          controller: controller,
          filter: PicPosPartyFilter.all,
          onFilterChanged: (_) {},
          onSearchChanged: (_) {},
          onGroupsPressed: () => tapped = true,
        ),
      );
      await tester.tap(find.text('المجموعات'));
      await tester.pumpAndSettle();
      expect(tapped, isTrue);
    });
  });

  group('PartiesCardGrid', () {
    testWidgets('قائمةٌ فارغةٌ تعرض حالةَ الفراغ لا شبكةً عمياء',
        (tester) async {
      await show(
        tester,
        PartiesCardGrid(parties: const [], actions: recordingActions([])),
      );
      expect(find.text('لا يوجد أطراف'), findsOneWidget);
      expect(find.byIcon(PhosphorIconsBold.users), findsOneWidget);
    });

    testWidgets('تعرض بطاقةً لكلّ طرف', (tester) async {
      await show(
        tester,
        PartiesCardGrid(
          parties: [
            _card(id: 1, name: 'الأول'),
            _card(id: 2, name: 'الثاني'),
            _card(id: 3, name: 'الثالث'),
          ],
          actions: recordingActions([]),
        ),
      );
      expect(find.byType(PartyCard), findsNWidgets(3));
      expect(find.text('الأول'), findsOneWidget);
      expect(find.text('الثالث'), findsOneWidget);
    });
  });

  group('PartiesSummaryCards', () {
    testWidgets('تعرض العدّاداتِ الأربعةَ بقيمها', (tester) async {
      await show(
        tester,
        const PartiesSummaryCards(
          kpis: PicPosPartyKpis(
            total: 120,
            customers: 90,
            suppliers: 35,
            totalDebit: 500,
            totalCredit: 200,
            overLimitCount: 4,
          ),
        ),
      );
      expect(find.text('إجمالي الأطراف'), findsOneWidget);
      expect(find.text('120'), findsOneWidget);
      expect(find.text('90'), findsOneWidget);
      expect(find.text('35'), findsOneWidget);
      expect(find.text('تجاوزوا حد الائتمان'), findsOneWidget);
      expect(find.text('4'), findsOneWidget);
    });
  });

  testWidgets('الشاشة المنفصلة تخفي مرشحات الأنواع وتبقي البحث', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await show(
      tester,
      PartiesFilterBar(
        controller: controller,
        filter: PicPosPartyFilter.customer,
        onFilterChanged: (_) {},
        onSearchChanged: (_) {},
        onGroupsPressed: () {},
        showTypeFilters: false,
      ),
      size: const Size(1366, 768),
    );

    expect(find.byType(TextField), findsOneWidget);
    expect(find.text(PicPosPartyFilter.customer.label), findsNothing);
    expect(tester.takeException(), isNull);
  });

  test('العميل المورد يقع في الشاشتين المنفصلتين', () {
    final dualRole = _card(isCustomer: true, isSupplier: true);

    expect(dualRole.matches(PicPosPartyFilter.customer, ''), isTrue);
    expect(dualRole.matches(PicPosPartyFilter.supplier, ''), isTrue);
  });

  test('شاشتا العملاء والموردين تثبتان النطاق الصحيح', () {
    expect(
      const PartiesPicposScreen.customers().scope,
      PicPosPartyFilter.customer,
    );
    expect(
      const PartiesPicposScreen.suppliers().scope,
      PicPosPartyFilter.supplier,
    );
  });

  testWidgets('PartiesPicposScreen موجودة وقابلة للإنشاء', (t) async {
    expect(const PartiesPicposScreen(), isA<Widget>());
  });
}
