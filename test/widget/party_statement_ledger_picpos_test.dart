// «كشف حساب» — إعادةُ تصميم تبويبة «الحركة والرصيد» (قرارُ المالك على
// الصورة `(7)`).
//
// ═══ ما يقيسه هذا الملفّ ═══
//
// ‏١) **مرشِّحُ الفرع ظاهرٌ — وعلى تبويبته وحدَها**. `getPartyStatement` هو
//    الاستعلامُ الوحيدُ الذي يقبل فرعاً؛ ومرشِّحٌ ثابتٌ فوقَ التبويبات الخمس
//    كان يُرشِّح واحدةً ويكذب على أربعٍ لا تقول إنّها لم تُرشَّح.
//
// ‏٢) **وما يُختار يصل الاستعلامَ فعلاً** — لا مرشِّحٌ يُرسَم ويُهمَل. والمقيسُ
//    ‏`branchId` الذي وصل المستودعَ لا لونُ الزرّ.
//
// ‏٣) **«تخصيص الأعمدة» يُغيّر الجدولَ فوراً** بلا إعادة استعلام، والتاريخُ
//    لا يُطفأ.
//
// ‏٤) **«عرض المستند» يتبع وجودَ الوجهة لا وجودَ الصفّ**: الرصيدُ الافتتاحيُّ
//    صفٌّ بلا مستندٍ أصلاً، وزرٌّ يُعرَض ولا يقفز أسوأُ من غيابه.
//
// ‏٥) **و«عرض المعتمد فقط» لا يُبنى**: الكشفُ يقرأ فواتيرَ وحركاتِ خزنةٍ
//    ‏`status`ها **حالةُ سدادٍ** (‏pending/partial/paid · pending/completed)
//    لا حالةُ اعتماد — فلا شيءَ ليُرشَّح، ومربّعٌ لا يُغيّر صفّاً واحداً يُقرأ
//    عطباً.
//
// ⚠️ **ولا قاعدةَ بيانات هنا**: المستودعُ ومزوِّدُ الفروع يُستبدَلان. فتحُ
// شاشةٍ على قاعدةٍ حيّةٍ في اختبار ودجت يعلّق — درسٌ مسجَّل لا تخمين.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/providers/providers.dart';
import 'package:picpos_erp/domain/repositories/parties_repository.dart';
import 'package:picpos_erp/presentation/party_statement_picpos/screens/party_statement_picpos_screen.dart';

Party _party(int id, String name) => Party(
  id: id,
  code: 'P-$id',
  name: name,
  isCustomer: true,
  isSupplier: false,
  isDeliveryCompany: false,
  isFavorite: false,
  balance: 300,
  creditLimit: 0,
  paymentTermsDays: 30,
  earlyPaymentDiscountPct: 0,
  earlyPaymentDiscountDays: 0,
  fixedDiscount: 0,
  priceLevel: 'default',
  isActive: true,
  createdAt: DateTime(2026, 1, 1),
  isGlobal: true,
  isSystemDefault: false,
  rowVersion: 0,
);

Branche _branch(int id, String name) => Branche(
  id: id,
  name: name,
  isActive: true,
  isSystemDefault: false,
  rowVersion: 0,
);

PartyStatementEntry _entry({
  required String type,
  required double debit,
  required double credit,
  required double balance,
  String? number,
  String? refType,
  int? refId,
}) => PartyStatementEntry(
  date: DateTime(2026, 9, 8),
  description: 'حركة $type',
  invoiceNumber: number,
  entryType: type,
  debit: debit,
  credit: credit,
  balance: balance,
  referenceType: refType,
  referenceId: refId,
);

/// مستودعٌ مزيَّفٌ **يسجّل الفرعَ الذي وصله**.
class _Repo implements IPartiesRepository {
  _Repo(this.parties, this.entries);

  final List<Party> parties;
  final List<PartyStatementEntry> entries;

  /// كلُّ قيمةِ `branchId` وصلت الاستعلامَ، بالترتيب.
  final List<int?> branchesAsked = [];

  @override
  Stream<List<Party>> watchAllPartiesForBranches(Set<int>? allowed) =>
      Stream.value(parties);

