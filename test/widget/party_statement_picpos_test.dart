// كشفُ حساب العميل والمورد — نسخةُ PicPos على التصميم.
//
// ═══ ما يُقاس ═══
//
// ‏١) **التركيبُ على عرضين لكلا الكشفين**: الشاشةُ ترويسةٌ فيها ثلاثةُ أزرارٍ
//    ومنتقي طرف، ثمّ شريطُ مدىً وخمسُ تبويبات، ثمّ جسمٌ فيه صفُّ مؤشّراتٍ
//    وأشرطةٌ ولوحةُ حالاتٍ وجدولٌ كلُّها محسوبةُ العرض. وانهيارُ التخطيط لا
//    يظهر في `flutter analyze` أبداً.
//
// ‏٢) **الكشفان مختلفان لا نسختان**: تبويبةُ «أعمار الدين» للعميل وحدَه
//    و«المستحق والاستحقاق» للمورد وحدَه. ولو انزلق أحدُهما إلى الآخر لبدا
//    كلُّ شيءٍ سليماً وقرأ المورّدُ كشفَ عميل.
//
// ‏٣) **الشارةُ مقيسةٌ من الصفوف المحمَّلة**: عددُ حركاتِ الكشف يجب أن يساويَ
//    ما يعود به المستودع. ورقمٌ مكتوبٌ بجانب ما يعدّه يمرّ أخضرَ ويكذب.
//
// ‏٤) **الشريحةُ تُرشِّح فعلاً**: `PicPosDataTable` بلا حالة، والتحميلُ يقع في
//    دالّةٍ غيرِ متزامنة — فبلا الحاويةِ الحاملةِ للحالة كانت الشريحةُ
//    تُرسَم ولا تفعل، وهي تكذب كزرٍّ لا يفعل.
//
// ‏٥) **أزرارُ التصميم محذوفةٌ لا معطَّلة**: «تحصيل» و«سداد» و«مطالبة» أفعالٌ
//    ماليّةٌ لم تُبنَ، فلا يجوز أن تظهر في أيّ صفّ.
//
// ‏٦) **الطرفُ المفقودُ يُعلَن**: العطبُ الميدانيُّ السابق كان جسماً فارغاً بلا
//    رسالةٍ حين يعود `getPartyById` بـ`null`.
//
// ⚠️ **ولا قاعدةَ بيانات هنا**: المستودعُ يُستبدَل بمزيَّف. فتحُ شاشةٍ على
// قاعدةٍ حيّةٍ في اختبار ودجت يعلّق (`db.close()` ينتظر مؤقّتَ drift في
// المنطقة الوهميّة) — درسٌ مسجَّل لا تخمين.
//
// ⚠️ **وتفكيكُ الشجرة بنداءٍ صريحٍ في نهاية الجسم لا في `addTearDown`**:
// الأخيرةُ تعمل **بعد** فحصِ المؤقّتات.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/providers/providers.dart';
import 'package:ural_erp/domain/repositories/parties_repository.dart';
import 'package:ural_erp/presentation/party_statement_picpos/screens/party_statement_picpos_screen.dart';

// ═══ تجهيزةٌ ثابتة ═══════════════════════════════════════════════════════

Party _party({
  required int id,
  required String name,
  bool customer = true,
  bool supplier = false,
  double balance = 4400,
  double creditLimit = 50000,
  int terms = 30,
  double discPct = 0,
  int discDays = 0,
  int? rating,
}) =>
    Party(
      id: id,
      code: 'P-$id',
      name: name,
      phone: '01000000000',
      address: 'المعادي',
      isCustomer: customer,
      isSupplier: supplier,
      isDeliveryCompany: false,
      isFavorite: false,
      balance: balance,
      creditLimit: creditLimit,
      paymentTermsDays: terms,
      earlyPaymentDiscountPct: discPct,
      earlyPaymentDiscountDays: discDays,
      supplierRating: rating,
      fixedDiscount: 0,
      priceLevel: 'default',
      isActive: true,
      createdAt: DateTime(2026, 1, 1),
      isGlobal: true,
      isSystemDefault: false,
      rowVersion: 0,
    );

