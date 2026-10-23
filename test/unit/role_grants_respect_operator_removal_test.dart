// نزعُ صلاحيةٍ من دورٍ يبقى منزوعاً بعد الإقلاع.
//
// ── البلاغ الميدانيّ (2026-08-11) ────────────────────────────────────────
// «مع تحديد الصلاحيات للمستخدم لا تنطبق للمستخدم» — الدورُ المجرَّب **كاشير**،
// أُعِدّ من حساب مدير النظام، ثم خروجٌ ودخولٌ بالكاشير.
//
// ── الجذرُ المقيس ─────────────────────────────────────────────────────────
// `RoleGrantPreflightService.grantMissingDefaults()` تعمل في **كلّ إقلاع**
// (`database_startup.dart`) وتُدرج كلَّ صلاحيةٍ في مصفوفة الافتراضات ناقصةٍ
// عن الدور. فالكتابةُ من الشاشة تنجح وتصل القاعدةَ صحيحة — ثم يُعيدها
// الإقلاعُ التالي. والمشغّلُ يرى «حفظتُ ولم يتغيّر شيء».
//
// وتعليقُ الدالّة يصفها بأنها «آمنةٌ ومتعادلة» — وهي متعادلةٌ **مع نفسها**
// لا مع قرار المشغّل. نفسُ فئة §٣-ب: إصلاحُ إقلاعٍ يدوس اختياراً صريحاً.
//
// ── ولماذا بصمةٌ لا علَمٌ أعمى ────────────────────────────────────────────
// غرضُ الدالّة الأصليُّ سليم: ترقيةٌ تضيف `sales_create` للكاشير يجب أن تصل
// بلا أن يضغط المشغّلُ «منح الصلاحيات الافتراضية» (مقيسٌ ميدانياً 2026-05-17
// أنهم لا يعرفون أن يضغطوا). فعلَمٌ يُرفع مرّةً للأبد كان سيمنع كلَّ ترقيةٍ
// لاحقة. والبصمةُ تفرّق بين الحالتين: تتغيّر مع المصفوفة وحدَها.

import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/core/permissions/role_grant_matrix.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/services/role_grant_preflight_service.dart';

void main() {
  late AppDatabase db;

  const roleName = 'كاشير';

  setUp(() async {
    db = AppDatabase.forTesting();
    // الإقلاعُ نفسُه شغّل الإصلاحَ وختم بصمتَه، فنحاكي تركيبةً ميدانيةً
    // مستقرّةً: المصفوفةُ مطبَّقةٌ سلفاً والمشغّلُ على وشك أن يعدّل.
  });

  tearDown(() => db.close());

  Future<int> roleIdOf(String name) async {
    final role = await (db.select(db.roles)..where((r) => r.name.equals(name)))
        .getSingleOrNull();
    expect(role, isNotNull, reason: 'دورُ «$name» مبذورٌ في كلّ تنصيب');
    return role!.id;
  }

  Future<Set<String>> grantsOf(int roleId) async {
    final perms = await db.getPermissionsForRole(roleId);
    return perms.map((p) => p.code).toSet();
  }

  /// صلاحيةٌ تمنحها المصفوفةُ للكاشير — نزعُها هو ما يجرّبه المشغّل.
  Future<String> aMatrixGrantForCashier(int roleId) async {
    final matrix = RoleGrantMatrix.defaultGrants[roleName];
    expect(matrix, isNotNull, reason: 'الكاشير دورٌ معروفٌ في المصفوفة');
    final held = await grantsOf(roleId);
    final candidate = matrix!.firstWhere(
      held.contains,
      orElse: () => throw StateError('الكاشير لا يحمل أيّاً من مصفوفته'),
    );
    return candidate;
  }

  test('البلاغُ حرفياً: صلاحيةٌ نزعها المدير تبقى منزوعةً بعد الإقلاع',
      () async {
    final roleId = await roleIdOf(roleName);
    final victim = await aMatrixGrantForCashier(roleId);

    // ما تفعله شاشةُ إدارة الصلاحيات بالضبط: تكتب المجموعةَ الجديدة.
    final kept = (await grantsOf(roleId))..remove(victim);
    final allPerms = await db.getAllPermissions();
    final idByCode = {for (final p in allPerms) p.code: p.id};
    await db.setRolePermissions(
      roleId,
      [for (final c in kept) if (idByCode.containsKey(c)) idByCode[c]!],
    );
    expect(await grantsOf(roleId), isNot(contains(victim)),
        reason: 'الكتابةُ نفسُها سليمةٌ — العطبُ ليس فيها');

    // والآن الإقلاعُ التالي.
    await RoleGrantPreflightService(db).grantMissingDefaultsOnce();

    expect(
      await grantsOf(roleId),
      isNot(contains(victim)),
      reason: 'الإقلاعُ أعاد «$victim» فداس قرارَ المشغّل — وهو البلاغُ '
          'بعينه: يُعِدّ الكاشيرَ ثم يخرج ويدخل فيجد كلَّ شيءٍ كما كان',
    );
  });

  test('وضابط: ترقيةٌ تغيّر المصفوفةَ تصل بلا ضغطِ زرّ', () async {
    // بلا هذا لَمرّ «إصلاحٌ» يوقف الدالّةَ للأبد، فتضيع الغايةُ الأصلية:
    // مقيسٌ ميدانياً (2026-05-17) أن الترقيةَ التي أضافت `sales_create`
    // للكاشير لم تصل، وظلّ يصطدم بـ403 حتى بدّلها المشغّلُ يدوياً.
    final roleId = await roleIdOf(roleName);
    final victim = await aMatrixGrantForCashier(roleId);

    final kept = (await grantsOf(roleId))..remove(victim);
    final allPerms = await db.getAllPermissions();
    final idByCode = {for (final p in allPerms) p.code: p.id};
    await db.setRolePermissions(
      roleId,
      [for (final c in kept) if (idByCode.containsKey(c)) idByCode[c]!],
    );

    // بصمةٌ مغايرةٌ = مصفوفةٌ تغيّرت بترقية.
    await db.setSetting(kRoleGrantMatrixFingerprint, 'ترقيةٌ-سابقة-مختلفة');
    await RoleGrantPreflightService(db).grantMissingDefaultsOnce();

    expect(await grantsOf(roleId), contains(victim),
        reason: 'ترقيةُ المصفوفة يجب أن تصل تلقائياً — وإلا عاد عطبُ ٢٠٢٦-٠٥-١٧');
  });

  test('وتشغيلٌ ثانٍ بنفس المصفوفة لا يفعل شيئاً', () async {
    final roleId = await roleIdOf(roleName);
    await RoleGrantPreflightService(db).grantMissingDefaultsOnce();
    final before = await grantsOf(roleId);

    final applied = await RoleGrantPreflightService(db).grantMissingDefaultsOnce();

    expect(applied, 0, reason: 'البصمةُ مختومةٌ فلا عمل');
    expect(await grantsOf(roleId), before);
  });
}
