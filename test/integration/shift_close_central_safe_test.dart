// نقدية الوردية كانت **بتتبخّر** من سجل الخزائن عند الإقفال.
//
// ── العطل ────────────────────────────────────────────────────────────────────
// `_closeShiftSafes` بيعمل `adjustSafeBalance(sId, -actualDrain)` — بيخصم من
// درج الكاشير **من غير خزينة مستقبِلة**. سطر السحب بيتكتب في
// `safe_transactions` بوصف «تحويل حصة الوردية من X إلى الإدارة»، لكن الطرف
// التاني من التحويل ده عمره ما اتنفّذ.
//
// النتيجة: مجموع أرصدة الخزائن بيقلّ كل وردية، فينحرف عن حساب النقدية في
// الأستاذ (اللي **صح** — النقدية بتتقيّد على ١١١١ من ساعة البيع، وتسليم
// الدرج ما بيحركش حاجة في الأستاذ). الفرق اللي اتقاس على الداتا الحيّة
// (٨٩٨ على ٦ ورديات) مصدره ده.
//
// ── القرار (المالك، 2026-08-02) ─────────────────────────────────────────────
// النقدية المسحوبة من الدرج بتترحّل لـ**الصندوق الرئيسي** — الصندوق المركزي
// للإدارة المركزية، اللي منه بيتوزّع على البنوك أو مصروفات موسّعة على مستوى
// الشركة. فهو **خزينة حقيقية** في النظام مش وجهة وهمية.
//
// ── الثابتة اللي الاختبار ده بيحرسها ────────────────────────────────────────
// **مجموع أرصدة كل الخزائن ما بيتغيّرش بالإقفال.** الفلوس بتتنقل مش بتتبخّر.
// أي اختبار بيفحص الدرج لوحده بيفضل أخضر والفلوس ضايعة.
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
            name: 'BR-CENTRAL',
            globalId: const Value('gid-br-central'),
          ),
        );
    final roleId = await db.into(db.roles).insert(
          RolesCompanion.insert(
              name: 'cashier-central', isSystemRole: const Value(false)),
        );
    userId = await db.createUser(
      username: 'cashier_central',
      password: 'pw',
      displayName: 'CC',
      roleId: roleId,
    );
    drawerSafeId = await db.into(db.safes).insert(
          SafesCompanion.insert(
            name: 'درج الكاشير',
            branchId: Value(branchId),
            safeType: const Value('cash'),
            balance: const Value(0),
            globalId: const Value('gid-safe-drawer'),
          ),
        );
  });

  tearDown(() => db.close());

  Future<double> totalSafeBalances() async {
    final all = await db.select(db.safes).get();
    return all.fold<double>(0, (s, x) => s + x.balance);
  }

  Future<void> postReceipt(int safeId, double amount, DateTime at) async {
    final current = await db.getSafeById(safeId);
    await db.into(db.safeTransactions).insert(
          SafeTransactionsCompanion.insert(
            voucherNumber: 'RCT-${at.microsecondsSinceEpoch}',
            safeId: safeId,
            transactionType: 'receipt',
            category: 'sale',
            amount: amount,
            balanceAfter: (current?.balance ?? 0) + amount,
            userId: Value(userId),
            createdAt: Value(at),
          ),
        );
    await db.adjustSafeBalance(safeId, amount);
  }

  Future<int> openShift(DateTime at) => db.into(db.shifts).insert(
        ShiftsCompanion.insert(
          userId: userId,
          startTime: at,
          status: 'open',
          globalId: Value('gid-shift-${at.microsecondsSinceEpoch}'),
        ),
      );

  test('الصندوق الرئيسي مزروع كخزينة حقيقية', () async {
    final central = await db.getCentralSafe();
    expect(central, isNotNull,
        reason: 'الوجهة لازم تكون خزينة في النظام مش وجهة وهمية');
    expect(central!.id, isNot(drawerSafeId));
  });

  test('إقفال الوردية بينقل النقدية للصندوق الرئيسي — مجموع الخزائن ثابت',
      () async {
    final at = DateTime.now().subtract(const Duration(hours: 3));
    final shiftId = await openShift(at);
    await postReceipt(drawerSafeId, 100, at.add(const Duration(hours: 1)));

    final totalBefore = await totalSafeBalances();
    expect(totalBefore, 100);

    await db.closeShiftWithAudit(shiftId, 100);

    expect((await db.getSafeById(drawerSafeId))!.balance, 0,
        reason: 'الدرج اتسلّم');

    final central = await db.getCentralSafe();
    expect(central!.balance, 100, reason: 'الإدارة استلمت');

    expect(await totalSafeBalances(), totalBefore,
        reason: 'الفلوس بتتنقل مش بتتبخّر — دي الثابتة اللي انكسرت');
  });

  test('سطر استلام مقابل في سجل حركات الصندوق الرئيسي', () async {
    final at = DateTime.now().subtract(const Duration(hours: 3));
    final shiftId = await openShift(at);
    await postReceipt(drawerSafeId, 100, at.add(const Duration(hours: 1)));
    await db.closeShiftWithAudit(shiftId, 100);

    final central = await db.getCentralSafe();
    final rows = await (db.select(db.safeTransactions)
          ..where((t) => t.safeId.equals(central!.id)))
        .get();
    expect(rows, hasLength(1),
        reason: 'التحويل لازم يبان على الطرفين مش على الدرج بس');
    expect(rows.single.amount, 100);
    expect(rows.single.transactionType, 'receipt');
    expect(rows.single.balanceAfter, 100);
  });

  test('أكتر من درج في نفس الوردية بيتجمّعوا في الصندوق الرئيسي', () async {
    // ── ليه درجين مش ورديتين ────────────────────────────────────────────────
    // `closeShiftWithAudit` بياخد `DateTime.now()` كنهاية للوردية دايماً،
    // فنافذة أي وردية تانية في نفس الاختبار بتشمل **سحب** الوردية اللي
    // قبلها وصافيها بيطلع صفر. ده خاصية في الكود مش باج، فالاختبار بيقيس
    // التجميع على محور الخزائن بدل محور الزمن.
    final drawer2 = await db.into(db.safes).insert(
          SafesCompanion.insert(
            name: 'درج تاني',
            branchId: Value(branchId),
            safeType: const Value('cash'),
            balance: const Value(0),
            globalId: const Value('gid-safe-drawer-2'),
          ),
        );

    final at = DateTime.now().subtract(const Duration(hours: 3));
    final shiftId = await openShift(at);
    await postReceipt(drawerSafeId, 100, at.add(const Duration(hours: 1)));
    await postReceipt(drawer2, 60, at.add(const Duration(hours: 1)));

    final totalBefore = await totalSafeBalances();
    expect(totalBefore, 160);

    await db.closeShiftWithAudit(shiftId, 160);

    expect((await db.getSafeById(drawerSafeId))!.balance, 0);
    expect((await db.getSafeById(drawer2))!.balance, 0);

    final central = await db.getCentralSafe();
    expect(central!.balance, 160, reason: 'الدرجين اتجمّعوا في الإدارة');
    expect(await totalSafeBalances(), totalBefore,
        reason: 'مجموع الخزائن ثابت مهما كان عدد الأدراج');
  });

  test('إقفال الصندوق الرئيسي نفسه ما بينقلش لنفسه', () async {
    // لو الوردية شغّالة على الصندوق المركزي مباشرة، التحويل لنفسه معناه سطر
    // استلام وهمي ورصيد ما بيتصفّاش.
    final central = await db.getCentralSafe();
    final at = DateTime.now().subtract(const Duration(hours: 3));
    final shiftId = await openShift(at);
    await postReceipt(central!.id, 100, at.add(const Duration(hours: 1)));

    await db.closeShiftWithAudit(shiftId, 100);

    final rows = await (db.select(db.safeTransactions)
          ..where((t) =>
              t.safeId.equals(central.id) & t.transactionType.equals('receipt')))
        .get();
    expect(rows.where((r) => r.category == 'shift_closing'), isEmpty,
        reason: 'مفيش تحويل لنفسه');
  });

  // ═══════════════════════════════════════════════════════════════════════
  // §٥-١ — بلاغٌ ميدانيّ: مالٌ غير ظاهرٍ عند إقفال الوردية
  // ═══════════════════════════════════════════════════════════════════════
  //
  // اللوج الميدانيّ: `[SHIFT-CLOSE-NO-CENTRAL] safeId=1 amount=140.0` —
  // ٤٦٠ خرجت من ثلاث خزائن ولم تستقبلها خزينة.
  //
  // ── الجذرُ المقيس ───────────────────────────────────────────────────────
  // السحبُ (`adjustSafeBalance(sId, -actualDrain)`) غيرُ مشروط، والاستلامُ
  // بعده «أفضلُ جهد» داخل `try` يكتفي بالتسجيل حين لا يجد مستقبِلاً. فأيُّ
  // حالةٍ يرجع فيها `getCentralSafe()` قيمةَ `null` تحوّل **التحويلَ** إلى
  // **اختفاء** — والحارسُ يسجّل ولا يمنع.
  //
  // وطريقان مقيسان يبلغان تلك الحالة:
  //
  //   ١. قاعدةٌ أُنشئت قبل دخول الصندوق المركزي في البذرة: `seedInitialData`
  //      لا تعمل إلا على قاعدةٍ جديدة أو بلا مستخدمين
  //      (`database_startup.dart:351` و`:367`)، ولا إصلاحَ إقلاعٍ يزرعه.
  //
  //   ٢. حذفُه من شاشة إدارة الصناديق على تنصيبٍ **جديد**: حارسُ
  //      `deleteSafeById` يشترط `isDefault == false` — والصندوقُ المركزيُّ
  //      `isDefault: false` **قصداً** («ده مش صندوق بيع»). وحارسُ القيود لا
  //      يعترض لأن تحويلات الإقفال لا تُنشئ قيداً أصلاً بنصِّ الكود، فحسابُه
  //      يبقى بلا بنودٍ مهما أُقفلت ورديات.
  //
  // والثابتةُ المحروسةُ في هذا الملفّ («مجموع أرصدة الخزائن ثابتٌ بالإقفال»)
  // هي بعينها ما ينكسر — ولم يكن يقيسها اختبارٌ في حالة غياب المستقبِل.
  group('§٥-١ — بلا مستقبِلٍ لا يخرج المال', () {
    Future<void> removeCentralSafe() async {
      final central = await db.getCentralSafe();
      expect(central, isNotNull, reason: 'البذرةُ تُنشئه — نزيله نحن قصداً');
      await (db.delete(db.safes)..where((s) => s.id.equals(central!.id))).go();
      expect(await db.getCentralSafe(), isNull);
    }

    test('مجموعُ أرصدة الخزائن ثابتٌ حتى بلا صندوقٍ مركزيّ', () async {
      await removeCentralSafe();

      final at = DateTime.now().subtract(const Duration(hours: 3));
      final shiftId = await openShift(at);
      await postReceipt(drawerSafeId, 140, at.add(const Duration(hours: 1)));

      final totalBefore = await totalSafeBalances();
      expect(totalBefore, 140);

      await db.closeShiftWithAudit(shiftId, 140);

      expect(await totalSafeBalances(), totalBefore,
          reason: 'بلا مستقبِلٍ لا يُسحب: التحويلُ بلا وجهةٍ ليس تحويلاً، '
              'والسحبُ وحدَه اختفاءٌ لا تسليم');
    });

    test('ولا يُكتب سطرُ سحبٍ يدّعي تحويلاً لم يحدث', () async {
      await removeCentralSafe();

      final at = DateTime.now().subtract(const Duration(hours: 3));
      final shiftId = await openShift(at);
      await postReceipt(drawerSafeId, 140, at.add(const Duration(hours: 1)));

      await db.closeShiftWithAudit(shiftId, 140);

      final drain = await (db.select(db.safeTransactions)
            ..where((t) =>
                t.safeId.equals(drawerSafeId) &
                t.category.equals('shift_closing')))
          .get();
      expect(drain, isEmpty,
          reason: 'سطرٌ وصفُه «تحويل حصة الوردية إلى الإدارة» بلا طرفٍ '
              'مقابلٍ يقرأه المراجعُ تسليماً حدث — وهو لم يحدث');
      expect((await db.getSafeById(drawerSafeId))!.balance, 140,
          reason: 'المالُ باقٍ في الدرج — وهو الصدقُ: لم يستلمه أحد');
    });

    test('ولا يختفي المالُ حين تعمل الوردية على المركزيّ نفسِه', () async {
      // نفسُ الفئة، طريقٌ ثالث: `central.id == sId` يمنع سطرَ الاستلام (وهو
      // صواب — تحويلٌ لنفسه سطرٌ وهميّ) لكنّ السحبَ فوقه غيرُ مشروط، فيخرج
      // المالُ من المركزيّ ولا يستقبله أحد. والاختبارُ القائم يؤكّد غيابَ
      // سطر الاستلام وحدَه فيمرُّ أخضرَ والمالُ ضائع.
      final central = await db.getCentralSafe();
      final at = DateTime.now().subtract(const Duration(hours: 3));
      final shiftId = await openShift(at);
      await postReceipt(central!.id, 140, at.add(const Duration(hours: 1)));

      final totalBefore = await totalSafeBalances();
      await db.closeShiftWithAudit(shiftId, 140);

      expect(await totalSafeBalances(), totalBefore,
          reason: 'تحويلٌ طرفاه واحدٌ حركتُه صفر — لا سحبَ ولا استلام');
    });

    test('ضابط: وجودُ المستقبِل يُعيد السلوكَ الطبيعيَّ كاملاً', () async {
      // بلا هذا الضابط لَمرّ الاختباران فوق على إصلاحٍ يوقف التسليمَ **دائماً**
      // كما يمرّان على إصلاحٍ يوقفه عند غياب المستقبِل وحدَه.
      final at = DateTime.now().subtract(const Duration(hours: 3));
      final shiftId = await openShift(at);
      await postReceipt(drawerSafeId, 140, at.add(const Duration(hours: 1)));

      await db.closeShiftWithAudit(shiftId, 140);

      expect((await db.getSafeById(drawerSafeId))!.balance, 0);
      expect((await db.getCentralSafe())!.balance, 140);
    });
  });
}
