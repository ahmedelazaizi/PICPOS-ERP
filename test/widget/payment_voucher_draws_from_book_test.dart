// 🔴 **سندُ الصرف يسحب الرقمَ من الدفتر فعلاً** — أثرٌ لا اسم.
//
// ═══ لماذا هذا الملفّ موجود ═══
//
// `cheque_book_guards_its_numbering_test` حارسُ **بنيةٍ**: يَعُدّ مواضعَ
// الرمز. وهو يمسك حذفَ السحب أو استعمالَ رقم المعاينة، **ولا يمسك** شرطاً
// ميّتاً (`if (… || true) return typed;`): الاسمُ باقٍ والعدُّ صحيحٌ والفرعُ
// لا يُنفَّذ.
//
// وأثرُ ذلك غيرُ مرئيّ تماماً: الشيكُ يُكتَب، والسندُ يُرحَّل، والدفترُ يعرض
// «التالي» كما هو — **فيُصدَر الرقمُ نفسُه لكلّ مورّد**، ولا يظهر حتى ترتدّ
// شيكاتٌ من البنك بـ«رقم مكرَّر».
//
// ⇒ فهذا الملفُّ يقود الشاشةَ ويقيس **ما وصل الورقة**.
//
// ⚠️ و`ClientWriteInterceptor` ساكنٌ لا يُحقَن — و`SyncInterceptor.isClientMode`
//    كاذبةٌ في الاختبار فيرتدّ بـ`null`، أي أنّ المسار المقيسَ هنا هو
//    المسارُ **المحلّيّ**: هو نفسُه الذي يكتب `commercial_papers`.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ural_erp/data/database/database.dart' as db;
import 'package:ural_erp/data/providers/auth_providers.dart';
import 'package:ural_erp/data/providers/parties_providers.dart';
import 'package:ural_erp/data/providers/repository_providers.dart';
import 'package:ural_erp/data/providers/treasury_providers.dart';
import 'package:ural_erp/domain/repositories/accounting_repository.dart';
import 'package:ural_erp/domain/repositories/activity_log_repository.dart';
import 'package:ural_erp/domain/repositories/commercial_papers_repository.dart'
    hide commercialPapersRepositoryProvider;
import 'package:ural_erp/domain/repositories/treasury_repository.dart';
import 'package:ural_erp/presentation/treasury_picpos/screens/payment_voucher_picpos_screen.dart';
import 'package:ural_erp/presentation/treasury_picpos/screens/receipt_voucher_picpos_screen.dart'
    show voucherOpenInvoicesProvider;

