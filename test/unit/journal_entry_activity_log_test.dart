// سجلُّ النشاط للقيد اليدويّ — **يُقاس بصفٍّ في جدول، لا بوجود نداءٍ في نصّ.**
//
// ═══ 🔴 ما كان ═══
//
// `logJournalEntry` مكتوبةٌ في `log_financial.dart` **بلا منادٍ واحد**.
// فسجلُّ النشاط فارغٌ تماماً من القيود، وقرارُ المالك 2026-09-18 يجعله مصدرَ
// «المنشئ» — أي ميزةً تُبنى وتُعرَض ولا تعمل يوماً.
//
// ═══ ولماذا في المستودع لا في الحوار ═══
//
// وصلُها في حوار الإنشاء كان يترك **كلَّ منادٍ آخر** بلا سجلّ، ويجعل وصلَها
// غيرَ قابلٍ للقياس إلّا بشجرةِ ودجت — وحارسٌ نصّيٌّ على وجود النداء **لا
// يفرّق بين شيفرةٍ تعمل وشيفرةٍ معطَّلةٍ بشرطٍ كاذب** (قِيس: `if (false)`
// يمرّ من الحارس ومن `flutter analyze` معاً).
//
// فالقياسُ هنا على الأثر: صفٌّ في `activity_logs` أو لا صفّ.

import 'package:drift/drift.dart' show Variable;
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/data/repositories/drift_accounting_repository.dart';
import 'package:picpos_erp/domain/repositories/accounting_repository.dart';

void main() {
  late AppDatabase db;
  late DriftAccountingRepository repo;
  late int adminId;
  late int cashId;
  late int expenseId;

  setUp(() async {
    db = AppDatabase.forTesting();
    await db.syncDefaultAccounts();
    repo = DriftAccountingRepository(db);
    adminId = (await db
            .customSelect("SELECT id FROM users WHERE username = 'admin' LIMIT 1")
            .getSingle())
        .read<int>('id');
    // حسابان أيّاً كانا — المقيسُ سجلُّ النشاط لا شجرةُ الحسابات، وتثبيتُ
    // رمزٍ بعينه يربط الاختبارَ بتجهيزةِ الدليل.
    // ⚠️ **تفصيليّان لا رئيسيّان**: الترحيلُ على حسابٍ `view` مرفوضٌ
    // بحارسٍ قائم (v110)، فاختيارُ أوّلِ حسابَين في الدليل يسقط عليه.
    final leaves = (await db.getAllAccounts())
        .where((a) => a.accountNature != 'view')
        .toList();
    expect(leaves.length, greaterThan(1), reason: 'لا حسابَين تفصيليَّين');
    cashId = leaves[0].id;
    expenseId = leaves[1].id;
  });

  tearDown(() => db.close());

  Future<List<Map<String, Object?>>> journalLogs() async {
    final rows = await db
        .customSelect(
          "SELECT entity_id, user_id, user_name, action, amount "
          "FROM activity_logs WHERE entity_type = 'journal_entry'",
        )
        .get();
    return [
      for (final r in rows)
        {
          'entity_id': r.read<int?>('entity_id'),
          'user_id': r.read<int?>('user_id'),
          'user_name': r.read<String?>('user_name'),
          'action': r.read<String?>('action'),
          'amount': r.read<double?>('amount'),
        }
    ];
  }

  Future<int> createManual({int? createdBy, double amount = 250}) =>
      repo.createJournalEntry(
        description: 'قيدٌ يدويٌّ للقياس',
        date: DateTime(2026, 9, 19),
        lines: [
          JournalLine(accountId: expenseId, debit: amount, credit: 0),
          JournalLine(accountId: cashId, debit: 0, credit: amount),
        ],
        referenceType: 'manual',
        createdBy: createdBy,
      );

  test('🔴 قيدٌ يدويٌّ يترك صفّاً في سجلّ النشاط', () async {
    // قبل هذا الوصل كان السجلُّ يبقى فارغاً مهما أُنشئ من قيود.
    final entryId = await createManual(createdBy: adminId);

    final logs = await journalLogs();
    expect(logs, hasLength(1),
        reason: 'لا صفَّ في السجلّ — والقرارُ يجعله مصدرَ «المنشئ»');
    expect(logs.single['entity_id'], entryId,
        reason: 'الصفُّ لا يشير إلى القيد الذي أُنشئ');
    expect(logs.single['user_id'], adminId);
    expect(logs.single['action'], 'journal_entry_create');
  });

  test('واسمُ المستخدم يُقرأ من صفّه لا يُخمَّن', () async {
    await createManual(createdBy: adminId);
    final name = (await db
            .customSelect('SELECT display_name FROM users WHERE id = ?',
                variables: [Variable.withInt(adminId)])
            .getSingle())
        .read<String>('display_name');
    expect((await journalLogs()).single['user_name'], name);
  });

  test('والمبلغُ المسجَّلُ هو مجموعُ المدين', () async {
    await createManual(createdBy: adminId, amount: 777);
    expect((await journalLogs()).single['amount'], closeTo(777, 0.001));
  });

  test('🔴 والترحيلُ الآليُّ لا يُسجَّل — لا منشئَ بشريَّ له', () async {
    // ⚠️ الترحيلُ الآليُّ يمرّ من نفس الدالّة (فواتيرُ وسنداتٌ وإهلاك).
    // وتسجيلُه باسمٍ مخترَعٍ يملأ السجلَّ بضجيجٍ يُخفي ما يفعله البشر.
    await createManual(createdBy: null);
    expect(await journalLogs(), isEmpty,
        reason: 'قيدٌ بلا منشئٍ سُجِّل باسمٍ ما — والسجلُّ للبشر');
  });

  test('وقيدان يدويّان يتركان صفَّين لا واحداً', () async {
    await createManual(createdBy: adminId, amount: 100);
    await createManual(createdBy: adminId, amount: 200);
    expect(await journalLogs(), hasLength(2));
  });

  // ⚠️ **ومنشئٌ لا وجودَ لصفّه لا يصل هذا المسارَ أصلاً**: قيدُ المفتاح
  // الأجنبيّ على `created_by` يرفض `UPDATE` قبل أن يُنادى السجلُّ. فالحالةُ
  // محروسةٌ أعمقَ ممّا قِيس هنا — ولا تُختبَر بما لا يقع.

  group('وقراءةُ «المنشئ» تقابل ما كُتب', () {
    test('قيدٌ بمنشئٍ يعيد اسمَه', () async {
      final entryId = await createManual(createdBy: adminId);
      final name = await repo.getJournalEntryCreator(entryId);
      expect(name, isNotNull);
      expect(name, isNotEmpty);
    });

    test('🔴 وقيدٌ بلا منشئٍ يعيد `null` لا اسماً مخترَعاً', () async {
      // الترحيلُ الآليُّ يمرّ من هنا، ولا منشئَ بشريَّ له. و«لا يُعرَف»
      // تُعرَض «—» على الشاشة لا اسماً.
      final entryId = await createManual(createdBy: null);
      expect(await repo.getJournalEntryCreator(entryId), isNull);
    });
  });
}
