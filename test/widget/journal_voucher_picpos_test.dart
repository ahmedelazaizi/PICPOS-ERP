// «سند قيد» — تصميمُ المالك `(14)`.
//
// ═══ ما يقيسه هذا الملفّ ═══
//
// ‏١) 🔴 **رقمُ السند لا يُخمَّن.** التصميمُ يعرض `JV-0031` وشارةَ «مسودة»،
//    والرقمُ يُولَّد **داخلَ معاملة الحفظ** (‏Spec 066) — فقبلها لا رقمَ
//    موجود. ورقمٌ مخمَّنٌ على الشاشة يُنقَل إلى دفترٍ ورقيٍّ ثمّ يُحفَظ غيرُه.
//
// ‏٢) 🔴 **و«المرجع» يصل القاعدة.** العمودُ `journal_entries.reference`
//    مزروعٌ منذ v174 بلا كاتبٍ ولا قارئ، وهذه الشاشةُ أوّلُ مَن يكتبه.
//    وحقلٌ يُكتَب فيه ولا يُخزَّن أسوأُ من حقلٍ غائب.
//
// ‏٣) 🔴 **والزرّان لا يعنيان الشيءَ نفسَه.** «حفظ مسودة» لا يحرّك رصيداً
//    حتى الاعتماد، و«مراجعة وترحيل» يدخل الأستاذَ فوراً. وخلطُهما يُرحّل ما
//    ظُنّ مسودّةً.
//
// ‏٤) **ونسخُ السطر بلا مبالغه** — نسخةٌ تحمل نفسَ المدين تضاعف مبلغاً
//    ماليّاً بنقرةٍ واحدة.
//
// ‏٥) **والنموذجُ يُفرَّغ بعد الترحيل** — وإلّا رُحِّل القيدُ نفسُه مرّتين.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:picpos_erp/data/database/database.dart' as db;
import 'package:picpos_erp/data/providers/auth_providers.dart';
import 'package:picpos_erp/data/providers/repository_providers.dart';
import 'package:picpos_erp/domain/repositories/accounting_repository.dart';
import 'package:picpos_erp/domain/repositories/auth_repository.dart';
import 'package:picpos_erp/presentation/accounting_picpos/journal_voucher_picpos_screen.dart';

db.Account _account(int id, String code, String name) => db.Account(
      id: id,
      code: code,
      name: name,
      accountType: 'expense',
      accountNature: 'detail',
      normalBalance: 'debit',
      level: 2,
      balance: 0,
      isSystem: false,
      isActive: true,
      isHiddenFromEntries: false,
      rowVersion: 1,
    );

final _accounts = [
  _account(51, '5101', 'مصروف الإيجار'),
  _account(11, '1101', 'الصندوق الرئيسي'),
];

/// ما وصل `createJournalEntry` — يُفحَص بدل مراقبة نداءٍ صامت.
class _Saved {
  _Saved({
    required this.description,
    required this.lines,
    required this.asDraft,
    required this.reference,
    required this.referenceType,
    required this.branchId,
  });

  final String description;
  final List<JournalLine> lines;
  final bool asDraft;
  final String? reference;
  final String? referenceType;
  final int? branchId;
}

class _FakeAccountingRepo implements IAccountingRepository {
  final List<_Saved> saved = [];

  @override
  Future<List<db.Account>> getAllAccounts() async => _accounts;

  @override
  Future<List<db.CostCenter>> getCostCenters() async => const [];

  @override
  Stream<List<db.Account>> watchAllAccounts() => Stream.value(_accounts);

