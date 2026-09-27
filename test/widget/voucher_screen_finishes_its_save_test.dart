// 🔴 **سندٌ حُفظ لا يبقى على الشاشة ممتلئاً** — وإلّا كُتب مرّتين.
//
// ═══ ما يُقاس، ولماذا هو مالٌ لا تخطيط ═══
//
// `receipt_voucher_picpos_screen.dart` و`payment_voucher_picpos_screen.dart`
// ينهيان الحفظَ بـ:
//
//     _toast('تم حفظ سند القبض', ToastType.success);
//     Navigator.of(context).maybePop();
//
// والشاشتان تُبلَغان من الشريط الجانبيّ وحدَه، فجسمُهما هو **المسارُ الأوّل**
// في ملّاح القشرة المتداخل (`appShellNestedNavigatorKey` في `app_shell.dart`:
// ‏`Navigator(onGenerateRoute: … builder: widget.child)`). و`maybePop` على
// المسار الأوّل تُرجع `false` ولا تفعل شيئاً.
//
// ⇒ فالسندُ يُكتَب، وتخرج رسالةُ النجاح، **وتبقى الاستمارةُ ممتلئةً كما
// هي**: نفسُ الطرف، ونفسُ المبلغ، ونفسُ الشيكات. وضغطةٌ ثانيةٌ على «مراجعة
// واعتماد» تكتب سنداً ثانياً مطابقاً — ولا شيءَ في المحرّك يردّه، فهو سندٌ
// مشروعٌ تماماً من وجهة نظره. وزرُّ «رجوع» ميّتٌ بنفس السبب.
//
// ═══ وهذا العطبُ **معروفٌ ومُصلَحٌ في أختهما** ═══
//
// `journal_voucher_picpos_screen.dart` يُنهي حفظَه بـ`_resetForm()` وفوقَها
// حرفيّاً:
//
//     /// نموذجٌ نظيفٌ بعد الحفظ — **وإلّا رُحِّل القيدُ نفسُه مرّتين.**
//
// فالخطرُ مُقاسٌ ومكتوبٌ في هذه الشجرة؛ سندا القبض والصرف وحدَهما فاتهما.
//
// ═══ ⚠️ ولماذا مرساةٌ «مدفوعاً» في نفس الملفّ ═══
//
// `maybePop` **تعمل** حين تكون الشاشةُ مدفوعةً فوق مسارٍ آخر — وهو ما ستصير
// إليه بعد خ‑٩ (‏تُفتَح من زرّ «جديد» في شاشة السجلّ). فبلا المرساة يبدو
// الفحصُ أعلاه وكأنّه يشترط شيئاً مستحيلاً، ويُسكَت غداً بحجّة «كذا يعمل».
// المرساةُ تُثبت أنّ الآليّةَ سليمةٌ وأنّ المقيسَ هو **الجذرُ** وحدَه.

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
import 'package:ural_erp/domain/repositories/treasury_repository.dart';
import 'package:ural_erp/presentation/treasury_picpos/screens/payment_voucher_picpos_screen.dart';
import 'package:ural_erp/presentation/treasury_picpos/screens/receipt_voucher_picpos_screen.dart';

// ═══════════════════════════════════════════════════════════════════════
// أطرافٌ ومستودعاتٌ وهميّة — أخفُّ ما يُكمل مسارَ الحفظ
// ═══════════════════════════════════════════════════════════════════════

