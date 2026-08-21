// صفحةُ العملاء/الموردين — السقفُ والبحثُ في SQL.
//
// نزلا إلى الاستعلام بعد قياسٍ (2026-08-21): القائمةُ كانت تُبَثّ كاملةً بلا
// `LIMIT`، والفلترُ يمرّ عليها في Dart مع كلّ ضغطة مفتاح. والعرضُ كان مسقوفاً
// بـ«تحميل المزيد» فبدا الأمرُ سليماً — لكنّ ذلك يسقّف الرسمَ لا البيانات.
//
// ويُقاس هنا ما ينكسر بصمت:
//  ١) **السقفُ يُطبَّق فعلاً** — لا يكفي أن يُمرَّر، لا بدّ أن يقصّ.
//  ٢) **الترتيبُ قبل القصّ** — سقفٌ على نتيجةٍ غيرِ مرتَّبةٍ يعطي صفوفاً
//     عشوائيّةً تتغيّر بين استدعاءين على نفس البيانات.
//  ٣) **صفٌّ بلا هاتفٍ لا يسقط من البحث بالاسم** — `NULL LIKE ?` تُنتج NULL
//     لا false، فالشرطُ المركَّب كان يُسقطه ولو طابق اسمُه.
//  ٤) **النوعُ يفصل** — بحثٌ عن عميلٍ لا يُرجع مورّداً يحمل الاسمَ نفسَه.
import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.forTesting();
    // البذرةُ القياسيّة قد تزرع أطرافاً، فيُبدأ من صفحةٍ نظيفةٍ كي تكون
    // الأعدادُ المؤكَّدةُ أعدادَ ما زرعناه لا ما ورثناه.
    await db.delete(db.parties).go();
  });

  // ⚠️ لا `db.close()` — يعلّق مؤقّتَ drift في المنطقة الوهميّة.
  tearDown(() async {});

  Future<void> addParty(
    String name, {
    String? phone,
    bool isCustomer = true,
    bool isSupplier = false,
  }) async {
    await db.into(db.parties).insert(
          PartiesCompanion.insert(
            name: name,
            phone: Value(phone),
            isCustomer: Value(isCustomer),
            isSupplier: Value(isSupplier),
          ),
        );
  }

  Future<List<Party>> page({String search = '', int limit = 200}) =>
      db.watchPartiesPage(isCustomer: true, search: search, limit: limit).first;

  test('السقفُ يقصّ فعلاً — لا يُمرَّر ويُهمَل', () async {
    for (var i = 0; i < 25; i++) {
      await addParty('عميل ${i.toString().padLeft(2, '0')}');
    }

    final capped = await page(limit: 10);

    expect(capped.length, 10,
        reason: 'سقفٌ لا يقصّ يعني أن كلَّ الصفوف ما زالت تدخل الذاكرة — '
            'وهو العطبُ عينُه الذي وُجدت الدالّةُ لأجله');
  });

  test('الترتيبُ يسبق القصَّ — الصفحةُ الأولى هي الأوائلُ أبجديّاً', () async {
    // الإدخالُ معكوسٌ عمداً: لو قُصَّ قبل الترتيب لعادت «ي…» لا «أ…».
    await addParty('ياسر');
    await addParty('باسم');
    await addParty('أحمد');

    final first = await page(limit: 2);

    expect(first.map((p) => p.name).toList(), ['أحمد', 'باسم'],
        reason: 'قصٌّ قبل ترتيبٍ يعطي صفوفاً تتبدّل بين استدعاءين على نفس '
            'البيانات — والمستخدمُ يرى قائمةً «ترقص»');
  });

  test('صفٌّ بلا هاتفٍ يظهر في البحث بالاسم', () async {
    await addParty('محمد بلا هاتف'); // phone == null
    await addParty('محمد بهاتف', phone: '0100');

    final found = await page(search: 'محمد');

    // ⚠️ ولا يُدَّعى أن `COALESCE` هي التي تُنقذ هذا: قِيس بإزالتها فبقي
    // أخضر، لأن `TRUE OR NULL` = TRUE في منطق SQL الثلاثيّ. فما يحرسه هذا
    // الاختبارُ هو **الدلالةُ** — البحثُ بالاسم لا يشترط وجودَ هاتف — لا
    // صياغةٌ بعينها. ولو أُعيدت صياغةُ الشرط يوماً (‏`AND` بدل `OR`، أو
    // شرطٌ مستقلٌّ للهاتف) لصار NULL قاتلاً، وحينها يحمرّ هذا بالضبط.
    expect(found.length, 2,
        reason: 'البحثُ بالاسم لا يجوز أن يشترط هاتفاً مسجَّلاً');
  });

  test('البحثُ يشمل الهاتفَ كما كان فلترُ Dart', () async {
    await addParty('سعيد', phone: '01234567');
    await addParty('كريم', phone: '09999999');

    final found = await page(search: '0123');

    expect(found.length, 1);
    expect(found.single.name, 'سعيد');
  });

  test('النوعُ يفصل — مورّدٌ لا يظهر في صفحة العملاء', () async {
    await addParty('طرفٌ مشترك', isCustomer: false, isSupplier: true);

    final customers = await page(search: 'مشترك');
    final suppliers = await db
        .watchPartiesPage(isCustomer: false, search: 'مشترك')
        .first;

    expect(customers, isEmpty, reason: 'مورّدٌ خالصٌ ليس عميلاً');
    expect(suppliers.length, 1);
  });

  test('بحثٌ فارغٌ ⇒ لا شرطَ بحثٍ (كلُّ الصفوف تحت السقف)', () async {
    await addParty('أ');
    await addParty('ب');

    expect((await page()).length, 2);
  });
}