  @override
  Future<int> createJournalEntry({
    required String description,
    required DateTime date,
    required List<JournalLine> lines,
    String? referenceType,
    int? referenceId,
    bool isAutoPosted = false,
    int? costCenterId,
    int? branchId,
    bool asDraft = false,
    int? createdBy,
    String? reference,
  }) async {
    saved.add(_Saved(
      description: description,
      lines: lines,
      asDraft: asDraft,
      reference: reference,
      referenceType: referenceType,
      branchId: branchId,
    ));
    return 1;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

/// ⚠️ **بلا مستخدمٍ مسجَّلٍ لا يصل شيءٌ إلى المستودع**: `_save` يرتدّ عند
/// `authProvider.user == null` — فيبدو الاختبارُ كأنّه يقيس الحفظَ وهو يقيس
/// تسجيلَ الدخول.
class _SignedInAuth extends AuthNotifier {
  @override
  AuthState build() => AuthState(
        isAuthenticated: true,
        userWithRole: db.UserWithRole(
          user: db.User(
            id: 1,
            username: 'tester',
            passwordHash: '',
            passwordSalt: '',
            displayName: 'مُدخِل القيود',
            defaultScreen: '0',
            isLocked: false,
            isActive: true,
            discountLimitIsPercent: true,
            forcePasswordChange: false,
            createdAt: DateTime(2026, 1, 1),
            rowVersion: 1,
          ),
        ),
      );
}

class _FakeAuthRepo implements IAuthRepository {
  _FakeAuthRepo({this.allowed = true});

  final bool allowed;
  final List<String> asked = [];

  @override
  Future<bool> userHasPermission(int userId, String code) async {
    asked.add(code);
    return allowed;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

Future<void> _pump(
  WidgetTester tester, {
  double width = 1440,
  _FakeAccountingRepo? repo,
  _FakeAuthRepo? auth,
}) async {
  tester.view.physicalSize = Size(width, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        accountingRepositoryProvider
            .overrideWithValue(repo ?? _FakeAccountingRepo()),
        authRepositoryProvider.overrideWithValue(auth ?? _FakeAuthRepo()),
        authProvider.overrideWith(_SignedInAuth.new),
        allBranchesProvider.overrideWith((ref) => Stream.value(const [])),
        currentUserPermissionsProvider
            .overrideWith((ref) async => const ['settings_view']),
      ],
      child: const MaterialApp(home: JournalVoucherPicposScreen()),
    ),
  );
  await tester.pump();
  await tester.pump();
  await tester.pump();
}

Future<void> _teardownTree(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 6));
  await tester.pumpAndSettle();
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
}

/// حقولُ نوعٍ بعينه — **بالتزيين لا بنصٍّ مجاور**.
///
/// ⚠️ `find.widgetWithText` يبحث في **أبناء** الودجت، ومنتقي الحساب لا
/// `labelText` له أصلاً (تلميحٌ داخل الحقل)، وصفُّ السطر يحمل نصوصاً أخرى.
/// فالمطابقةُ على `InputDecoration` نفسِها.
Finder _fieldsByHint(String hint) => find.byWidgetPredicate(
    (w) => w is TextField && w.decoration?.hintText == hint);

Finder _fieldsByLabel(String label) => find.byWidgetPredicate(
    (w) => w is TextField && w.decoration?.labelText == label);

const _accountHint = 'اكتب اسم أو رمز الحساب...';

/// يملأ سطراً: حسابٌ بالبحث ثمّ مبلغٌ في الطرف المطلوب.
Future<void> _fillLine(
  WidgetTester tester,
  int index, {
  required String accountCode,
  required String accountName,
  double? debit,
  double? credit,
}) async {
  await tester.enterText(_fieldsByHint(_accountHint).at(index), accountCode);
  await tester.pumpAndSettle();
  // ⚠️ **يُختار بالإرسال لا بنقر الاقتراح**: صفُّ الاقتراح يرسم الرمزَ
  //    والاسمَ في **نصّين منفصلَين**، فلا `find.text` واحدٌ يطابق
  //    «٥١٠١ - مصروف الإيجار». و`onSubmitted` يختار المظلَّلَ وهو الأوّل.
  await tester.testTextInput.receiveAction(TextInputAction.done);
  await tester.pumpAndSettle();
  expect(find.text('$accountCode - $accountName'), findsWidgets,
      reason: 'لم يُختَر الحسابُ «$accountName» في السطر $index');

  if (debit != null) {
    await tester.enterText(
        _fieldsByLabel('مدين').at(index), debit.toStringAsFixed(0));
  }
  if (credit != null) {
    await tester.enterText(
        _fieldsByLabel('دائن').at(index), credit.toStringAsFixed(0));
  }
  await tester.pumpAndSettle();
}

