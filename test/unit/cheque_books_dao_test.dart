// `ChequeBooksDao` — أوّلُ كاتبٍ لجدول v174، والحكمُ النافذُ على المدى.
//
// ═══ 🔴 ولماذا يُقاس هنا لا في الشاشة وحدَها ═══
//
// `cheque_book_plan.dart` خالصةٌ ومقيسةٌ في `cheque_book_plan_test.dart`،
// ويستعملها اللوحُ ليُري المستخدمَ الخطأَ وهو يكتب. لكنّ الفحصَ هناك
// **سباقٌ**: جهازان يفتحان دفترَين متداخلَين في نفس اللحظة وكلاهما قرأ
// القائمةَ قبل كتابة الآخر. فما يُقاس هنا هو أنّ المحرّكَ يرفض **بنفسه**،
// على قراءةٍ داخلَ المعاملة.
//
// 🔴 **ورقمٌ مكرَّرٌ في شيكٍ صادرٍ خطأٌ يصل البنك** — والحارسُ القائمُ في
// `commercial_papers_dao` يقارن `bankName` نصّاً حرّاً، فيسقط لو كُتب «مصر»
// مرّةً و«بنك مصر» أخرى.

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting());
  tearDown(() => db.close());

  Future<int> account(String code) => db.into(db.accounts).insert(
        AccountsCompanion.insert(
          code: code,
          name: 'بنك $code',
          accountType: 'asset',
          accountNature: const Value('debit'),
          normalBalance: const Value('debit'),
          level: const Value(1),
          balance: const Value(0),
          isSystem: const Value(false),
        ),
      );

  group('فتحُ دفتر', () {
    test('يُكتَب بحالته المشتقّة ومعرّفٍ عامّ', () async {
      final acc = await account('1121');
      final id = await db.createChequeBook(
        bankAccountId: acc,
        bookNumber: 'A-1',
        fromNumber: 101,
        toNumber: 200,
        prefix: 'CHK-',
      );

      final b = await db.getChequeBook(id);
      expect(b!.nextNumber, 101, reason: 'يبدأ من أوّله ما لم يُكتَب غيرُه');
      expect(b.status, 'active');
      expect(b.prefix, 'CHK-');
      // المعرّفُ العامُّ شرطُ المزامنة — وبدونه لا يتطابق صفُّ الجهازَين.
      expect(b.globalId, isNotNull);
      expect(b.globalId, isNotEmpty);
    });

    test('وبادئةٌ فارغةٌ تُخزَّن فراغاً لا نصّاً فارغاً', () async {
      final acc = await account('1122');
      final id = await db.createChequeBook(
        bankAccountId: acc,
        bookNumber: 'A-2',
        fromNumber: 1,
        toNumber: 50,
        prefix: '   ',
      );
      expect((await db.getChequeBook(id))!.prefix, isNull);
    });

    test('ودفترٌ يبدأ من منتصفه — أوراقٌ صُرفت قبل تسجيله', () async {
      final acc = await account('1123');
      final id = await db.createChequeBook(
        bankAccountId: acc,
        bookNumber: 'A-3',
        fromNumber: 101,
        toNumber: 200,
        nextNumber: 150,
      );
      expect((await db.getChequeBook(id))!.nextNumber, 150);
    });
  });

  group('🔴 المحرّكُ يرفض بنفسه', () {
    test('مدًى متداخلٌ على نفس الحساب — ورقمٌ مكرَّرٌ يصل البنك', () async {
      final acc = await account('1131');
      await db.createChequeBook(
        bankAccountId: acc,
        bookNumber: 'A',
        fromNumber: 101,
        toNumber: 200,
      );
      await expectLater(
        db.createChequeBook(
          bankAccountId: acc,
          bookNumber: 'B',
          fromNumber: 150,
          toNumber: 260,
        ),
        throwsA(isA<Exception>()),
      );
      expect((await db.getChequeBooks()).length, 1,
          reason: 'المعاملةُ لم ترتدّ — بقي الدفترُ المرفوض');
    });

    test('🔴 وحسابان مختلفان يقبلان نفسَ المدى', () async {
      final a = await account('1141');
      final b = await account('1142');
      await db.createChequeBook(
          bankAccountId: a, bookNumber: 'A', fromNumber: 101, toNumber: 200);
      await db.createChequeBook(
          bankAccountId: b, bookNumber: 'B', fromNumber: 101, toNumber: 200);
      expect((await db.getChequeBooks()).length, 2,
          reason: 'منعُ الثاني كان يُبطل دفتراً مشروعاً — بنكان مختلفان');
    });

    test('ورقمُ دفترٍ مكرَّرٌ على نفس الحساب يُرفَض', () async {
      final acc = await account('1151');
      await db.createChequeBook(
          bankAccountId: acc, bookNumber: 'A', fromNumber: 1, toNumber: 50);
      await expectLater(
        db.createChequeBook(
            bankAccountId: acc,
            bookNumber: 'A',
            fromNumber: 100,
            toNumber: 150),
        throwsA(isA<Exception>()),
      );
    });

    test('ومدًى مقلوبٌ يُرفَض', () async {
      final acc = await account('1161');
      await expectLater(
        db.createChequeBook(
            bankAccountId: acc, bookNumber: 'A', fromNumber: 200, toNumber: 101),
        throwsA(isA<Exception>()),
      );
    });

    test('والملغى لا يحجز مداه', () async {
      final acc = await account('1171');
      final id = await db.createChequeBook(
          bankAccountId: acc, bookNumber: 'A', fromNumber: 101, toNumber: 200);
      await db.setChequeBookCancelled(id, true);
      // الدفترُ الجديدُ على نفس المدى يمرّ — الأرقامُ لن تُسحَب من الملغى.
      final second = await db.createChequeBook(
          bankAccountId: acc, bookNumber: 'B', fromNumber: 101, toNumber: 200);
      expect(second, greaterThan(0));
    });
  });

  group('🔴 سحبُ الأرقام', () {
    test('يقدّم «التالي» بقدر ما سُحب', () async {
      final acc = await account('1201');
      final id = await db.createChequeBook(
          bankAccountId: acc, bookNumber: 'A', fromNumber: 101, toNumber: 200);

      expect(await db.allocateChequeNumbers(bookId: id, count: 3),
          [101, 102, 103]);
      expect((await db.getChequeBook(id))!.nextNumber, 104);

      // والسحبُ التالي يكمّل ولا يعيد.
      expect(await db.allocateChequeNumbers(bookId: id, count: 2), [104, 105]);
      expect((await db.getChequeBook(id))!.nextNumber, 106);
    });

    test('🔴 ولا يُسحَب رقمان لشيكين — السحبُ لا يعيد ما سبق', () async {
      final acc = await account('1202');
      final id = await db.createChequeBook(
          bankAccountId: acc, bookNumber: 'A', fromNumber: 1, toNumber: 20);
      final first = await db.allocateChequeNumbers(bookId: id, count: 2);
      final second = await db.allocateChequeNumbers(bookId: id, count: 2);
      expect(first.toSet().intersection(second.toSet()), isEmpty,
          reason: 'رقمٌ صُرف مرّتين — شيكان بنفس الرقم إلى البنك');
    });

    test('وآخرُ ورقةٍ تُنهي الدفترَ بحالته', () async {
      final acc = await account('1203');
      final id = await db.createChequeBook(
          bankAccountId: acc, bookNumber: 'A', fromNumber: 1, toNumber: 3);
      await db.allocateChequeNumbers(bookId: id, count: 3);
      final b = await db.getChequeBook(id);
      expect(b!.nextNumber, 4);
      expect(b.status, 'exhausted',
          reason: 'دفترٌ نفد وبقي «نشطاً» يُعرَض للسحب ولا يُسحَب منه');
    });

    test('🔴 ولا سحبَ جزئيّ — ولا يتقدّم «التالي» عند الرفض', () async {
      final acc = await account('1204');
      final id = await db.createChequeBook(
          bankAccountId: acc, bookNumber: 'A', fromNumber: 1, toNumber: 2);
      await expectLater(
        db.allocateChequeNumbers(bookId: id, count: 3),
        throwsA(isA<Exception>()),
      );
      expect((await db.getChequeBook(id))!.nextNumber, 1,
          reason: 'تقدّمَ الدفترُ على سحبٍ مرفوض ⇒ فجوةٌ في الترقيم');
    });

    test('ومن دفترٍ ملغًى لا يُسحَب ولو بقيت أرقامُه', () async {
      final acc = await account('1205');
      final id = await db.createChequeBook(
          bankAccountId: acc, bookNumber: 'A', fromNumber: 1, toNumber: 50);
      await db.setChequeBookCancelled(id, true);
      await expectLater(
        db.allocateChequeNumbers(bookId: id, count: 1),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('التعديلُ والإلغاء', () {
    test('توسيعُ النهاية يُعيد المنتهيَ نشطاً', () async {
      final acc = await account('1301');
      final id = await db.createChequeBook(
          bankAccountId: acc, bookNumber: 'A', fromNumber: 1, toNumber: 2);
      await db.allocateChequeNumbers(bookId: id, count: 2);
      expect((await db.getChequeBook(id))!.status, 'exhausted');

      await db.updateChequeBook(
        id: id,
        bankAccountId: acc,
        bookNumber: 'A',
        fromNumber: 1,
        toNumber: 10,
        nextNumber: 3,
      );
      expect((await db.getChequeBook(id))!.status, 'active');
    });

    test('🔴 والإلغاءُ لا يُنقَض بتعديلِ مدًى', () async {
      final acc = await account('1302');
      final id = await db.createChequeBook(
          bankAccountId: acc, bookNumber: 'A', fromNumber: 1, toNumber: 50);
      await db.setChequeBookCancelled(id, true);

      await db.updateChequeBook(
        id: id,
        bankAccountId: acc,
        bookNumber: 'A',
        fromNumber: 1,
        toNumber: 80,
        nextNumber: 1,
      );
      expect((await db.getChequeBook(id))!.status, 'cancelled',
          reason: 'دفترٌ ضاع عاد نشطاً بتعديلِ مدًى ⇒ يُسحَب منه شيكٌ لا '
              'وجودَ له ورقيّاً');
    });

    test('والدفترُ لا يتداخل مع نفسِه عند التعديل', () async {
      final acc = await account('1303');
      final id = await db.createChequeBook(
          bankAccountId: acc, bookNumber: 'A', fromNumber: 101, toNumber: 200);
      await db.updateChequeBook(
        id: id,
        bankAccountId: acc,
        bookNumber: 'A',
        fromNumber: 101,
        toNumber: 300,
        nextNumber: 101,
      );
      expect((await db.getChequeBook(id))!.toNumber, 300);
    });

    test('وتعديلٌ يتداخل مع دفترٍ آخرَ يُرفَض', () async {
      final acc = await account('1304');
      final a = await db.createChequeBook(
          bankAccountId: acc, bookNumber: 'A', fromNumber: 101, toNumber: 200);
      await db.createChequeBook(
          bankAccountId: acc, bookNumber: 'B', fromNumber: 201, toNumber: 300);
      await expectLater(
        db.updateChequeBook(
          id: a,
          bankAccountId: acc,
          bookNumber: 'A',
          fromNumber: 101,
          toNumber: 250,
          nextNumber: 101,
        ),
        throwsA(isA<Exception>()),
      );
      expect((await db.getChequeBook(a))!.toNumber, 200);
    });

    test('والإعادةُ تُرجع الحالةَ المشتقّة', () async {
      final acc = await account('1305');
      final id = await db.createChequeBook(
          bankAccountId: acc, bookNumber: 'A', fromNumber: 1, toNumber: 50);
      await db.setChequeBookCancelled(id, true);
      await db.setChequeBookCancelled(id, false);
      expect((await db.getChequeBook(id))!.status, 'active');
    });
  });

  test('🔴 والشيكُ يحمل دفترَه — وإلّا تقدّم الدفترُ وبقي مصدرُه مجهولاً',
      () async {
    final acc = await account('1401');
    final bookId = await db.createChequeBook(
        bankAccountId: acc, bookNumber: 'A', fromNumber: 101, toNumber: 200);
    final partyId = await db.into(db.parties).insert(
          PartiesCompanion.insert(
              name: 'مورد', isSupplier: const Value(true)),
        );
    final numbers = await db.allocateChequeNumbers(bookId: bookId, count: 1);

    await db.createCommercialPaper(
      paperNumber: '${numbers.single}',
      type: 'cheque',
      direction: 'issued',
      partyId: partyId,
      amount: 500,
      issueDate: DateTime.now(),
      dueDate: DateTime.now().add(const Duration(days: 30)),
      chequeBookId: bookId,
    );

    final usage = await db.getChequeBookUsage(bookId);
    expect(usage, hasLength(1));
    expect(usage.single.paperNumber, '101');
    expect(usage.single.amount, 500);
  });
}