  @override
  Future<Party?> getPartyById(int id) async =>
      parties.where((p) => p.id == id).firstOrNull;

  @override
  Future<List<PartyStatementEntry>> getPartyStatement(
    int partyId, {
    DateTime? fromDate,
    DateTime? toDate,
    int? branchId,
  }) async {
    branchesAsked.add(branchId);
    return entries;
  }

  @override
  Future<List<PartyOpenInvoiceRow>> getPartyOpenInvoices({
    required int partyId,
    required bool supplier,
    DateTime? asOf,
    int? branchId,
  }) async => const [];

  // ⚠️ `TabBarView` يبني التبويبةَ المجاورةَ أيضاً، فاستعلاماتُها تُنادى ولو
  //    لم تُفتَح. وردُّها فارغاً يُبقي المقيسَ على «الحركة والرصيد» وحدَها.
  @override
  Future<List<PartyPaymentMatchRow>> getPartyPaymentMatches({
    required int partyId,
    DateTime? from,
    DateTime? to,
  }) async => const [];

  @override
  Future<List<CommercialPaperData>> getPartyPapers(int partyId) async =>
      const [];

  @override
  Future<PartyProfileMetrics> getPartyProfileMetrics({
    required int partyId,
    required bool supplier,
  }) async => const PartyProfileMetrics(
    settledInvoices: 0,
    avgSettlementDays: 0,
    onTimeSettlements: 0,
    receivedOrders: 0,
    onTimeOrders: 0,
  );

  @override
  Future<List<PartySettlementRow>> getPartySettlementRows({
    required int partyId,
    required bool supplier,
    int limit = 6,
  }) async => const [];

  @override
  Future<int> countPartyFollowUps(int partyId, {int? invoiceId}) async => 0;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final customer = _party(1, 'شركة النور');

  // ثلاثةُ صفوفٍ من التصميم + رصيدٌ افتتاحيٌّ بلا مستند.
  final entries = <PartyStatementEntry>[
    _entry(type: 'opening', debit: 0, credit: 0, balance: 0),
    _entry(
      type: 'invoice',
      debit: 300,
      credit: 0,
      balance: 300,
      number: 'INV-1042',
      refType: 'sales_invoice',
      refId: 11,
    ),
    _entry(
      type: 'receipt',
      debit: 0,
      credit: 140,
      balance: 160,
      number: 'RV-0051',
      refType: 'safe_transaction',
      refId: 22,
    ),
  ];