db.Party _party({required bool customer}) => db.Party(
      id: customer ? 7 : 5,
      name: customer ? 'عميل الجنوب' : 'مورد الشمال',
      isCustomer: customer,
      isSupplier: !customer,
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

/// يعدّ السنداتِ المكتوبة — فالقياسُ على **ما وصل القاعدة** لا على الشاشة.
class _CountingTreasuryRepo implements ITreasuryRepository {
  final List<double> receipts = [];
  final List<double> payments = [];

  @override
  Future<int> createReceiptVoucher({
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
    int? linkedAccountId,
    int? operatingBranchId,
    String? globalId,
    int? userId,
    bool manualEntry = false,
  }) async {
    receipts.add(amount);
    return receipts.length;
  }

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
  }) async {
    payments.add(amount);
    return payments.length;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

/// ⚠️ **سندُ الصرف وحدَه يراقبُ دفاترَ الشيكات** — وبلا تجاوزٍ
/// تُفتَح قاعدةٌ حقيقيّةٌ ويسقط الاختبارُ بـ«A Timer is still pending».
class _FakeBooksRepo implements IChequeBooksRepository {
  @override
  Stream<List<db.ChequeBookData>> watchChequeBooks() =>
      Stream.value(const []);

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

/// ⚠️ **تُعيد النطاقَ لا قائمةَ التجاوزات**: `Override` غيرُ مُصدَّرٍ من
/// flutter_riverpod 3، فلا نوعَ يُكتَب لقائمةٍ تُمرَّر.
Widget _scope(_CountingTreasuryRepo treasury, {required Widget child}) =>
    ProviderScope(
      overrides: [
        treasuryRepositoryProvider.overrideWithValue(treasury),
        accountingRepositoryProvider.overrideWithValue(_FakeAccountingRepo()),
        chequeBooksRepositoryProvider.overrideWithValue(_FakeBooksRepo()),
        activityLogRepositoryProvider.overrideWithValue(_FakeActivityLog()),
        allPartiesProvider.overrideWith(
          (ref) => Stream.value([_party(customer: true), _party(customer: false)]),
        ),
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
      child: child,
    );

void _sizeView(WidgetTester tester) {
  tester.view.physicalSize = const Size(1600, 1100);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  // ⚠️ **التفكيكُ بـ`addTearDown` لا بنداءٍ في آخر الاختبار**: توكيدٌ
  //    يرمي يتخطّى السطرَ الأخير، فتبقى الشجرةُ مركّبةً وتسقط
  //    مؤقّتاتُ drift على **الاختبار التالي** بـ«A Timer is still
  //    pending» — فيُقرأُ الفشلُ على من لم يُخطئ.
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}

/// تُركَّب الشاشةُ **جسماً لمسارٍ أوّل** — كما تُبلَغ اليومَ من الشريط.
Future<void> _pumpAtRoot(
  WidgetTester tester,
  Widget screen,
  _CountingTreasuryRepo treasury,
) async {
  _sizeView(tester);
  await tester.pumpWidget(
    _scope(treasury, child: MaterialApp(home: screen)),
  );
  await tester.pumpAndSettle();
}

/// وتُدفَع فوق مسارٍ قائم — كما ستُفتَح من زرّ «جديد» بعد خ‑٩.
Future<void> _pumpPushed(
  WidgetTester tester,
  Widget screen,
  _CountingTreasuryRepo treasury,
) async {
  _sizeView(tester);
  final navKey = GlobalKey<NavigatorState>();
  await tester.pumpWidget(
    _scope(
      treasury,
      child: MaterialApp(
        navigatorKey: navKey,
        home: const Scaffold(body: Center(child: Text('شاشةُ السجلّ'))),
      ),
    ),
  );
  await tester.pumpAndSettle();
  unawaited(navKey.currentState!
      .push(MaterialPageRoute<void>(builder: (_) => screen)));
  await tester.pumpAndSettle();
}

void unawaited(Future<void> _) {}

/// يملأ سنداً نقديّاً ويعتمده. يُعيد المبلغَ المكتوب.
Future<String> _fillAndSubmit(WidgetTester tester,
    {required String partyName}) async {
  await tester.tap(find.byKey(const Key('voucher_party')));
  await tester.pumpAndSettle();
  await tester.tap(find.text(partyName).last);
  await tester.pumpAndSettle();

  await tester.enterText(find.byKey(const Key('voucher_amount')), '750');
  await tester.pumpAndSettle();

  await tester.tap(find.text('مراجعة واعتماد'));
  await tester.pumpAndSettle();
  // ⚠️ `AppToast` يجدول مؤقّتاً — وتفكيكُ الشجرة قبل انقضائه يُسقط
  //    الاختبارَ بـ«A Timer is still pending».
  await tester.pump(const Duration(seconds: 6));
  return '750';
}

/// نصُّ حقل المبلغ كما هو على الشاشة الآن.
String _amountOnScreen(WidgetTester tester) {
  final field = tester.widget<TextField>(
    find.descendant(
      of: find.byKey(const Key('voucher_amount')),
      matching: find.byType(TextField),
      matchRoot: true,
    ),
  );
  return field.controller?.text ?? '';
}

void main() {
  group('سندُ القبض', () {
    testWidgets('مرساةٌ — الحفظُ يصل القاعدةَ فعلاً', (tester) async {
      // بلا هذه يمرّ كلُّ ما تحتها لو لم يُنفَّذ الحفظُ أصلاً.
      final treasury = _CountingTreasuryRepo();
      await _pumpAtRoot(
          tester, const ReceiptVoucherPicposScreen(), treasury);
      await _fillAndSubmit(tester, partyName: 'عميل الجنوب');
      expect(treasury.receipts, hasLength(1),
          reason: 'لم يُكتَب سندٌ — فالمسارُ المقيسُ تحتَه لا يعني شيئاً');
    });

    testWidgets('🔴 ولا تبقى الاستمارةُ ممتلئةً بعده', (tester) async {
      final treasury = _CountingTreasuryRepo();
      await _pumpAtRoot(
          tester, const ReceiptVoucherPicposScreen(), treasury);
      await _fillAndSubmit(tester, partyName: 'عميل الجنوب');

      final stillThere = find.byKey(const Key('voucher_amount')).evaluate();
      if (stillThere.isNotEmpty) {
        expect(_amountOnScreen(tester), isEmpty,
            reason: '🔴 السندُ حُفظ والمبلغُ ما زال في الحقل — وضغطةٌ ثانيةٌ '
                'على «مراجعة واعتماد» تكتب سنداً ثانياً مطابقاً، ولا شيءَ '
                'في المحرّك يردّه');
      }
    });

    testWidgets('🔴 وضغطةٌ ثانيةٌ لا تكتب سنداً ثانياً', (tester) async {
      final treasury = _CountingTreasuryRepo();
      await _pumpAtRoot(
          tester, const ReceiptVoucherPicposScreen(), treasury);
      await _fillAndSubmit(tester, partyName: 'عميل الجنوب');

      final submit = find.text('مراجعة واعتماد');
      if (submit.evaluate().isNotEmpty) {
        await tester.tap(submit);
        await tester.pumpAndSettle();
        await tester.pump(const Duration(seconds: 6));
      }
      expect(treasury.receipts, hasLength(1),
          reason: '🔴 كُتب سندُ قبضٍ مرّتين بضغطتَين — مالٌ مزدوجٌ على '
              'العميل وفي الخزنة');
    });
  });

  group('سندُ الصرف', () {
    testWidgets('مرساةٌ — الحفظُ يصل القاعدةَ فعلاً', (tester) async {
      final treasury = _CountingTreasuryRepo();
      await _pumpAtRoot(
          tester, const PaymentVoucherPicposScreen(), treasury);
      await _fillAndSubmit(tester, partyName: 'مورد الشمال');
      expect(treasury.payments, hasLength(1),
          reason: 'لم يُكتَب سندٌ — فالمسارُ المقيسُ تحتَه لا يعني شيئاً');
    });

    testWidgets('🔴 ولا تبقى الاستمارةُ ممتلئةً بعده', (tester) async {
      final treasury = _CountingTreasuryRepo();
      await _pumpAtRoot(
          tester, const PaymentVoucherPicposScreen(), treasury);
      await _fillAndSubmit(tester, partyName: 'مورد الشمال');

      if (find.byKey(const Key('voucher_amount')).evaluate().isNotEmpty) {
        expect(_amountOnScreen(tester), isEmpty,
            reason: '🔴 السندُ حُفظ والمبلغُ ما زال في الحقل — وضغطةٌ ثانيةٌ '
                'تكتب صرفاً ثانياً من الخزنة');
      }
    });

    testWidgets('🔴 وضغطةٌ ثانيةٌ لا تكتب سنداً ثانياً', (tester) async {
      final treasury = _CountingTreasuryRepo();
      await _pumpAtRoot(
          tester, const PaymentVoucherPicposScreen(), treasury);
      await _fillAndSubmit(tester, partyName: 'مورد الشمال');

      final submit = find.text('مراجعة واعتماد');
      if (submit.evaluate().isNotEmpty) {
        await tester.tap(submit);
        await tester.pumpAndSettle();
        await tester.pump(const Duration(seconds: 6));
      }
      expect(treasury.payments, hasLength(1),
          reason: '🔴 صُرف مرّتين بضغطتَين — نقصٌ حقيقيٌّ في الخزنة');
    });
  });

  testWidgets('✅ ومرساةُ الآليّة — مدفوعةً فوق مسارٍ تُغلَق بنفسها',
      (tester) async {
    // راجع رأسَ الملفّ: `maybePop` سليمةٌ، والمقيسُ أعلاه هو **الجذرُ**
    // وحدَه. وهذه هي الحالُ التي ستصير إليها الشاشةُ بعد خ‑٩.
    final treasury = _CountingTreasuryRepo();
    await _pumpPushed(tester, const ReceiptVoucherPicposScreen(), treasury);
    expect(find.byKey(const Key('voucher_amount')), findsOneWidget,
        reason: 'لم تُدفَع الاستمارةُ أصلاً — المرساةُ لا تقيس شيئاً');

    await _fillAndSubmit(tester, partyName: 'عميل الجنوب');

    expect(treasury.receipts, hasLength(1));
    expect(find.text('شاشةُ السجلّ'), findsOneWidget,
        reason: 'لم يُعَد إلى ما تحتها بعد الحفظ');
    expect(find.byKey(const Key('voucher_amount')), findsNothing,
        reason: 'بقيت الاستمارةُ مدفوعةً بعد الحفظ');
  });
}
