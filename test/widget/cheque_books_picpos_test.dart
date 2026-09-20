// «دفتر الشيكات» — أوّلُ ضابطٍ لترقيم الشيك الصادر.
//
// ═══ ما يقيسه هذا الملفّ ═══
//
// ‏١) 🔴 **الشاشةُ كاتبةٌ لا عارضة** — الجدولُ شُحن في v174 بلا كاتب.
//
// ‏٢) 🔴 **والتداخلُ يُقال قبل الضغط.** دفتران متداخلان على نفس الحساب
//    يعنيان رقماً مكرَّراً **يصل البنك**، والحارسُ القائمُ في
//    `commercial_papers_dao` يقارن `bankName` نصّاً حرّاً فيسقط عند أوّل
//    اختلافِ إملاء.
//
// ‏٣) 🔴 **والبنكُ خزنةٌ بنكيّةٌ لها حسابٌ مرتبط** — والثلاثةُ شروطٌ معاً،
//    والمُقصى يُقال لا يُبتلَع.
//
// ‏٤) **وسببُ منعِ الحفظ يُقال**: زرٌّ معطَّلٌ بلا سببٍ ظاهرٍ يُقرأ «معطوب».

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ural_erp/data/database/database.dart' as db;
import 'package:ural_erp/data/providers/auth_providers.dart';
import 'package:ural_erp/data/providers/repository_providers.dart';
import 'package:ural_erp/domain/repositories/treasury_repository.dart';
import 'package:ural_erp/presentation/treasury_picpos/screens/cheque_books_picpos_screen.dart';

db.ChequeBookData _book({
  int id = 1,
  int account = 100,
  String number = 'A-1',
  String? prefix = 'CHK-',
  int from = 101,
  int to = 200,
  int? next,
  String status = 'active',
}) =>
    db.ChequeBookData(
      id: id,
      bankAccountId: account,
      bookNumber: number,
      prefix: prefix,
      fromNumber: from,
      toNumber: to,
      nextNumber: next ?? from,
      status: status,
      createdAt: DateTime(2026, 1, 1),
      rowVersion: 0,
    );

SafeData _safe({
  int id = 1,
  String name = 'بنك مصر',
  String type = 'bank',
  bool active = true,
  int? linked = 100,
  String? bank = 'بنك مصر — فرع وسط البلد',
}) =>
    SafeData(
      id: id,
      name: name,
      safeType: type,
      balance: 0,
      isDefault: false,
      isActive: active,
      bankName: bank,
      linkedAccountId: linked,
    );

class _FakeBooksRepo implements IChequeBooksRepository {
  _FakeBooksRepo({this.books = const []});

  final List<db.ChequeBookData> books;
  final List<Map<String, Object?>> created = [];
  final List<Map<String, Object?>> updated = [];
  final List<Map<String, Object?>> cancelled = [];

  @override
  Stream<List<db.ChequeBookData>> watchChequeBooks() => Stream.value(books);

  @override
  Future<int> createChequeBook({
    required int bankAccountId,
    required String bookNumber,
    required int fromNumber,
    required int toNumber,
    String? prefix,
    int? nextNumber,
    String? notes,
  }) async {
    created.add({
      'bankAccountId': bankAccountId,
      'bookNumber': bookNumber,
      'from': fromNumber,
      'to': toNumber,
      'prefix': prefix,
      'next': nextNumber,
      'notes': notes,
    });
    return 1;
  }

  @override
  Future<void> updateChequeBook({
    required int id,
    required int bankAccountId,
    required String bookNumber,
    required int fromNumber,
    required int toNumber,
    required int nextNumber,
    String? prefix,
    String? notes,
  }) async {
    updated.add({'id': id, 'from': fromNumber, 'to': toNumber, 'next': nextNumber});
  }

