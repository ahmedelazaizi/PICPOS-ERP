// ═══════════════════════════════════════════════════════════════════════════
// مانعُ Go ٢‑٨ — كلُّ ريالٍ يُنسَب إلى **درجه** في الأستاذ
// ═══════════════════════════════════════════════════════════════════════════
//
// `linkUnlinkedSafesToSubAccounts` تُنشئ لكلِّ خزنةٍ حساباً فرعيّاً
// `111-0000N` — **شقيقاً** لـ`1111` لا ابناً له. وقيودُ الخزينة كانت تُرحَّل
// على حساب الغرض العامّ بينما المالُ يتحرّك على خزنةٍ بعينها.
//
// 🔴 والأثرُ لا يظهر في المجاميع: مجموعُ الشجرة تحت `111` يبقى صحيحاً —
// ولهذا بقي اختبارُ اتّفاق الأستاذ أخضرَ سنواتٍ — لكنّ **نسبةَ كلِّ ريالٍ
// إلى درجه ضاعت**: رصيدُ الدرج يتحرّك في جدوله وحسابُه في الأستاذ يبقى
// صفراً، و`1111` يحمل حركاتٍ لا خزنةَ تملكها.
//
// وهذا الملفُّ هو **شبكةُ الحماية الوحيدة** لهذا التغيير: بدونه لا شيءَ
// يمنع رِجْلاً من العودة إلى الحساب العامّ.

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';

void main() {
  late AppDatabase db;
  late int branchId;
  late int userId;
  late int drawerSafeId;

  setUp(() async {
    db = AppDatabase.forTesting();
    await db.syncDefaultAccounts();

    branchId = await db.into(db.branches).insert(
          BranchesCompanion.insert(
            name: 'BR-ATTR',
            globalId: const Value('gid-br-attr'),
          ),
        );
    final roleId = await db.into(db.roles).insert(
          RolesCompanion.insert(
              name: 'cashier-attr', isSystemRole: const Value(false)),
        );
    userId = await db.createUser(
      username: 'cashier_attr',
      password: 'pw',
      displayName: 'CA',
      roleId: roleId,
    );
    drawerSafeId = await db.into(db.safes).insert(
          SafesCompanion.insert(
            name: 'درج الكاشير — نسبة',
            branchId: Value(branchId),
            safeType: const Value('cash'),
            balance: const Value(0),
            globalId: const Value('gid-safe-attr-drawer'),
          ),
        );
    // الدرجُ أُدرج **بعد** الإقلاع فلا رابطَ له — نربطه كما يفعل الردمُ
    // في التنصيبات الحقيقيّة، وإلّا سقط كلُّ شيءٍ إلى حساب الغرض ومرّ
    // الاختبارُ لسببٍ خاطئ.
    await db.linkUnlinkedSafesToSubAccounts();
  });

  tearDown(() => db.close());

  /// صافي (‏مدين − دائن) على حسابٍ بعينه من كلِّ القيود المرحَّلة.
  Future<double> netOf(int accountId) async {
    final row = await db.customSelect(
      'SELECT COALESCE(SUM(jel.debit) - SUM(jel.credit), 0) AS net '
      'FROM journal_entry_lines jel '
      'INNER JOIN journal_entries je ON je.id = jel.entry_id '
      'WHERE jel.account_id = ?',
      variables: [Variable<int>(accountId)],
    ).getSingle();
    return (row.data['net'] as num?)?.toDouble() ?? 0.0;
  }

  test('التجهيزة: الدرجُ والمركزيّةُ لكلٍّ حسابُه، وكلاهما ليس 1111',
      () async {
    final drawer = await db.getSafeById(drawerSafeId);
    final central = await db.getCentralSafe();
    final generic = await db.getAccountByCode('1111');

    expect(drawer!.linkedAccountId, isNotNull,
        reason: 'الردمُ ربط الدرج — بدونه لا يقيس الاختبارُ شيئاً');
    expect(central, isNotNull);
    expect(central!.linkedAccountId, isNotNull,
        reason: 'الخزنةُ المركزيّةُ مربوطةٌ كذلك');
    expect(drawer.linkedAccountId, isNot(central.linkedAccountId));
    expect(drawer.linkedAccountId, isNot(generic!.id),
        reason: 'حسابُ الدرج شقيقٌ لـ1111 لا هو');
  });

  test('الإقفالُ اليوميّ: الدرجُ يُدان والمركزيّةُ تُدان، و1111 لا يتحرّك',
      () async {
    // نقدٌ في الدرج.
    await db.adjustSafeBalance(drawerSafeId, 300.0);

    final drawer = await db.getSafeById(drawerSafeId);
    final central = await db.getCentralSafe();
    final generic = await db.getAccountByCode('1111');

    final genericBefore = await netOf(generic!.id);

    await db.closeSafe(drawerSafeId, userId: userId);

    // الرصيدُ انتقل فعلاً.
    expect((await db.getSafeById(drawerSafeId))!.balance, closeTo(0, 0.001));
    expect((await db.getSafeById(central!.id))!.balance, closeTo(300, 0.001),
        reason: 'المالُ ينتقل لا يتبخّر');

    // 🔴 المعطوب: المدينُ كان على `1111` ⇒ حسابُ المركزيّة صفرٌ إلى الأبد.
    expect(await netOf(central.linkedAccountId!), closeTo(300.0, 0.01),
        reason: 'حسابُ الخزنة المركزيّة يُدان بما استلمته فعلاً');
    expect(await netOf(drawer!.linkedAccountId!), closeTo(-300.0, 0.01),
        reason: 'حسابُ الدرج يُدان دائناً بما خرج منه');
    expect(await netOf(generic.id), closeTo(genericBefore, 0.01),
        reason: 'الحسابُ العامُّ لا يحمل حركةً لا خزنةَ تملكها');
  });

  test('الشجرةُ تحت 111 تبقى متّزنةً — الانتقالُ لا يخلق مالاً', () async {
    await db.adjustSafeBalance(drawerSafeId, 250.0);

    final parent = await db.getAccountByCode('111');
    final subtree = await db.accountSubtreeIds(parent!.id);
    Future<double> subtreeNet() async {
      var total = 0.0;
      for (final id in subtree) {
        total += await netOf(id);
      }
      return total;
    }

    final before = await subtreeNet();
    await db.closeSafe(drawerSafeId, userId: userId);
    final after = await subtreeNet();

    expect(after, closeTo(before, 0.01),
        reason: 'تحويلٌ بين خزنتَين صافيه صفرٌ على مستوى المجموعة — '
            'وهذا عينُ ما كان يُخفي العطب: المجموعُ صحيحٌ والنسبةُ خاطئة');
  });
}