PartyStatementEntry _entry(
  String type,
  double debit,
  double credit,
  double balance, {
  String? number,
}) =>
    PartyStatementEntry(
      date: DateTime(2026, 8, 10),
      description: 'حركة $type',
      invoiceNumber: number,
      entryType: type,
      debit: debit,
      credit: credit,
      balance: balance,
    );

PartyOpenInvoiceRow _open(
  String number,
  double total,
  double paid,
  int daysLate,
) =>
    PartyOpenInvoiceRow(
      invoiceId: number.hashCode,
      invoiceNumber: number,
      invoiceDate: DateTime(2026, 7, 1),
      dueDate: DateTime(2026, 7, 31),
      total: total,
      paid: paid,
      daysLate: daysLate,
    );

PartyPaymentMatchRow _pay(
  String number,
  double amount,
  double allocated,
  int invoiceCount,
) =>
    PartyPaymentMatchRow(
      paymentId: number.hashCode,
      paymentNumber: number,
      paymentDate: DateTime(2026, 8, 20),
      amount: amount,
      allocated: allocated,
      method: 'نقدي',
      invoiceCount: invoiceCount,
    );

CommercialPaperData _paper(int id, String number, String status, double amt) =>
    CommercialPaperData(
      id: id,
      paperNumber: number,
      type: 'cheque',
      direction: 'received',
      partyId: 1,
      amount: amt,
      issueDate: DateTime(2026, 7, 1),
      dueDate: DateTime(2026, 9, 20),
      bankName: 'بنك مصر',
      status: status,
      createdAt: DateTime(2026, 7, 1),
      rowVersion: 0,
    );

/// مستودعُ أطرافٍ مزيَّف.
///
/// `noSuchMethod` تغطّي الباقي: أيُّ نداءٍ آخرَ يرمي — وهذا مقصود، فالشاشةُ
/// لا يجوز أن تنادي غيرَ ما هنا.
class _FakePartiesRepo implements IPartiesRepository {
  _FakePartiesRepo({
    required this.parties,
    this.entries = const [],
    this.open = const [],
    this.payments = const [],
    this.poRows = const [],
    this.papers = const [],
    this.metrics = const PartyProfileMetrics(
      settledInvoices: 4,
      avgSettlementDays: 6,
      onTimeSettlements: 3,
      receivedOrders: 5,
      onTimeOrders: 4,
    ),
    this.missingParty = false,
  });

  final List<Party> parties;
  final List<PartyStatementEntry> entries;
  final List<PartyOpenInvoiceRow> open;
  final List<PartyPaymentMatchRow> payments;
  final List<PoMatchRow> poRows;
  final List<CommercialPaperData> papers;
  final PartyProfileMetrics metrics;

  /// يحاكي الطرفَ المحذوفَ أو الخارجَ عن النطاق.
  final bool missingParty;

  @override
  Stream<List<Party>> watchAllPartiesForBranches(Set<int>? allowed) =>
      Stream.value(parties);

  @override
  Future<Party?> getPartyById(int id) async => missingParty
      ? null
      : parties.where((p) => p.id == id).firstOrNull;

  @override
  Future<List<PartyStatementEntry>> getPartyStatement(
    int partyId, {
    DateTime? fromDate,
    DateTime? toDate,
    int? branchId,
  }) async =>
      entries;

  @override
  Future<List<PartyOpenInvoiceRow>> getPartyOpenInvoices({
    required int partyId,
    required bool supplier,
    DateTime? asOf,
  }) async =>
      open;

  @override
  Future<List<PartyPaymentMatchRow>> getPartyPaymentMatches({
    required int partyId,
    DateTime? from,
    DateTime? to,
  }) async =>
      payments;

  @override
  Future<List<PoMatchRow>> getPurchaseOrderMatches({
    required int supplierId,
    DateTime? from,
    DateTime? to,
  }) async =>
      poRows;

  @override
  Future<List<CommercialPaperData>> getPartyPapers(int partyId) async => papers;