  @override
  Future<void> setChequeBookCancelled(int id, bool value) async {
    cancelled.add({'id': id, 'cancelled': value});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

class _FakeTreasuryRepo implements ITreasuryRepository {
  _FakeTreasuryRepo(this.safes);
  final List<SafeData> safes;

  @override
  Stream<List<SafeData>> watchSafes() => Stream.value(safes);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

Future<void> _pump(
  WidgetTester tester, {
  List<db.ChequeBookData> books = const [],
  List<SafeData>? safes,
  _FakeBooksRepo? repo,
  List<String> perms = const ['treasury_view', 'commercial_papers_manage'],
}) async {
  tester.view.physicalSize = const Size(1440, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        chequeBooksRepositoryProvider
            .overrideWithValue(repo ?? _FakeBooksRepo(books: books)),
        treasuryRepositoryProvider
            .overrideWithValue(_FakeTreasuryRepo(safes ?? [_safe()])),
        currentUserPermissionsProvider.overrideWith((ref) async => perms),
      ],
      child: const MaterialApp(home: ChequeBooksPicposScreen()),
    ),
  );
  await tester.pump();
  await tester.pump();
  await tester.pump();
}

Future<void> _teardownTree(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
}

/// يبني اللوحَ وحدَه — أدقُّ من قيادته عبر الشاشة، ويقيس ما يخرج منه.
Future<List<ChequeBookSave>> _pumpPanel(
  WidgetTester tester, {
  ChequeBookValue? value,
  List<ChequeBookRowForTest> others = const [],
  List<BankAccountOption> banks = const [
    (accountId: 100, label: 'بنك مصر'),
    (accountId: 200, label: 'بنك القاهرة'),
  ],
  List<({int id, bool cancelled})>? toggles,
}) async {
  final saved = <ChequeBookSave>[];
  tester.view.physicalSize = const Size(900, 1200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentUserPermissionsProvider
            .overrideWith((ref) async => const ['commercial_papers_manage']),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ChequeBookPanel(
              value: value,
              banks: banks,
              others: [
                for (final o in others)
                  (
                    id: o.id,
                    bankAccountId: o.bankAccountId,
                    fromNumber: o.fromNumber,
                    toNumber: o.toNumber,
                    nextNumber: o.nextNumber,
                    status: o.status,
                  ),
              ],
              onClose: () {},
              onSave: (v) async => saved.add(v),
              onToggleCancelled: (id, c) async =>
                  toggles?.add((id: id, cancelled: c)),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  return saved;
}

typedef ChequeBookRowForTest = ({
  int id,
  int bankAccountId,
  int fromNumber,
  int toNumber,
  int nextNumber,
  String status,
});

void main() {
  group('الجدول', () {
    testWidgets('يعرض المدى والتالي والمتبقّي', (tester) async {
      await _pump(tester, books: [_book(next: 150)]);
      expect(find.text('CHK-101 ← CHK-200'), findsOneWidget);
      expect(find.text('CHK-150'), findsOneWidget);
      // ٢٠٠ − ١٥٠ + ١ = ٥١ — شاملةَ الطرفين.
      expect(find.text('٥١'), findsWidgets);
      await _teardownTree(tester);
    });

    testWidgets('🔴 و«التالي» على دفترٍ منتهٍ يقول سببَه لا رقماً كاذباً',
        (tester) async {
      await _pump(tester,
          books: [_book(next: 201, status: 'exhausted')]);
      expect(find.text('— انتهى'), findsOneWidget);
      expect(find.text('CHK-201'), findsNothing,
          reason: 'رقمٌ خارجَ المدى يُعرَض «التالي» ⇒ يُكتَب شيكٌ لا وجودَ '
              'له ورقيّاً');
      await _teardownTree(tester);
    });

    testWidgets('والملغى يقول سببَه كذلك', (tester) async {
      await _pump(tester, books: [_book(status: 'cancelled')]);
      expect(find.text('— ملغى'), findsOneWidget);
      await _teardownTree(tester);
    });
  });

  group('🔴 البنكُ خزنةٌ بنكيّةٌ لها حسابٌ مرتبط', () {
    testWidgets('لا خزنةَ صالحةً ⇒ يُقال السببُ ولا يُفتَح دفتر',
        (tester) async {
      await _pump(tester, safes: [_safe(linked: null)]);
      expect(find.byKey(const Key('cheque_book_no_bank_notice')),
          findsOneWidget);
      final btn = tester.widget<FilledButton>(
          find.byKey(const Key('cheque_book_new')));
      expect(btn.onPressed, isNull,
          reason: 'زرٌّ يفتح لوحاً بلا بنكٍ يُختار');
      await _teardownTree(tester);
    });

    testWidgets('وخزنةُ نقديّةٍ ليست بنكاً', (tester) async {
      expect(bankAccountOptions([_safe(type: 'cash')]), isEmpty);
    });

    testWidgets('وخزنةٌ موقوفةٌ تُقصى — تُختار اليومَ ويُرفَض قيدُها غداً',
        (tester) async {
      expect(bankAccountOptions([_safe(active: false)]), isEmpty);
    });

    testWidgets('وخزنتان على حسابٍ واحدٍ خيارٌ واحد', (tester) async {
      final opts = bankAccountOptions([
        _safe(id: 1, name: 'بنك مصر'),
        _safe(id: 2, name: 'بنك مصر ٢'),
      ]);
      expect(opts, hasLength(1),
          reason: 'الدفترُ على الحساب لا على الخزنة — وخياران على حسابٍ '
              'واحدٍ يُنتجان دفترَين متداخلَين يبدوان مشروعَين');
    });
  });

  group('اللوح', () {
    testWidgets('يكتب دفتراً جديداً بما مُلئ', (tester) async {
      final saved = await _pumpPanel(tester);
      await tester.enterText(
          find.byKey(const Key('cheque_book_number')), 'A-1');
      await tester.enterText(find.byKey(const Key('cheque_book_prefix')), 'CHK-');
      await tester.enterText(find.byKey(const Key('cheque_book_from')), '101');
      await tester.enterText(find.byKey(const Key('cheque_book_to')), '200');
      await tester.pump();

      await tester.tap(find.byKey(const Key('cheque_book_save')));
      await tester.pump();

      expect(saved, hasLength(1));
      expect(saved.single.bookNumber, 'A-1');
      expect(saved.single.fromNumber, 101);
      expect(saved.single.toNumber, 200);
      // ⚠️ «التالي» فارغٌ ⇒ يبدأ من أوّل الدفتر لا من صفر.
      expect(saved.single.nextNumber, 101);
      expect(saved.single.bankAccountId, 100);
      await _teardownTree(tester);
    });

    testWidgets('و«التالي» المكتوبُ يُحترَم — دفترٌ صُرفت أوراقُه قبل تسجيله',
        (tester) async {
      final saved = await _pumpPanel(tester);
      await tester.enterText(find.byKey(const Key('cheque_book_number')), 'A');
      await tester.enterText(find.byKey(const Key('cheque_book_from')), '101');
      await tester.enterText(find.byKey(const Key('cheque_book_to')), '200');
      await tester.enterText(find.byKey(const Key('cheque_book_next')), '150');
      await tester.pump();
      await tester.tap(find.byKey(const Key('cheque_book_save')));
      await tester.pump();
      expect(saved.single.nextNumber, 150);
      await _teardownTree(tester);
    });

    testWidgets('🔴 والتداخلُ يُقال ويمنع الحفظ قبل الضغط', (tester) async {
      final saved = await _pumpPanel(tester, others: [
        (
          id: 9,
          bankAccountId: 100,
          fromNumber: 101,
          toNumber: 200,
          nextNumber: 101,
          status: 'active'
        ),
      ]);
      await tester.enterText(find.byKey(const Key('cheque_book_number')), 'B');
      await tester.enterText(find.byKey(const Key('cheque_book_from')), '150');
      await tester.enterText(find.byKey(const Key('cheque_book_to')), '260');
      await tester.pump();

      expect(find.byKey(const Key('cheque_book_block_reason')), findsOneWidget);
      final btn = tester.widget<FilledButton>(
          find.byKey(const Key('cheque_book_save')));
      expect(btn.onPressed, isNull);
      expect(saved, isEmpty);
      await _teardownTree(tester);
    });

    testWidgets('ومدًى مقلوبٌ يمنع الحفظ', (tester) async {
      await _pumpPanel(tester);
      await tester.enterText(find.byKey(const Key('cheque_book_number')), 'A');
      await tester.enterText(find.byKey(const Key('cheque_book_from')), '200');
      await tester.enterText(find.byKey(const Key('cheque_book_to')), '101');
      await tester.pump();
      expect(find.byKey(const Key('cheque_book_block_reason')), findsOneWidget);
      await _teardownTree(tester);
    });

    testWidgets('ورقمُ دفترٍ فارغٌ يمنع الحفظ ويقول سببَه', (tester) async {
      await _pumpPanel(tester);
      await tester.enterText(find.byKey(const Key('cheque_book_from')), '1');
      await tester.enterText(find.byKey(const Key('cheque_book_to')), '50');
      await tester.pump();
      expect(find.text('اكتب رقم الدفتر.'), findsOneWidget);
      await _teardownTree(tester);
    });

    testWidgets('⚠️ والإلغاءُ زرٌّ ولا حذفَ في اللوح', (tester) async {
      final toggles = <({int id, bool cancelled})>[];
      await _pumpPanel(
        tester,
        value: (
          id: 7,
          bankAccountId: 100,
          bookNumber: 'A',
          prefix: 'CHK-',
          fromNumber: 101,
          toNumber: 200,
          nextNumber: 120,
          status: 'active',
          notes: '',
        ),
        toggles: toggles,
      );
      expect(find.text('حذف الدفتر'), findsNothing);

      await tester.tap(find.byKey(const Key('cheque_book_toggle_cancelled')));
      await tester.pump();
      expect(toggles, [(id: 7, cancelled: true)]);
      await _teardownTree(tester);
    });

    testWidgets('والملغى يعرض «إعادة الدفتر»', (tester) async {
      final toggles = <({int id, bool cancelled})>[];
      await _pumpPanel(
        tester,
        value: (
          id: 8,
          bankAccountId: 100,
          bookNumber: 'A',
          prefix: '',
          fromNumber: 1,
          toNumber: 50,
          nextNumber: 1,
          status: 'cancelled',
          notes: '',
        ),
        toggles: toggles,
      );
      await tester.tap(find.byKey(const Key('cheque_book_toggle_cancelled')));
      await tester.pump();
      expect(toggles, [(id: 8, cancelled: false)]);
      await _teardownTree(tester);
    });

    testWidgets('والدفترُ لا يتداخل مع نفسِه عند التعديل', (tester) async {
      final saved = await _pumpPanel(
        tester,
        value: (
          id: 7,
          bankAccountId: 100,
          bookNumber: 'A',
          prefix: '',
          fromNumber: 101,
          toNumber: 200,
          nextNumber: 101,
          status: 'active',
          notes: '',
        ),
        others: [
          (
            id: 7,
            bankAccountId: 100,
            fromNumber: 101,
            toNumber: 200,
            nextNumber: 101,
            status: 'active'
          ),
        ],
      );
      await tester.enterText(find.byKey(const Key('cheque_book_to')), '300');
      await tester.pump();
      expect(find.byKey(const Key('cheque_book_block_reason')), findsNothing);

      await tester.tap(find.byKey(const Key('cheque_book_save')));
      await tester.pump();
      expect(saved.single.toNumber, 300);
      expect(saved.single.id, 7);
      await _teardownTree(tester);
    });
  });

  group('الكتابة', () {
    testWidgets('🔴 الشاشةُ تكتب فعلاً — أوّلُ كاتبٍ لجدول v174',
        (tester) async {
      final repo = _FakeBooksRepo();
      await _pump(tester, repo: repo);
      await tester.tap(find.byKey(const Key('cheque_book_new')));
      await tester.pump();

      await tester.enterText(
          find.byKey(const Key('cheque_book_number')), 'A-9');
      await tester.enterText(find.byKey(const Key('cheque_book_from')), '1');
      await tester.enterText(find.byKey(const Key('cheque_book_to')), '25');
      await tester.pump();

      await tester.tap(find.byKey(const Key('cheque_book_save')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 6));

      expect(repo.created, hasLength(1));
      expect(repo.created.single['bookNumber'], 'A-9');
      expect(repo.created.single['to'], 25);
      await _teardownTree(tester);
    });

    testWidgets('⚠️ وبلا صلاحيّة الإدارة لا زرَّ كتابةٍ يُعرَض',
        (tester) async {
      await _pump(tester, perms: const ['treasury_view']);
      expect(find.byKey(const Key('cheque_book_new')), findsNothing);
      await _teardownTree(tester);
    });
  });
}