db.Party _supplier() => db.Party(
      id: 5,
      name: 'مورد الشمال',
      isCustomer: false,
      isSupplier: true,
      isDeliveryCompany: false,
      isFavorite: false,
      balance: 0,
      creditLimit: 0,
      paymentTermsDays: 0,
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

db.ChequeBookData _book({
  int id = 3,
  String number = 'A-1',
  int next = 101,
  int to = 200,
  String status = 'active',
}) =>
    db.ChequeBookData(
      id: id,
      bankAccountId: 100,
      bookNumber: number,
      prefix: 'CHK-',
      fromNumber: 101,
      toNumber: to,
      nextNumber: next,
      status: status,
      createdAt: DateTime(2026, 1, 1),
      rowVersion: 0,
    );

class _FakeBooksRepo implements IChequeBooksRepository {
  _FakeBooksRepo({List<db.ChequeBookData>? books})
      : books = books ?? [_book()];

  final List<db.ChequeBookData> books;
  final List<Map<String, Object?>> allocations = [];

  /// ⚠️ **يُرجع ما بعدَ المعاين عمداً** — جهازٌ آخرُ سحب قبلنا. فلو كتبت
  ///    الشاشةُ ما عاينَته ظهر الفرقُ هنا.
  @override
  Future<List<int>> allocateChequeNumbers({
    required int bookId,
    required int count,
  }) async {
    allocations.add({'bookId': bookId, 'count': count});
    return [for (var i = 0; i < count; i++) 140 + i];
  }

  @override
  Stream<List<db.ChequeBookData>> watchChequeBooks() => Stream.value(books);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

class _FakePapersRepo implements ICommercialPapersRepository {
  final List<Map<String, Object?>> created = [];

  @override
  Future<int> createPaper({
    required String paperNumber,
    required String type,
    required String direction,
    required int partyId,
    required double amount,
    required DateTime issueDate,
    required DateTime dueDate,
    String? bankName,
    int? safeId,
    String? accountNumber,
    String? notes,
    String? globalId,
    int? sourceVoucherId,
    int? chequeBookId,
  }) async {
    created.add({
      'paperNumber': paperNumber,
      'amount': amount,
      'chequeBookId': chequeBookId,
    });
    return created.length;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

class _FakeTreasuryRepo implements ITreasuryRepository {
  final List<Map<String, Object?>> vouchers = [];

  @override
  Future<int> createPaymentVoucher({
    required double amount,
    double discount = 0,
    required String category,
    int? safeId,
    int? partyId,
    String? description,
    int? costCenterId,
    String? paperNumber,
    String? paperType,
    String? paperBankName,
    DateTime? paperDueDate,
    DateTime? paperIssueDate,
    int? userId,
    int? operatingBranchId,
    String? globalId,
    bool manualEntry = false,
    int? currencyId,
    double? paymentRate,
    double? foreignAmount,
  }) async {
    vouchers.add({'paperNumber': paperNumber, 'amount': amount});
    return 77;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

class _FakeAccountingRepo implements IAccountingRepository {
  @override
  Future<List<db.CostCenter>> getActiveCostCenters() async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

class _FakeActivityLog implements IActivityLogRepository {
  @override
  Future<int> logActivity({
    required int? userId,
    required String userName,
    required String action,
    required String entityType,
    int? entityId,
    required String description,
    String? oldValue,
    String? newValue,
    double? amount,
    String? ipAddress,
    String? deviceInfo,
    int? branchId,
  }) async =>
      1;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

Future<void> _pump(
  WidgetTester tester, {
  required _FakeBooksRepo books,
  required _FakePapersRepo papers,
  required _FakeTreasuryRepo treasury,
}) async {
  tester.view.physicalSize = const Size(1600, 1100);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        chequeBooksRepositoryProvider.overrideWithValue(books),
        commercialPapersRepositoryProvider.overrideWithValue(papers),
        treasuryRepositoryProvider.overrideWithValue(treasury),
        accountingRepositoryProvider.overrideWithValue(_FakeAccountingRepo()),
        activityLogRepositoryProvider.overrideWithValue(_FakeActivityLog()),
        allPartiesProvider.overrideWith((ref) => Stream.value([_supplier()])),
        scopedSafesProvider.overrideWith((ref) => Stream.value(const [
              SafeData(
                id: 1,
                name: 'خزنة رئيسية',
                safeType: 'cash',
                balance: 0,
                isDefault: true,
                isActive: true,
              ),
            ])),
        // ⚠️ يلمس `databaseProvider` — وبلا تجاوزٍ تُفتَح قاعدةٌ حقيقيّةٌ
        //    ويتعلّق `pumpAndSettle`.
        voucherOpenInvoicesProvider.overrideWith((ref, key) async => const []),
        activeBranchIdProvider.overrideWith((ref) async => 1),
        currentUserPermissionsProvider
            .overrideWith((ref) async => const ['treasury_view']),
      ],
      child: const MaterialApp(home: PaymentVoucherPicposScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _fillChequeVoucher(
  WidgetTester tester, {
  required bool pickBook,
  String typedNumber = '999',
}) async {
  await tester.tap(find.byKey(const Key('voucher_party')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('مورد الشمال').last);
  await tester.pumpAndSettle();

  await tester.tap(find.byKey(const Key('voucher_method_check')));
  await tester.pumpAndSettle();

  if (pickBook) {
    await tester.tap(find.byKey(const Key('voucher_cheque_book')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('A-1 · متبقٍّ 100').last);
    await tester.pumpAndSettle();
  } else {
    await tester.enterText(
        find.widgetWithText(TextField, 'رقم الشيك').first, typedNumber);
    await tester.pumpAndSettle();
  }

  await tester.enterText(
      find.widgetWithText(TextField, 'المبلغ').first, '500');
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(InputDecorator, 'اختر التاريخ').first);
  await tester.pumpAndSettle();
  await tester.tap(find.text('OK').last);
  await tester.pumpAndSettle();

  await tester.tap(find.text('مراجعة واعتماد'));
  await tester.pumpAndSettle();
  await _drainToasts(tester);
}

/// ⚠️ `AppToast` يجدول مؤقّتاً — وتفكيكُ الشجرة قبل انقضائه يُسقط الاختبارَ
///    بـ«A Timer is still pending».
Future<void> _drainToasts(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 6));
}

Future<void> _teardownTree(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
}

void main() {
  testWidgets('🔴 الرقمُ المسحوبُ هو ما يصل الورقةَ — لا رقمُ المعاينة',
      (tester) async {
    final books = _FakeBooksRepo();
    final papers = _FakePapersRepo();
    final treasury = _FakeTreasuryRepo();
    await _pump(
        tester, books: books, papers: papers, treasury: treasury);

    await _fillChequeVoucher(tester, pickBook: true);

    // ‏١) سُحب فعلاً — وبقدر الشيكات.
    expect(books.allocations, hasLength(1),
        reason: '🔴 لم يُنادَ السحبُ إطلاقاً ⇒ `next_number` لا يتقدّم '
            'أبداً، ويُصدَر الرقمُ نفسُه لكلّ مورّد');
    expect(books.allocations.single, {'bookId': 3, 'count': 1});

    // ‏٢) 🔴 والمكتوبُ هو المسحوبُ (١٤٠) لا المعاينُ (١٠١).
    expect(papers.created, hasLength(1));
    expect(papers.created.single['paperNumber'], 'CHK-140',
        reason: '🔴 كُتب رقمُ المعاينة — وهو يبطُل لحظةَ يسحب جهازٌ آخر، '
            'فيخرج شيكان بنفس الرقم إلى البنك');
    expect(papers.created.single['chequeBookId'], 3,
        reason: '🔴 الورقةُ بلا دفترها ⇒ تقدّم الدفترُ وبقي مصدرُها مجهولاً');

    // ‏٣) ووصفُ السند يحمل الرقمَ نفسَه — لا رقماً ثالثاً.
    expect(treasury.vouchers.single['paperNumber'], 'CHK-140',
        reason: 'سندٌ يصف رقماً غيرَ الذي كُتب على الورقة');
    await _teardownTree(tester);
  });

  testWidgets('⚠️ وبلا دفترٍ يُكتَب ما كتبه المستخدمُ ولا يُسحَب شيء',
      (tester) async {
    final books = _FakeBooksRepo();
    final papers = _FakePapersRepo();
    final treasury = _FakeTreasuryRepo();
    await _pump(
        tester, books: books, papers: papers, treasury: treasury);

    await _fillChequeVoucher(tester, pickBook: false, typedNumber: '999');

    // ⚠️ دفاترُ قديمةٌ لم تُسجَّل وشيكٌ مصرفيٌّ من غير دفترنا — ومنعُ اليد
    //    كان يوقف الصرفَ حتى يُسجَّل كلُّ دفترٍ في الدرج.
    expect(books.allocations, isEmpty,
        reason: '⚠️ سُحب من دفترٍ لم يختره أحد ⇒ أرقامٌ تحترق بلا سبب');
    expect(papers.created.single['paperNumber'], '999');
    expect(papers.created.single['chequeBookId'], isNull);
    await _teardownTree(tester);
  });

  testWidgets('🔴 ولا يُعرَض دفترٌ ملغًى ولا منتهٍ — وعدٌ يُرفَض عند الحفظ',
      (tester) async {
    // 🔴 خيارٌ يُعرَض ثمّ يُرفَض عند الحفظ **بعد أن مُلئ السندُ كلُّه** وعدٌ
    //    كاذب: المستخدمُ اختار دفتراً، وكتب المبالغَ والتواريخ، ثمّ سقط
    //    بـ«الدفتر ملغى». والإقصاءُ هنا لا في المحرّك وحدَه.
    final books = _FakeBooksRepo(books: [
      _book(id: 3, number: 'ملغى', status: 'cancelled'),
      _book(id: 4, number: 'منتهٍ', next: 201, status: 'exhausted'),
    ]);
    await _pump(
      tester,
      books: books,
      papers: _FakePapersRepo(),
      treasury: _FakeTreasuryRepo(),
    );

    await tester.tap(find.byKey(const Key('voucher_method_check')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('voucher_cheque_book')), findsNothing,
        reason: '🔴 مُنتقٍ يُعرَض بدفاترَ لا يُسحَب من أيٍّ منها — يختار '
            'المستخدمُ ويملأ السندَ كلَّه ثمّ يسقط بـ«الدفتر ملغى»');
    // وحقلُ الرقم يبقى محرَّراً — لا شيءَ يملؤه.
    expect(find.widgetWithText(TextField, 'رقم الشيك'), findsOneWidget);
    await _teardownTree(tester);

    // ⚠️ **مرساةٌ موجبةٌ في نفس الاختبار**: بلا هذه يمرّ `findsNothing`
    //    أعلاه لو تبدّل المفتاحُ أو اختفى المنتقي كلُّه.
    final live = _FakeBooksRepo(books: [_book()]);
    await _pump(
      tester,
      books: live,
      papers: _FakePapersRepo(),
      treasury: _FakeTreasuryRepo(),
    );
    await tester.tap(find.byKey(const Key('voucher_method_check')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('voucher_cheque_book')), findsOneWidget);
    await _teardownTree(tester);
  });

  testWidgets('🔴 وشيكان يسحبان رقمَين لا رقماً', (tester) async {
    final books = _FakeBooksRepo();
    final papers = _FakePapersRepo();
    final treasury = _FakeTreasuryRepo();
    await _pump(
        tester, books: books, papers: papers, treasury: treasury);

    await tester.tap(find.byKey(const Key('voucher_party')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('مورد الشمال').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('voucher_method_check')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('voucher_cheque_book')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('A-1 · متبقٍّ 100').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('voucher_add_cheque')));
    await tester.pumpAndSettle();

    for (var i = 0; i < 2; i++) {
      await tester.enterText(
          find.widgetWithText(TextField, 'المبلغ').at(i), '${(i + 1) * 100}');
      await tester.pumpAndSettle();
      await tester
          .tap(find.widgetWithText(InputDecorator, 'اختر التاريخ').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK').last);
      await tester.pumpAndSettle();
    }

    await tester.tap(find.text('مراجعة واعتماد'));
    await tester.pumpAndSettle();
    await _drainToasts(tester);

    expect(books.allocations.single['count'], 2);
    // 🔴 ومبلغُ كلِّ شيكٍ كما كُتب — لا قسمةً بالتساوي.
    expect(
      papers.created.map((p) => (p['paperNumber'], p['amount'])).toList(),
      [('CHK-140', 100.0), ('CHK-141', 200.0)],
    );
    await _teardownTree(tester);
  });
}
