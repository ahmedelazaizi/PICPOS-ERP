// v166 / المرحلة ٢ — المصروفُ التشغيليّ: العميلُ يُرسل ولا يكتب.
//
// ═══ العطبُ الذي يمنعه هذا الملفّ ═══
//
// 🔴 المصروفُ الواحدُ **ثلاثةُ آثارٍ ماليّة** لا أثرٌ واحد: قيدُ يوميّةٍ وسندُ
// صرفٍ من الخزنة وخصمُ رصيدها. ومفتاحُ إزالة تكرار القيد
// `(referenceType, referenceId)` و`referenceId` رقمُ المصروف **المحلّيّ** الذي
// يخالف رقمَه على الخادم. فترحيلُ الطرفين يُنتج قيدَين وسندَي صرفٍ وخصمَين
// لمصروفٍ واحد — والخزنةُ تنقص ضعفَ ما صُرف.
//
// ولا يُكتَب صفٌّ محلّيٌّ هنا أصلاً — بخلاف الأصل الثابت. المصروفُ بلا سنده
// وخصمه صفٌّ يتيمٌ يجعل تقريرَ المصروفات يخالف الخزنةَ حتّى أوّل سحبِ دلتا،
// وهو أسوأُ من غيابٍ مؤقّت.
//
// ═══ ولماذا مرساةٌ موجبةٌ في الآخر ═══
//
// «لم يُكتَب شيء» تمرّ أيضاً لو كانت التجهيزةُ ناقصةً فلم يُكتَب شيءٌ أصلاً.
// فالفحصُ الأخيرُ يشترط أنّ الوضعَ المستقلَّ يكتب الثلاثةَ فعلاً.

import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/data/database/sync_interceptor.dart';

class _RecordingClient implements SyncInterceptor {
  int calls = 0;
  Map<String, dynamic>? document;

  @override
  bool get isClientModeImpl => true;

  @override
  bool get isMirrorModeImpl => false;

  @override
  Future<void> submitOperationalExpense(Map<String, dynamic> doc) async {
    calls++;
    document = doc;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  late AppDatabase db;
  late int categoryId;
  late int userId;

  Future<int> record() => db.recordAndPostOperationalExpense(
        categoryId: categoryId,
        amount: 500,
        expenseDate: DateTime(2026, 8, 27),
        description: 'إيجارُ مخزن',
        expenseAccountCode: '6214',
        userId: userId,
      );

  setUp(() async {
    SyncInterceptor.instance = null;
    db = AppDatabase.forTesting();
    await db.syncDefaultAccounts();

    categoryId = await db.createExpenseCategory(name: 'إيجارات');
    final user = await db.select(db.users).getSingleOrNull();
    userId = user?.id ?? 1;
  });

  tearDown(() async {
    SyncInterceptor.instance = null;
    await db.close();
  });

  test('الفئةُ والمصروفُ يحملان هويّةً', () async {
    final cat = await (db.select(db.opExpenseCategories)
          ..where((c) => c.id.equals(categoryId)))
        .getSingle();
    expect(cat.globalId, isNotNull,
        reason: 'فئةٌ بلا هويّةٍ تردّ كلَّ مصروفٍ فيها من الخادم.');
  });

  group('مصروفٌ من عميل', () {
    late _RecordingClient client;

    setUp(() async {
      client = _RecordingClient();
      SyncInterceptor.instance = client;
      await record();
    });

    test('أُرسل مرّةً واحدةً بهويّةٍ', () {
      expect(client.calls, 1);
      expect(client.document!['globalId'], isNotNull);
      expect(client.document!['amount'], 500);
    });

    test('🔴 ولا صفَّ مصروفٍ كُتب محلّيّاً', () async {
      expect(
        await db.select(db.opExpenses).get(),
        isEmpty,
        reason: 'صفٌّ محلّيٌّ بلا سندٍ ولا خصمٍ يجعل تقريرَ المصروفات يخالف '
            'الخزنةَ حتّى أوّل سحبِ دلتا.',
      );
    });

    test('🔴 ولا قيدَ رُحِّل', () async {
      final entries = await (db.select(db.journalEntries)
            ..where((e) => e.referenceType.equals('op_expense')))
          .get();
      expect(
        entries,
        isEmpty,
        reason: 'العميلُ رحّل قيداً ⇒ الخادمُ سيُرحّل ثانياً ومفتاحاهما '
            'مختلفان: قيدان لمصروفٍ واحد.',
      );
    });

    test('🔴 ولا سندَ صرفٍ ولا خصمَ من خزنة', () async {
      final vouchers = await (db.select(db.safeTransactions)
            ..where((t) => t.referenceType.equals('op_expense')))
          .get();
      expect(
        vouchers,
        isEmpty,
        reason: 'سندُ صرفٍ محلّيٌّ + سندُ الخادم = الخزنةُ تنقص ضعفَ ما صُرف.',
      );
    });

    test('والفئةُ تُرسَل كاملةً لا بمعرّفها', () {
      final cat = client.document!['category'] as Map<String, dynamic>?;
      expect(cat, isNotNull);
      expect(cat!['name'], 'إيجارات');
      expect(cat['accountCode'], isNotNull,
          reason: 'بلا رمز الحساب لا يعرف الخادمُ أينَ يُرحّل الفئةَ الجديدة.');
    });
  });

  test('⚓ مرساة: الوضعُ المستقلُّ يكتب الثلاثةَ فعلاً', () async {
    // بلا هذه المرساةِ يمرّ كلُّ فحصٍ أعلاه أخضرَ لو كانت الحساباتُ غيرَ
    // مهيّأةٍ فلم يُكتَب شيءٌ أصلاً.
    SyncInterceptor.instance = null;
    final id = await record();

    expect(id, greaterThan(0));
    expect(await db.select(db.opExpenses).get(), isNotEmpty,
        reason: 'المستقلُّ لا يكتب صفَّ المصروف ⇒ فحوصُ المنعِ بلا معنى.');

    final entries = await (db.select(db.journalEntries)
          ..where((e) => e.referenceType.equals('op_expense')))
        .get();
    expect(entries, isNotEmpty,
        reason: 'المستقلُّ لا يُرحّل ⇒ فحصُ المنعِ بلا معنى.');
  });
}