  @override
  Future<PartyProfileMetrics> getPartyProfileMetrics({
    required int partyId,
    required bool supplier,
  }) async =>
      metrics;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

void main() {
  final customer = _party(id: 1, name: 'سوبر ماركت النور');
  final supplier = _party(
    id: 2,
    name: 'جهينة للأغذية',
    customer: false,
    supplier: true,
    balance: -98600,
    creditLimit: 0,
    discPct: 2,
    discDays: 10,
    rating: 4,
  );

  // ثلاثُ فواتيرَ ومقبوضٌ ومرتجعٌ — خمسُ حركات.
  final entries = <PartyStatementEntry>[
    _entry('opening', 28400, 0, 28400),
    _entry('invoice', 34180, 0, 62580, number: 'INV-0842'),
    _entry('invoice', 10620, 0, 73200, number: 'INV-1041'),
    _entry('receipt', 0, 30000, 43200, number: 'RCP-0498'),
    _entry('sales_return', 0, 4820, 38380, number: 'RET-0122'),
  ];

  final open = <PartyOpenInvoiceRow>[
    _open('INV-1041', 10620, 0, -5), // لم يحن
    _open('INV-1035', 9140, 1360, 44), // متأخر ٣١—٦٠
  ];

  final papers = <CommercialPaperData>[
    _paper(1, 'CHQ-8842', 'deposited', 18000),
    _paper(2, 'CHQ-7710', 'pending', 9400),
    _paper(3, 'CHQ-5501', 'cashed', 25000),
  ];

  Future<void> open2(
    WidgetTester tester,
    Size size, {
    required bool asSupplier,
    _FakePartiesRepo? repo,
    int? partyId,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final r = repo ??
        _FakePartiesRepo(
          parties: [customer, supplier],
          entries: entries,
          open: open,
          papers: papers,
        );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          partiesRepositoryProvider.overrideWithValue(r),
          branchScopeProvider
              .overrideWith((ref) async => const BranchScope.fullAccess()),
        ],
        child: MaterialApp(
          home: PartyStatementPicposScreen(
            partyId: partyId ?? (asSupplier ? 2 : 1),
            isSupplier: asSupplier,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> teardownTree(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }

  group('التركيبُ على عرضين', () {
    for (final w in const [
      ('عرضٌ يتّسع', Size(1500, 900)),
      ('عرضٌ ضيّق', Size(820, 760)),
    ]) {
      for (final mode in const [('عميل', false), ('مورد', true)]) {
        testWidgets('${w.$1} — كشفُ ${mode.$1} بلا فيضٍ ولا انهيار',
            (tester) async {
          await open2(tester, w.$2, asSupplier: mode.$2);
          expect(tester.takeException(), isNull,
              reason: 'انهيارُ تخطيطٍ عند العرض ${w.$2.width} لكشف ${mode.$1}');

          // والمحتوى ظاهرٌ فعلاً — لا شجرةٌ فارغةٌ تمرّ.
          expect(find.text('كشف حساب ${mode.$1}'), findsOneWidget);
          expect(find.text('الحركة والرصيد'), findsWidgets);
          expect(find.text('تصدير الكشف'), findsOneWidget);
          expect(find.text('طباعة'), findsOneWidget);
          await teardownTree(tester);
        });
      }
    }
  });

  testWidgets('الكشفان مختلفان — لكلٍّ تبويبتُه الخاصّة', (tester) async {
    await open2(tester, const Size(1500, 900), asSupplier: false);
    expect(find.text('أعمار الدين'), findsOneWidget);
    expect(find.text('المستحق والاستحقاق'), findsNothing);
    expect(find.text('مطابقة الدفعات'), findsOneWidget);
    expect(find.text('ملف العميل والائتمان'), findsOneWidget);
    await teardownTree(tester);
  });

  testWidgets('كشفُ المورد يحمل تبويباتِه هو لا تبويباتِ العميل',
      (tester) async {
    await open2(tester, const Size(1500, 900), asSupplier: true);
    expect(find.text('المستحق والاستحقاق'), findsOneWidget);
    expect(find.text('أعمار الدين'), findsNothing,
        reason: 'تبويبةُ العميل انزلقت إلى كشف المورد',
    );
    expect(find.text('مطابقة الفواتير بالاستلام'), findsOneWidget);
    expect(find.text('ملف المورد والتقييم'), findsOneWidget);
    await teardownTree(tester);
  });

  testWidgets('شارةُ التبويبة مقيسةٌ من الصفوف لا مكتوبة', (tester) async {
    await open2(tester, const Size(1500, 900), asSupplier: false);
    // خمسُ حركاتٍ في التجهيزة ⇒ الشارةُ «5»، وشارةُ «أعمار الدين» «2».
    expect(find.text('${entries.length}'), findsWidgets);
    expect(find.text('${open.length}'), findsWidgets);
    await teardownTree(tester);
  });

  testWidgets('شريحةُ الجدول تُرشِّح فعلاً لا تُرسَم وحسب', (tester) async {
    await open2(tester, const Size(1500, 900), asSupplier: false);

    // «كل الحركات» أوّلاً: الفواتيرُ والمقبوضُ والمرتجعُ كلُّها معروضة.
    expect(find.text('RCP-0498'), findsOneWidget);
    expect(find.text('INV-0842'), findsOneWidget);

    // إلى شريحة «فواتير» — المقبوضُ يختفي والفواتيرُ تبقى.
    await tester.tap(find.text('فواتير').first);
    await tester.pumpAndSettle();
    expect(find.text('INV-0842'), findsOneWidget);
    expect(
      find.text('RCP-0498'),
      findsNothing,
      reason: 'الشريحةُ رُسمت ولم تُرشِّح — وهي تكذب كزرٍّ لا يفعل',
    );
    await teardownTree(tester);
  });

  // ═══ بحثُ الترويسة — `HEADS.hint` في التصميم ════════════════════════════
  //
  // ⚠️ يُفحَص على **تبويبتين مختلفتَين** لأنّ آليّتَهما مختلفة: الجدولُ يرشِّح
  //    صفوفاً واللوحةُ ترشِّح بطاقات. وفحصُ إحداهما وحدَها كان سيمرّ أخضرَ
  //    بينما البحثُ معطَّلٌ على نصف الشاشة.
  testWidgets('بحثُ الترويسة يُرشِّح صفوفَ الجدول', (tester) async {
    await open2(tester, const Size(1500, 900), asSupplier: false);

    expect(find.text('INV-0842'), findsOneWidget);
    expect(find.text('RCP-0498'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextField, 'ابحث بمستند أو مبلغ داخل الكشف...'),
      'RCP',
    );
    await tester.pumpAndSettle();

    expect(find.text('RCP-0498'), findsOneWidget);
    expect(find.text('INV-0842'), findsNothing,
        reason: 'البحثُ رُسم ولم يُرشِّح');

    // ومجاميعُ الجدول تتبع البحث — «٥ حركة» فوق صفٍّ واحدٍ رقمٌ يكذب.
    //
    // ⚠️ ولا يُفحَص هنا **شارةُ التبويبة**: هي عددُ حركات **الفترة** لا عددُ
    //    ما يظهر، والبحثُ عدسةٌ عابرةٌ لا يغيّر ما تحمله الفترة. فبقاؤها ٥
    //    صوابٌ لا عطب.
    expect(find.text('1 حركة'), findsOneWidget,
        reason: 'مجموعُ الجدول لم يتبع البحث');
    expect(find.text('5 حركة'), findsNothing);
    await teardownTree(tester);
  });

  testWidgets('بحثُ الترويسة يُرشِّح بطاقاتِ لوحة المطابقة', (tester) async {
    await open2(
      tester,
      const Size(1500, 900),
      asSupplier: false,
      repo: _FakePartiesRepo(
        parties: [customer],
        entries: entries,
        open: open,
        payments: [
          _pay('RCP-0552', 11540, 0, 0),
          _pay('RCP-0410', 34180, 34180, 1),
        ],
      ),
    );
    await tester.tap(find.text('مطابقة الدفعات').first);
    await tester.pumpAndSettle();
    expect(find.textContaining('RCP-0552'), findsWidgets);
    expect(find.textContaining('RCP-0410'), findsWidgets);

    await tester.enterText(
      find.widgetWithText(TextField, 'ابحث بمستند أو مبلغ داخل الكشف...'),
      '0410',
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('RCP-0410'), findsWidgets);
    expect(
      find.textContaining('RCP-0552'),
      findsNothing,
      reason: 'اللوحةُ لا تسمع البحثَ — فتبويبةٌ كاملةٌ يبدو البحثُ فيها معطَّلاً',
    );
    await teardownTree(tester);
  });

  testWidgets('بحثٌ بلا نتيجةٍ يقول ذلك ولا يُرى جدولاً فارغاً',
      (tester) async {
    await open2(tester, const Size(1500, 900), asSupplier: false);
    await tester.enterText(
      find.widgetWithText(TextField, 'ابحث بمستند أو مبلغ داخل الكشف...'),
      'لا-يوجد-مثل-هذا',
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('لا نتيجةَ للبحث'), findsWidgets);
    await teardownTree(tester);
  });

  testWidgets('حالةُ الفاتورة مقيسةٌ بالقائم من الذمّة', (tester) async {
    await open2(tester, const Size(1500, 900), asSupplier: false);
    // INV-0842 ليست في القائمة ⇒ «مسدَّدة»، وINV-1041 قائمةٌ لم يحن أجلُها.
    expect(find.text('مسدَّدة'), findsWidgets);
    expect(find.text('قائمة'), findsWidgets);
    expect(find.text('مُدوَّر'), findsOneWidget);
    await teardownTree(tester);
  });

  // ⚠️ **يُفحَص على التبويبات التي يضع التصميمُ الأزرارَ فيها**، لا على
  //    «الحركة والرصيد» وحدَها — فهي التبويبةُ الوحيدةُ التي لا عمودَ إجراءٍ
  //    لها في التصميم أصلاً، وفحصُها كان سيمرّ أخضرَ بلا معنى.
  testWidgets('لا أزرارَ إجراءٍ في أيّ تبويبة — محذوفةٌ لا معطَّلة',
      (tester) async {
    const actionLabels = ['تحصيل', 'سداد', 'مطالبة', 'إيداع', 'تأكيد الخصم'];

    await open2(tester, const Size(1500, 900), asSupplier: false);
    for (final tab in const ['أعمار الدين', 'الأوراق والضمانات']) {
      await tester.tap(find.text(tab).first);
      await tester.pumpAndSettle();
      for (final label in actionLabels) {
        expect(
          find.text(label),
          findsNothing,
          reason: 'زرُّ «$label» ظهر في تبويبة «$tab» وهو فعلٌ ماليٌّ لم '
              'يُبنَ — وزرٌّ يظهر ولا يفعل أسوأُ من زرٍّ غائب',
        );
      }
      // والتبويبةُ رُسمت فعلاً — وإلّا كان الغيابُ غيابَ الشجرة كلِّها.
      expect(tester.takeException(), isNull);
    }
    await teardownTree(tester);

    await open2(tester, const Size(1500, 900), asSupplier: true);
    await tester.tap(find.text('المستحق والاستحقاق').first);
    await tester.pumpAndSettle();
    for (final label in actionLabels) {
      expect(find.text(label), findsNothing,
          reason: 'زرُّ «$label» ظهر في «المستحق والاستحقاق»');
    }
    expect(find.text('المستحق للمورد وتواريخه'), findsOneWidget,
        reason: 'التبويبةُ لم تُرسَم — فغيابُ الأزرار بلا دلالة');
    await teardownTree(tester);
  });

  // ═══ حارسُ عمودِ «إجراء» — بمرساةٍ تُسقطه إن انكسر معياره ═══════════════
  //
  // ⚠️ **لا يُفحَص بنوع الودجت**: `PicPosButtonCell` ترسم `Material`+`InkWell`
  //    لا `ElevatedButton`، فحارسٌ يبحث عن الأخير يمرّ أخضرَ إلى الأبد وهو
  //    لا يفحص شيئاً (قِيس فعلاً في هذه الجلسة).
  //
  //    فالمعيارُ **عنوانُ العمود**: التصميمُ يسمّيه «إجراء» في أربعة جداول.
  //    وعودتُه تعني عودةَ العمود. والمرساةُ عناوينُ الأعمدة الأخرى في نفس
  //    الجدول — إن غابت فالجدولُ لم يُرسَم أصلاً وغيابُ «إجراء» بلا دلالة.
  testWidgets('عمودُ «إجراء» غائبٌ عن جداول الكشف الأربعة', (tester) async {
    final cases = <({bool supplier, String tab, String anchor})>[
      (supplier: false, tab: 'أعمار الدين', anchor: 'عمر التأخر'),
      (supplier: false, tab: 'الأوراق والضمانات', anchor: 'الاستحقاق'),
      (supplier: true, tab: 'المستحق والاستحقاق', anchor: 'خصم نقدي'),
      (supplier: true, tab: 'الأوراق والمقايضات', anchor: 'الاستحقاق'),
    ];

    for (final c in cases) {
      await open2(tester, const Size(1500, 900), asSupplier: c.supplier);
      await tester.tap(find.text(c.tab).first);
      await tester.pumpAndSettle();

      // المرساة: آخرُ عمودٍ باقٍ في الجدول بعد حذف «إجراء».
      expect(
        find.text(c.anchor),
        findsWidgets,
        reason: 'عمودُ «${c.anchor}» غائبٌ عن «${c.tab}» — الجدولُ لم يُرسَم، '
            'فغيابُ «إجراء» لا يثبت شيئاً',
      );
      expect(
        find.text('إجراء'),
        findsNothing,
        reason: 'عمودُ «إجراء» عاد إلى «${c.tab}»',
      );
      await teardownTree(tester);
    }
  });

  testWidgets('الطرفُ المفقودُ يُعلَن ولا يُترَك جسماً فارغاً',
      (tester) async {
    await open2(
      tester,
      const Size(1200, 800),
      asSupplier: false,
      repo: _FakePartiesRepo(parties: [customer], missingParty: true),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('الطرفُ المطلوب غيرُ موجود'), findsOneWidget);
    await teardownTree(tester);
  });

  testWidgets('تبويبةُ الأوراق تعرض ما حُمِّل وتعدّه', (tester) async {
    await open2(tester, const Size(1500, 900), asSupplier: false);
    await tester.tap(find.text('الأوراق والضمانات').first);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('CHQ-8842'), findsOneWidget);
    // ثلاثُ أوراقٍ: واحدةٌ مودعةٌ وواحدةٌ معلّقةٌ ⇒ «قائمة» اثنتان، ومحصَّلةٌ
    // واحدة.
    expect(find.text('مودع'), findsOneWidget);
    expect(find.text('محصَّل'), findsOneWidget);
    await teardownTree(tester);
  });

  testWidgets('ملفُّ المورد يقول «لم يُقيَّم» لا «صفر» حين لا تقييم',
      (tester) async {
    final unrated = _party(
      id: 2,
      name: 'مورد بلا تقييم',
      customer: false,
      supplier: true,
    );
    await open2(
      tester,
      const Size(1500, 900),
      asSupplier: true,
      repo: _FakePartiesRepo(
        parties: [unrated],
        entries: entries,
        open: open,
        metrics: const PartyProfileMetrics(
          settledInvoices: 0,
          avgSettlementDays: 0,
          onTimeSettlements: 0,
          receivedOrders: 0,
          onTimeOrders: 0,
        ),
      ),
    );
    await tester.tap(find.text('ملف المورد والتقييم').first);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('لم يُقيَّم'), findsWidgets);
    // ولا نسبةَ التزامٍ صفريّةً لمورّدٍ بلا أوامرَ مستلَمة.
    expect(find.text('لا بيانات'), findsWidgets);
    expect(
      find.text('0٪'),
      findsNothing,
      reason: 'تقييمٌ صفريٌّ لمورّدٍ بلا سجلٍّ حكمٌ ظالمٌ يبدو مقيساً',
    );
    await teardownTree(tester);
  });
}
