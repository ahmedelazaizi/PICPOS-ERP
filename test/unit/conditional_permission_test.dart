// الصلاحيةُ المشروطة — `role_permissions.grant_mode` (هجرة v163).
//
// ═══ ما يحمي هذا الملفّ ═══
//
// «مشروط» تعني: الصلاحيةُ **ممنوحةٌ** ويمرّ تنفيذُها بموافقة مسؤولٍ في كلّ
// مرّة. وهي أسهلُ ما يُعطَّل بصمت:
//
//  ‏١) لو حُفظ النمطُ ولم يُقرأ ⇒ خليّةٌ كهرمانيّةٌ في المصفوفة والتنفيذُ
//     يمضي بلا موافقة.
//  ‏٢) لو قُرئ وفُحص **بعد** فحص المِلك ⇒ يعود `true` أوّلاً ولا يُسأل
//     مسؤولٌ أبداً — والترتيبُ هو الميزةُ كلُّها.
//  ‏٣) لو أضاف أحدٌ `grantMode` إلى companion المزامنة ⇒ كلُّ سحبٍ يكتب
//     `allow` فوقَ المشروط، أي **انحدارٌ أمنيٌّ صامت**.
//
// فلكلٍّ من الثلاثة فحصٌ صريحٌ هنا.
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' show Value;
import 'package:ural_erp/core/permissions/permission_codes.dart';
import 'package:ural_erp/data/database/database.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting());
  tearDown(() async {
    // ⚠️ لا `db.close()` — يعلّق في المنطقة الوهميّة بانتظار مؤقّت drift.
  });

  Future<(int roleId, int allowId, int condId)> seed() async {
    final roleId = await db.insertRole(name: 'دورُ الاختبار');
    final all = await db.getAllPermissions();
    // كودان حقيقيّان من البذرة — لا كودٌ مخترَع.
    final a = all.firstWhere((p) => p.code == PermissionCodes.posAccess);
    final c = all.firstWhere((p) => p.code == PermissionCodes.posDiscount);
    return (roleId, a.id, c.id);
  }

  group('النموذجُ يحفظ النمطَ ويُرجعه', () {
    test('الافتراضُ `allow` — والاتّجاهُ أمنيٌّ لا تفصيليّ', () async {
      final (roleId, a, c) = await seed();
      await db.setRolePermissions(roleId, [a, c]);
      final modes = await db.getRolePermissionModes(roleId);
      expect(modes[a], PermissionCodes.grantAllow);
      expect(modes[c], PermissionCodes.grantAllow);
      // ⚠️ لو صار الافتراضُ `conditional` لتحوّل كلُّ نظامٍ قائمٍ فجأةً إلى
      //    سؤال مسؤولٍ في كلّ ضغطة — فالفحصُ يحمي الاتّجاه لا القيمة.
    });

    test('المشروطُ يُكتَب ويُقرأ، والباقي يبقى `allow`', () async {
      final (roleId, a, c) = await seed();
      await db.setRolePermissions(
        roleId,
        [a, c],
        modes: {c: PermissionCodes.grantConditional},
      );
      final modes = await db.getRolePermissionModes(roleId);
      expect(modes[a], PermissionCodes.grantAllow);
      expect(modes[c], PermissionCodes.grantConditional);
    });

    test('وسحبُ الصلاحية يمحو نمطَها معها', () async {
      final (roleId, a, c) = await seed();
      await db.setRolePermissions(roleId, [a, c],
          modes: {c: PermissionCodes.grantConditional});
      await db.setRolePermissions(roleId, [a]);
      final modes = await db.getRolePermissionModes(roleId);
      expect(modes.containsKey(c), isFalse,
          reason: 'بقي نمطٌ لصلاحيةٍ مسحوبة — فمنحُها ثانيةً يعيدها مشروطةً '
              'بلا أن يطلب أحدٌ ذلك.');
    });
  });

  group('قائمةُ أكواد المستخدم تحمل العلامة', () {
    test('`cond:` تُلحَق للمشروط وحدَه', () async {
      final (roleId, a, c) = await seed();
      await db.setRolePermissions(roleId, [a, c],
          modes: {c: PermissionCodes.grantConditional});
      final userId = await db.createUser(
        username: 'condtest',
        password: 'x1234567',
        displayName: 'مختبِر',
        roleId: roleId,
      );

      final codes = await db.getUserPermissionCodes(userId);

      // الكودان ممنوحان — والمشروطُ **ممنوحٌ أيضاً**، وهذا جوهرُ المعنى.
      expect(codes, contains(PermissionCodes.posAccess));
      expect(codes, contains(PermissionCodes.posDiscount));

      expect(PermissionCodes.isConditionalIn(codes, PermissionCodes.posDiscount),
          isTrue);
      expect(PermissionCodes.isConditionalIn(codes, PermissionCodes.posAccess),
          isFalse,
          reason: 'كودٌ غيرُ مشروطٍ حمل علامةَ الشرط — فكلُّ ضغطةٍ تسأل '
              'مسؤولاً بلا سبب.');
    });
  });

  group('⚠️ المزامنةُ لا تُسقط النمط', () {
    test('upsert بـcompanion بلا `grantMode` يُبقي المشروطَ كما هو', () async {
      final (roleId, a, c) = await seed();
      await db.setRolePermissions(roleId, [a, c],
          modes: {c: PermissionCodes.grantConditional});

      // نفسُ ما يفعله `role_permission_sync_strategy` حرفيّاً: companion
      // بحقلَي المفتاح وحدَهما، ثمّ `insertOnConflictUpdate`.
      await db.into(db.rolePermissions).insertOnConflictUpdate(
            RolePermissionsCompanion(
              roleId: Value(roleId),
              permissionId: Value(c),
            ),
          );

      final modes = await db.getRolePermissionModes(roleId);
      expect(modes[c], PermissionCodes.grantConditional,
          reason: 'سحبُ المزامنة كتب `allow` فوقَ نمطٍ مشروط — انحدارٌ '
              'أمنيٌّ صامت. من أضاف `grantMode` إلى الـcompanion عليه أن '
              'يمرّره من الخادم، لا أن يكتب الافتراضَ فوقَ اختيار المشغّل.');
    });
  });
}
