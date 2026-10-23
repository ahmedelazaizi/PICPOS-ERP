// جداول Drift مفقودة على SQLite مرقّى — مفيش أي شبكة أمان.
//
// ── العطل ────────────────────────────────────────────────────────────────────
// `category_station_mappings` مسجّل في `@DriftDatabase` وبيتقري بـSQL خام في
// `kitchen_dao.dart:364`، لكن **مفيش `createTable` ليه في أي مايجريشن**.
// يعني تركيبة نضيفة بتاخده من `createAll()`، والتركيبة المرقّاة **لأ**.
//
// النتيجة على مطعم بيرقّي: أول بيعة → `generateKitchenWorkOrder` →
// `no such table` → متبلع في
// `catch { debugPrint('[KitchenService] فشل إنشاء أمر المطبخ') }` →
// **أوامر المطبخ ما بتتطبعش والكاشير مش شايف أي خطأ**.
//
// وde مش حالة نظرية: التعليق في `database_startup.dart:60` بيوثّق نفس العطل
// لما حصل على تركيبة PostgreSQL في 2026-05-25 (كل بيعة بتفشل بـ42P01).
// الإصلاح ساعتها كان `_ensurePostgresSchemaParity` — بس هو جوه
// `if (_isPostgres)`، فـSQLite فضلت بلا نظير.
//
// ── ليه تمريرة عامة مش createTable لجدول واحد ───────────────────────────────
// المسح طلّع إن الجدول ده مش وحيد: فيه جداول تانية في `@DriftDatabase`
// مالهاش `createTable` في أي مايجريشن. إضافة الجدول ده بإيدنا بتقفل الحالة
// دي وبس، والتمريرة العامة بتقفل الفئة كلها — بما فيها أي جدول ينضم
// للـ`@DriftDatabase` في إصدار جاي من غير مايجريشن.
//
// drift بيولّد `CREATE TABLE IF NOT EXISTS`، فالتمريرة no-op على قاعدة سليمة.
import 'package:drift/drift.dart' show Variable;
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting());
  tearDown(() => db.close());

  Future<bool> tableExists(String name) async {
    final rows = await db.customSelect(
      "SELECT name FROM sqlite_master WHERE type='table' AND name = ?",
      variables: [Variable<String>(name)],
    ).get();
    return rows.isNotEmpty;
  }

  test('ensureSchemaDefaults بيرجّع جدول ناقص من قاعدة مرقّاة', () async {
    // نحاكي التركيبة المرقّاة: الجدول مش موجود لأن مفيش مايجريشن عملته.
    await db.customStatement('DROP TABLE IF EXISTS category_station_mappings');
    expect(await tableExists('category_station_mappings'), isFalse,
        reason: 'الإعداد نفسه فشل — الجدول لازم يبقى مش موجود هنا');

    await db.ensureSchemaDefaults();

    expect(await tableExists('category_station_mappings'), isTrue);
  });

  test('الجدول المرجَّع قابل للكتابة والقراءة فعلاً مش مجرد اسم', () async {
    await db.customStatement('DROP TABLE IF EXISTS category_station_mappings');
    await db.ensureSchemaDefaults();

    // الاهتمام هنا إن الجدول اتعمل بشكله الصح وقابل للاستخدام — مش سلوك
    // الـFK. الصنف والمحطة الحقيقيين محتاجين صفوف كاملة مالهاش علاقة بالعطل.
    await db.customStatement('PRAGMA foreign_keys = OFF');
    await db.customStatement(
        'INSERT INTO category_station_mappings (category_id, station_id) '
        'VALUES (1, 2)');
    final rows = await db
        .customSelect('SELECT station_id FROM category_station_mappings')
        .get();
    expect(rows.single.data['station_id'], 2);
  });

  test('التمريرة no-op على قاعدة سليمة — البيانات ما بتتمسحش', () async {
    await db.customStatement('PRAGMA foreign_keys = OFF');
    await db.customStatement(
        'INSERT INTO category_station_mappings (category_id, station_id) '
        'VALUES (7, 9)');

    await db.ensureSchemaDefaults();

    final rows = await db
        .customSelect('SELECT category_id FROM category_station_mappings')
        .get();
    expect(rows.single.data['category_id'], 7,
        reason: 'CREATE TABLE IF NOT EXISTS ما يمسحش صفوف قايمة');
  });

  test('التمريرة بتغطّي كل جداول Drift مش جدول واحد', () async {
    // عيّنة تانية من نفس الفئة — جدول موجود في المخطّط لكن غير مذكور في أي
    // مايجريشن. لو التمريرة اتكتبت لجدول واحد بالاسم، الاختبار ده بيقع.
    await db.customStatement('DROP TABLE IF EXISTS processed_messages');
    expect(await tableExists('processed_messages'), isFalse);

    await db.ensureSchemaDefaults();

    expect(await tableExists('processed_messages'), isTrue);
  });
}
