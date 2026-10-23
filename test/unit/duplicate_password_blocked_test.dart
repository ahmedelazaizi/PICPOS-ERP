// ═══════════════════════════════════════════════════════════════════════════
// تكرارُ كلمة المرور يُمنع **عند الكتابة** لا عند القراءة
// ═══════════════════════════════════════════════════════════════════════════
//
// ── لماذا منعٌ لا تنبيه ──────────────────────────────────────────────────────
// `authenticateByPasswordOrCard` يمرّ على كلّ مستخدمٍ نشطٍ غيرِ مقفولٍ ويرجع
// **أوّلَ** من يتحقّق هاشُه، بلا `orderBy`. فلو حمل اثنان نفسَ كلمة المرور:
//
//   · الثاني **لا يستطيع المصادقةَ إطلاقاً** — لا تبديلَ مستخدمٍ ولا موافقةَ
//     مديرٍ ولا إغلاقَ ورديةٍ بالمدخل الموحَّد.
//   · و«أيُّهما الأوّل» **غيرُ محدَّد** — ترتيبُ الصفوف لا يضمنه شيء.
//   · وأخطرُها: حوارُ موافقةِ المدير يُسجّل الموافقةَ **باسم الشخص الخطأ** —
//     نقضٌ للمسؤولية، لا إزعاجٌ في تجربة الاستعمال.
//
// ── وما الذي كان موجوداً قبل هذا الملف ──────────────────────────────────────
// `PasswordCollisionScanner` (‏Feature 004/US2) يفحص التصادمَ لكنه **لا يعالج
// أيّاً مما سبق** بثلاثة قيودٍ مكتوبةٍ في رأسه:
//   · FR-013 — التنبيهُ إخباريٌّ ولا يمنع الحفظَ أبداً.
//   · FR-016 — تصادمُ **نفس الفرع** خارجَ النطاق أصلاً.
//   · وهو `unawaited` — يصل المديرَ بعد أن صار العطبُ في القاعدة.
// و`PIR-08` كان أزال فحصَ التفرّد وسمّاه «نمطاً أمنياً مضادّاً» — وهو حكمٌ
// صحيحٌ لموقعٍ مكشوفٍ للعامّة، وهذا المسارُ إداريٌّ محضٌ خلفَ صلاحيات
// المستخدمين، والبديلُ عنه مصادقةٌ مكسورةٌ وتوقيعٌ منسوبٌ لغير صاحبه.
//
// ── الكلفة، مقيسةٌ لا مفترَضة ────────────────────────────────────────────────
// الفحصُ يجرّب كلمةَ المرور الجديدة على كلّ مستخدمٍ نشطٍ غيرِ مقفول، وArgon2id
// عند ضبط المشروع ‏٣٠–٥٠ms لكلّ تحقّق. فهي `n × 40ms` في مسارٍ متزامن: تحت
// الثانية لعشرين مستخدماً، وثانيتان لخمسين. ولذلك يقتصر على النشطين غيرِ
// المقفولين — وهم بعينهم من تجرّبهم حلقةُ المصادقة، فلا يُمنع إلا تصادمٌ
// يُنتج العطبَ فعلاً.

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/services/network_service.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting();
    // ⚠️ `PasswordCollisionScanner` يُطلَق `unawaited` من مسارَي الكتابة، فيبقى
    // يقرأ القاعدةَ بعد أن ينتهي الاختبارُ ويغلقَها `tearDown` — فيسقط الاختبارُ
    // بـ«Can't re-open a database after closing it»، وهو فشلٌ **زمنيٌّ لا
    // سلوكيّ** يُقرأ عطباً في المنع. والماسحُ يقصر نفسَه على وضع العميل
    // (‏`password_collision_scanner.dart:86,156`)، فهذا المدخلُ يُسكته
    // بالتصميم. ويُضبط **بعد** بناء القاعدة كي لا يمسّ الزرعَ.
    NetworkService.instance.debugSetModeForTests(NetworkMode.client);
  });

  tearDown(() async {
    NetworkService.instance.debugSetModeForTests(NetworkMode.standalone);
    await db.close();
  });

  group('إنشاءُ مستخدم', () {
    test('كلمةُ مرورٍ يحملها مستخدمٌ آخرُ تُرفض', () async {
      await db.createUser(
        username: 'kareem',
        password: 'Str0ng!Pass',
        displayName: 'كريم',
      );

      await expectLater(
        db.createUser(
          username: 'sara',
          password: 'Str0ng!Pass',
          displayName: 'سارة',
        ),
        throwsA(isA<DuplicatePasswordException>()),
      );
    });

    test('الرفضُ يسمّي صاحبَ الكلمة ليعرف المديرُ ما يصلحه', () async {
      await db.createUser(
        username: 'kareem',
        password: 'Str0ng!Pass',
        displayName: 'كريم',
      );

      try {
        await db.createUser(
          username: 'sara',
          password: 'Str0ng!Pass',
          displayName: 'سارة',
        );
        fail('كان يجب أن يُرفض');
      } on DuplicatePasswordException catch (e) {
        expect(e.conflictingUsername, 'kareem');
        expect(e.toString(), contains('kareem'));
      }
    });

    test('كلمةُ مرورٍ فريدةٌ تمرّ', () async {
      final id = await db.createUser(
        username: 'sara',
        password: 'An0ther!Pass',
        displayName: 'سارة',
      );
      expect(id, greaterThan(0));
    });

    test('لا يُنشأ صفٌّ للمستخدم المرفوض', () async {
      await db.createUser(
        username: 'kareem',
        password: 'Str0ng!Pass',
        displayName: 'كريم',
      );

      try {
        await db.createUser(
          username: 'sara',
          password: 'Str0ng!Pass',
          displayName: 'سارة',
        );
      } on DuplicatePasswordException {
        // متوقَّع
      }

      // ⚠️ الضابطُ الحاكم: المنعُ **قبل** الإدراج لا بعده. لو أُدرج الصفُّ ثم
      // رُمي الاستثناءُ لبقي في القاعدة مستخدمٌ لا يقدر يصادق — وهو العطبُ
      // نفسُه الذي جئنا نمنعه.
      final sara = await (db.select(db.users)
            ..where((u) => u.username.equals('sara')))
          .getSingleOrNull();
      expect(sara, isNull);
    });
  });

  group('تغييرُ كلمة المرور', () {
    test('التغييرُ إلى كلمةِ مستخدمٍ آخرَ يُرفض', () async {
      await db.createUser(
        username: 'kareem',
        password: 'Str0ng!Pass',
        displayName: 'كريم',
      );
      final saraId = await db.createUser(
        username: 'sara',
        password: 'An0ther!Pass',
        displayName: 'سارة',
      );

      await expectLater(
        db.updateUserPassword(userId: saraId, newPassword: 'Str0ng!Pass'),
        throwsA(isA<DuplicatePasswordException>()),
      );
    });

    test('إبقاءُ المستخدمِ كلمتَه نفسَها لا يُرفض', () async {
      final saraId = await db.createUser(
        username: 'sara',
        password: 'An0ther!Pass',
        displayName: 'سارة',
      );

      // ⚠️ بلا استثناءِ صاحبِ الصفّ يصير كلُّ حفظٍ بلا تغييرِ كلمةٍ رفضاً —
      // والمستخدمُ يحبس نفسَه عن تعديل اسمه أو دورِه.
      await db.updateUserPassword(
        userId: saraId,
        newPassword: 'An0ther!Pass',
      );

      final user = await db.getUserByEmailAndPassword('sara', 'An0ther!Pass');
      expect(user, isNotNull);
    });

    test('كلمةٌ فريدةٌ تمرّ ويصادق بها صاحبُها', () async {
      final saraId = await db.createUser(
        username: 'sara',
        password: 'An0ther!Pass',
        displayName: 'سارة',
      );

      await db.updateUserPassword(userId: saraId, newPassword: 'Fresh!Pass9');

      final user = await db.getUserByEmailAndPassword('sara', 'Fresh!Pass9');
      expect(user, isNotNull);
      expect(user!.username, 'sara');
    });
  });

  group('حدودُ الفحص', () {
    test('المستخدمُ المعطَّلُ لا يمنع كلمتَه', () async {
      final oldId = await db.createUser(
        username: 'old',
        password: 'Str0ng!Pass',
        displayName: 'قديم',
      );
      await (db.update(db.users)..where((u) => u.id.equals(oldId)))
          .write(const UsersCompanion(isActive: Value(false)));

      // حلقةُ المصادقة نفسُها تتخطّى غيرَ النشطين، فلا تصادمَ يقع أصلاً —
      // والمنعُ هنا كان سيحجب كلمةً صالحةً بلا سبب.
      final id = await db.createUser(
        username: 'sara',
        password: 'Str0ng!Pass',
        displayName: 'سارة',
      );
      expect(id, greaterThan(0));
    });
  });
}