  Future<_Repo> open(
    WidgetTester tester, {
    Size size = const Size(1500, 950),
    List<Branche> branches = const [],
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final repo = _Repo([customer], entries);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          partiesRepositoryProvider.overrideWithValue(repo),
          branchScopeProvider.overrideWith(
            (ref) async => const BranchScope.fullAccess(),
          ),
          userAccessibleBranchesProvider.overrideWith((ref) async => branches),
        ],
        child: const MaterialApp(home: PartyStatementPicposScreen(partyId: 1)),
      ),
    );
    await tester.pumpAndSettle();
    return repo;
  }

  Future<void> teardownTree(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }

  group('🔴 مرشِّحُ الفرع', () {
    testWidgets('لا يظهر لتجهيزةٍ بفرعٍ واحد — اختيارٌ من واحدٍ ليس اختياراً', (
      tester,
    ) async {
      await open(tester, branches: [_branch(1, 'الفرع الرئيسي')]);
      expect(find.text('جميع الفروع'), findsNothing);
      await teardownTree(tester);
    });

    testWidgets('ويظهر بفرعين', (tester) async {
      await open(
        tester,
        branches: [_branch(1, 'الفرع الرئيسي'), _branch(2, 'فرع المعادي')],
      );
      expect(find.text('جميع الفروع'), findsOneWidget);
      await teardownTree(tester);
    });

    testWidgets('🔴 وما يُختار يصل الاستعلامَ فعلاً', (tester) async {
      final repo = await open(
        tester,
        branches: [_branch(1, 'الفرع الرئيسي'), _branch(2, 'فرع المعادي')],
      );
      expect(repo.branchesAsked, [null], reason: 'أوّلُ تحميلٍ بلا فرع');

      await tester.tap(find.text('جميع الفروع'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('فرع المعادي').last);
      await tester.pumpAndSettle();

      expect(
        repo.branchesAsked,
        [null, 2],
        reason: 'مرشِّحٌ يُرسَم ولا يصل الاستعلامَ يكذب كزرٍّ لا يفعل',
      );
      await teardownTree(tester);
    });

    testWidgets('🔴 ويختفي على تبويبةٍ لا تعرف الفرع', (tester) async {
      await open(
        tester,
        branches: [_branch(1, 'الفرع الرئيسي'), _branch(2, 'فرع المعادي')],
      );
      expect(find.text('جميع الفروع'), findsOneWidget);

      await tester.tap(find.text('الأوراق والضمانات'));
      await tester.pumpAndSettle();
      expect(
        find.text('جميع الفروع'),
        findsNothing,
        reason:
            '`getPartyPapers` لا تعرف فرعاً — ومرشِّحٌ باقٍ فوقها '
            'يَعِد بترشيحٍ لا يقع',
      );
      await teardownTree(tester);
    });
  });

  group('🔴 تخصيصُ الأعمدة', () {
    testWidgets('الزرُّ حاضرٌ والأعمدةُ السبعةُ افتراضاً', (tester) async {
      await open(tester);
      expect(find.text('تخصيص الأعمدة'), findsOneWidget);
      for (final label in [
        'التاريخ',
        'المستند',
        'البيان',
        'مدين',
        'دائن',
        'الرصيد الجاري',
        'الحالة',
      ]) {
        expect(find.text(label), findsWidgets, reason: 'العمود «$label» غائب');
      }
      await teardownTree(tester);
    });

    testWidgets('🔴 وإطفاءُ عمودٍ يُخرجه من الجدول فوراً', (tester) async {
      final repo = await open(tester);
      final queriesBefore = repo.branchesAsked.length;

      await tester.tap(find.text('تخصيص الأعمدة'));
      await tester.pumpAndSettle();
      // «الحالة» في الحوار — آخرُ مربّعٍ في القائمة.
      await tester.tap(
        find.descendant(
          of: find.byType(CheckboxListTile),
          matching: find.text('الحالة'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('تطبيق'));
      await tester.pumpAndSettle();

      expect(find.text('الحالة'), findsNothing);
      expect(
        repo.branchesAsked.length,
        queriesBefore,
        reason: 'تبديلُ عمودٍ عرضٌ خالصٌ — ولا يجوز أن يضرب القاعدة',
      );
      await teardownTree(tester);
    });

    testWidgets('🔴 والشريحةُ المنتقاةُ تبقى بعد التخصيص', (tester) async {
      // ⚠️ مفتاحٌ يحمل الأعمدةَ على الجدول كان سيُعيد بناءَ حالته فيرتدّ
      //    الترشيحُ إلى «كل الحركات» — والمستخدمُ لم يطلب ذلك.
      await open(tester);
      await tester.tap(find.text('فواتير'));
      await tester.pumpAndSettle();
      expect(find.text('RV-0051'), findsNothing);
      expect(find.text('INV-1042'), findsOneWidget);

      await tester.tap(find.text('تخصيص الأعمدة'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(CheckboxListTile),
          matching: find.text('الحالة'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('تطبيق'));
      await tester.pumpAndSettle();

      expect(
        find.text('RV-0051'),
        findsNothing,
        reason: 'الترشيحُ ارتدّ إلى «كل الحركات» بعد تبديل عمود',
      );
      expect(find.text('INV-1042'), findsOneWidget);
      await teardownTree(tester);
    });

    testWidgets('🔴 وعمودُ التاريخ لا يُطفأ', (tester) async {
      await open(tester);
      await tester.tap(find.text('تخصيص الأعمدة'));
      await tester.pumpAndSettle();

      final dateTile = tester.widget<CheckboxListTile>(
        find.ancestor(
          of: find.text('التاريخ'),
          matching: find.byType(CheckboxListTile),
        ),
      );
      expect(
        dateTile.onChanged,
        isNull,
        reason: 'سطرُ كشفٍ بلا تاريخٍ لا يُقرأ ولا يُرتَّب',
      );
      expect(
        find.text('ثابتٌ — لا يُخفى'),
        findsOneWidget,
        reason: 'مربّعٌ معطَّلٌ بلا سببٍ مكتوبٍ يُقرأ عطباً',
      );
      await teardownTree(tester);
    });
  });

  group('🔴 عرضُ المستند', () {
    testWidgets('الشريطُ يقول «اختر سطراً» قبل الاختيار والزرُّ معطَّل', (
      tester,
    ) async {
      await open(tester);
      expect(find.text('اختر سطراً لعرض مستنده'), findsOneWidget);
      final btn = tester.widget<FilledButton>(
        find.ancestor(
          of: find.text('عرض المستند'),
          matching: find.byType(FilledButton),
        ),
      );
      expect(btn.onPressed, isNull);
      await teardownTree(tester);
    });

    testWidgets('واختيارُ فاتورةٍ يُفعِّله ويسمّي وجهتَه', (tester) async {
      await open(tester);
      await tester.tap(find.text('INV-1042'));
      await tester.pumpAndSettle();

      expect(find.textContaining('فاتورة المبيعات'), findsOneWidget);
      final btn = tester.widget<FilledButton>(
        find.ancestor(
          of: find.text('عرض المستند'),
          matching: find.byType(FilledButton),
        ),
      );
      expect(btn.onPressed, isNotNull);
      await teardownTree(tester);
    });

    testWidgets('🔴 وصفُّ الرصيد الافتتاحيّ يقول «لا مستندَ يُفتَح»', (
      tester,
    ) async {
      await open(tester);
      await tester.tap(find.text('حركة opening'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('لا مستندَ يُفتَح'),
        findsOneWidget,
        reason: 'زرٌّ يُعرَض ولا يقفز يُقرأ «الشاشةُ معطوبة»',
      );
      final btn = tester.widget<FilledButton>(
        find.ancestor(
          of: find.text('عرض المستند'),
          matching: find.byType(FilledButton),
        ),
      );
      expect(btn.onPressed, isNull);
      await teardownTree(tester);
    });

    testWidgets('ونقرةٌ ثانيةٌ على المختار تُلغي الاختيار', (tester) async {
      await open(tester);
      await tester.tap(find.text('INV-1042'));
      await tester.pumpAndSettle();
      expect(find.text('اختر سطراً لعرض مستنده'), findsNothing);

      await tester.tap(find.text('INV-1042'));
      await tester.pumpAndSettle();
      expect(find.text('اختر سطراً لعرض مستنده'), findsOneWidget);
      await teardownTree(tester);
    });
  });

  group('و«عرض المعتمد فقط» أُسقط', () {
    testWidgets('لا مربّعَ اعتمادٍ في الشاشة', (tester) async {
      await open(
        tester,
        branches: [_branch(1, 'الفرع الرئيسي'), _branch(2, 'فرع المعادي')],
      );
      expect(
        find.textContaining('المعتمد'),
        findsNothing,
        reason:
            'فواتيرُ الكشف وحركاتُه `status`ها حالةُ سدادٍ لا اعتماد — '
            'فلا شيءَ ليُرشَّح',
      );
      await teardownTree(tester);
    });
  });

  group('ومراسي تركيب', () {
    for (final w in const [1100.0, 1500.0, 1920.0]) {
      testWidgets('الشريطُ السفليُّ والجدولُ بلا فيضٍ عند ${w ~/ 1}', (
        tester,
      ) async {
        await open(
          tester,
          size: Size(w, 900),
          branches: [_branch(1, 'الفرع الرئيسي'), _branch(2, 'فرع المعادي')],
        );
        expect(tester.takeException(), isNull);
        expect(find.text('عرض المستند'), findsOneWidget);
        expect(find.text('طباعة الكشف'), findsOneWidget);
        expect(find.text('تصدير'), findsOneWidget);
        await teardownTree(tester);
      });
    }
  });
}