/// يملأ سنداً متوازناً ١٠٠٠ / ١٠٠٠.
Future<void> _fillBalanced(WidgetTester tester) async {
  await tester.enterText(
      find.byKey(const Key('journal_voucher_description')), 'إثبات مصروف إيجار');
  await tester.pumpAndSettle();
  await _fillLine(tester, 0,
      accountCode: '5101', accountName: 'مصروف الإيجار', debit: 1000);
  await _fillLine(tester, 1,
      accountCode: '1101', accountName: 'الصندوق الرئيسي', credit: 1000);
}

void main() {
  group('🔴 رقمُ السند', () {
    testWidgets('لا يُخمَّن قبل الحفظ', (tester) async {
      await _pump(tester);
      expect(find.textContaining(kJournalVoucherNumberPlaceholder),
          findsOneWidget,
          reason: '🔴 رقمٌ مخمَّنٌ يُنقَل إلى دفترٍ ورقيٍّ ثمّ يُحفَظ غيرُه');
      expect(find.textContaining('JV-'), findsNothing);
      await _teardownTree(tester);
    });

    testWidgets('ولا شارةَ «مسودة» لمستندٍ لم يوجد', (tester) async {
      await _pump(tester);
      expect(find.text('مسودة'), findsNothing,
          reason: 'شارةٌ تصف مستنداً لم يُنشأ بعد');
      await _teardownTree(tester);
    });
  });

  group('سببُ منعِ الحفظ', () {
    testWidgets('🔴 يُقال ولا يُبتلَع', (tester) async {
      await _pump(tester);
      expect(find.textContaining('اكتب بيان القيد'), findsOneWidget,
          reason: 'زرٌّ معطَّلٌ بلا سببٍ ظاهرٍ يُقرأ «معطوب»');
      await _teardownTree(tester);
    });

    testWidgets('🔴 وقيدٌ غيرُ متوازنٍ لا يُرحَّل', (tester) async {
      final repo = _FakeAccountingRepo();
      await _pump(tester, repo: repo);
      await tester.enterText(
          find.byKey(const Key('journal_voucher_description')), 'قيد ناقص');
      await tester.pumpAndSettle();
      await _fillLine(tester, 0,
          accountCode: '5101', accountName: 'مصروف الإيجار', debit: 1000);
      await _fillLine(tester, 1,
          accountCode: '1101', accountName: 'الصندوق الرئيسي', credit: 400);

      expect(find.text('غير متوازن'), findsOneWidget);
      final post = tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, 'مراجعة وترحيل'));
      expect(post.onPressed, isNull);
      expect(repo.saved, isEmpty);
      await _teardownTree(tester);
    });
  });

  group('🔴 الحفظ', () {
    testWidgets('«مراجعة وترحيل» ترحّل و«حفظ مسودة» لا ترحّل', (tester) async {
      final repo = _FakeAccountingRepo();
      await _pump(tester, repo: repo);
      await _fillBalanced(tester);
      expect(find.text('متوازن'), findsOneWidget);

      await tester.tap(find.widgetWithText(OutlinedButton, 'حفظ مسودة'));
      await tester.pumpAndSettle();
      expect(repo.saved, hasLength(1));
      expect(repo.saved.single.asDraft, isTrue,
          reason: '🔴 مسوّدةٌ تُرحَّل تحرّك أرصدةً ظُنّ أنّها تنتظر اعتماداً');

      await _fillBalanced(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'مراجعة وترحيل'));
      await tester.pumpAndSettle();
      expect(repo.saved, hasLength(2));
      expect(repo.saved.last.asDraft, isFalse);
      await _teardownTree(tester);
    });

    testWidgets('🔴 و«المرجع» يصل القاعدة', (tester) async {
      final repo = _FakeAccountingRepo();
      await _pump(tester, repo: repo);
      await _fillBalanced(tester);
      await tester.enterText(
          find.byKey(const Key('journal_voucher_reference')), 'عقد إيجار ٢٠٢٦');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'مراجعة وترحيل'));
      await tester.pumpAndSettle();

      expect(repo.saved.single.reference, 'عقد إيجار ٢٠٢٦',
          reason: '🔴 العمودُ مزروعٌ منذ v174 بلا كاتب — وحقلٌ يُكتَب فيه '
              'ولا يُخزَّن أسوأُ من حقلٍ غائب');
      // ⚠️ **وليس `referenceType`**: ذاك مفرداتٌ مغلقةٌ يُرشَّح بها.
      expect(repo.saved.single.referenceType, 'daily');
      await _teardownTree(tester);
    });

    testWidgets('والمرجعُ الفارغُ يبقى فارغاً لا سلسلةً خاوية',
        (tester) async {
      final repo = _FakeAccountingRepo();
      await _pump(tester, repo: repo);
      await _fillBalanced(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'مراجعة وترحيل'));
      await tester.pumpAndSettle();
      expect(repo.saved.single.reference, isNull,
          reason: "سلسلةٌ خاويةٌ تُقرأ «مرجعٌ موجودٌ فارغ» في كلّ ترشيح");
      await _teardownTree(tester);
    });

    testWidgets('🔴 والصلاحيةُ تُفحَص عند الضغط', (tester) async {
      final repo = _FakeAccountingRepo();
      final auth = _FakeAuthRepo(allowed: false);
      await _pump(tester, repo: repo, auth: auth);
      await _fillBalanced(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'مراجعة وترحيل'));
      await tester.pumpAndSettle();

      expect(auth.asked, contains('accounting_journal'),
          reason: '🔴 الشاشةُ تُفتَح بـ`settings_view` — والترحيلُ بلا فحصٍ '
              'يجعل كلَّ من يرى الإعدادات يرحّل قيوداً');
      expect(repo.saved, isEmpty);
      await _teardownTree(tester);
    });

    testWidgets('🔴 والنموذجُ يُفرَّغ بعد الترحيل', (tester) async {
      final repo = _FakeAccountingRepo();
      await _pump(tester, repo: repo);
      await _fillBalanced(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'مراجعة وترحيل'));
      await tester.pumpAndSettle();

      expect(find.textContaining('اكتب بيان القيد'), findsOneWidget,
          reason: '🔴 شاشةٌ تبقى ممتلئةً تُغري بضغطةٍ ثانية — ولا شيءَ في '
              'المحرّك يمنع قيداً ثانياً مطابقاً');
      await _teardownTree(tester);
    });
  });

  group('السطور', () {
    testWidgets('🔴 نسخُ السطر ينقل بنيتَه لا مبالغَه', (tester) async {
      await _pump(tester);
      await _fillLine(tester, 0,
          accountCode: '5101', accountName: 'مصروف الإيجار', debit: 1000);
      await tester.tap(find.byTooltip('نسخ السطر').first);
      await tester.pumpAndSettle();

      final debits =
          tester.widgetList<TextField>(_fieldsByLabel('مدين')).toList();
      expect(debits, hasLength(3), reason: 'السطرُ لم يُنسَخ');
      expect(debits[1].controller?.text, '',
          reason: '🔴 نسخةٌ تحمل نفسَ المدين تضاعف مبلغاً ماليّاً بنقرةٍ '
              'واحدة — والغرضُ تكرارُ بنيةِ السطر لا مبلغِه');
      await _teardownTree(tester);
    });

    testWidgets('⚠️ ولا يقلّ القيدُ عن سطرين', (tester) async {
      await _pump(tester);
      // ⚠️ `IconButton` **يلفّ** التلميحَ لا العكس، فالبحثُ عن السلف.
      final del = tester
          .widgetList<IconButton>(find.ancestor(
            of: find.byTooltip('لا يقلّ القيد عن سطرين'),
            matching: find.byType(IconButton),
          ))
          .toList();
      expect(del, hasLength(2));
      expect(del.every((b) => b.onPressed == null), isTrue,
          reason: 'قيدٌ بسطرٍ واحدٍ لا يتّزن أبداً — ونموذجٌ لا يُحفَظ');
      await _teardownTree(tester);
    });
  });

  group('ومراسي تركيب', () {
    for (final w in const [1100.0, 1440.0, 1920.0]) {
      testWidgets('الشاشةُ بلا فيضٍ عند ${w ~/ 1}', (tester) async {
        await _pump(tester, width: w);
        expect(tester.takeException(), isNull);
        expect(find.text('سند قيد'), findsWidgets);
        expect(find.text('تفاصيل القيد'), findsOneWidget);
        await _teardownTree(tester);
      });
    }
  });
}
