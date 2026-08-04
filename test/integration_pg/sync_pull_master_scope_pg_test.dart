// المرحلة ١ / G1 — حصر البيانات الأساسية على `/api/sync/pull`.
//
// قبل الإصلاح: `_syncPullBranchColumn` يحتوي خمسة جداول تعاملية فقط، فسحب
// `warehouses` بـ`branch_id=1` يعيد مخازن كل الفروع. DeltaPull يعمل كل
// دورة ⇒ يعيد ملء قاعدة العميل ببيانات الشركة كاملة، مُلغياً حصر المزامنة
// الكاملة الذي يعمل بشكل صحيح.
@Tags(['pg'])
library;

import 'dart:convert';

import 'package:drift/drift.dart' as d;
import 'package:flutter_test/flutter_test.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:ural_erp/core/logging/diagnostic_logger.dart';
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/services/api/api_handler.dart';
import 'package:ural_erp/services/api/api_user_context.dart';

import '_support/pg_fixture.dart';

void main() {
  late PgTestFixture fx;
  late ApiHandler handler;

  setUpAll(() async {
    fx = await bootPgTestSchema();
    await fx.db.customSelect('SELECT 1').get(); // اطبع أخطاء الترحيل مبكراً
  });

  tearDownAll(() async => fx.tearDown());

  setUp(() async {
    await fx.db.delete(fx.db.warehouses).go();
    await fx.db.delete(fx.db.safes).go();
    await fx.db.delete(fx.db.userBranchAccess).go();
    await fx.db.delete(fx.db.users).go();
    await fx.db.delete(fx.db.roles).go();
    await fx.db.delete(fx.db.branches).go();

    // فرعان حقيقيان — PostgreSQL ينفّذ الـFK الذي كان SQLite يتجاهله.
    await fx.db.customStatement(
      "INSERT INTO branches (id, name) VALUES (1,'فرع أ'),(2,'فرع ب') "
      'ON CONFLICT (id) DO NOTHING',
    );
    handler = ApiHandler(fx.db);
  });

  /// يستدعي `/api/sync/pull` كمستخدم مُعرَّف. حقن الهوية عبر
  /// `request.change(context: ...)` هو ما يفعله `api_auth_middleware:139`
  /// بعد التحقّق من التوكن — بدونه `_extractBranchId` يرى مستدعياً بلا
  /// هوية ويسلك مساراً مختلفاً تماماً، فيصير الاختبار بلا معنى.
  Future<List<Map<String, dynamic>>> pull(
    String table, {
    int? branchId,
    int? userId,
  }) async {
    final qs = branchId == null ? '' : '&branch_id=$branchId';
    var request = shelf.Request(
      'GET',
      Uri.parse('http://localhost/api/sync/pull?table=$table$qs'),
    );
    if (userId != null) {
      request = request.change(context: {ApiUserCtx.userIdKey: userId});
    }
    final response = await handler.buildRouter().call(request);
    final body = jsonDecode(await response.readAsString())
        as Map<String, dynamic>;
    return (body['rows'] as List).cast<Map<String, dynamic>>();
  }

  /// مستخدم مقيَّد على [branchId] — يحتاج صف `userBranchAccess` وإلا
  /// عاملَه `_extractBranchId` كـ«مُساء التزويد» وقصّه على السنتينل.
  Future<void> seedScopedUser(int userId, int branchId) async {
    await fx.db.into(fx.db.roles).insert(
          RolesCompanion.insert(name: 'كاشير')
              .copyWith(id: const d.Value(9)),
        );
    await fx.db.into(fx.db.users).insert(
          UsersCompanion.insert(
            username: 'u$userId',
            passwordHash: 'h',
            displayName: 'u$userId',
            roleId: const d.Value(9),
          ).copyWith(id: d.Value(userId)),
        );
    await fx.db.into(fx.db.userBranchAccess).insert(
          UserBranchAccessCompanion.insert(
            userId: userId,
            branchId: branchId,
          ),
        );
  }

  /// مستخدم مقيَّد على **أكثر من فرع** — «مدير فروع» كما يجلس على جهاز
  /// المرآة: ليس `isFullBranchAccessUser` (الاسم ليس «مدير النظام» ولا
  /// «مدير مالي» والمعرّف ليس ١) ومع ذلك نطاقه أوسع من فرع واحد.
  Future<void> seedMultiBranchUser(int userId, List<int> branchIds) async {
    await fx.db.into(fx.db.roles).insert(
          RolesCompanion.insert(name: 'مدير فروع')
              .copyWith(id: const d.Value(8)),
        );
    await fx.db.into(fx.db.users).insert(
          UsersCompanion.insert(
            username: 'u$userId',
            passwordHash: 'h',
            displayName: 'u$userId',
            roleId: const d.Value(8),
          ).copyWith(id: d.Value(userId)),
        );
    for (final b in branchIds) {
      await fx.db.into(fx.db.userBranchAccess).insert(
            UserBranchAccessCompanion.insert(userId: userId, branchId: b),
          );
    }
  }

  group('G1 — الجداول الأساسية تُحصَر على الفرع', () {
    test('warehouses: الفرع ١ لا يرى مخزن الفرع ٢', () async {
      await seedScopedUser(10, 1);
      await fx.db.into(fx.db.warehouses).insert(
            WarehousesCompanion.insert(name: 'مخزن أ')
                .copyWith(branchId: const d.Value(1)),
          );
      await fx.db.into(fx.db.warehouses).insert(
            WarehousesCompanion.insert(name: 'مخزن ب')
                .copyWith(branchId: const d.Value(2)),
          );

      final rows = await pull('warehouses', branchId: 1, userId: 10);
      final names = rows.map((r) => r['name']).toSet();

      expect(names, contains('مخزن أ'));
      expect(
        names,
        isNot(contains('مخزن ب')),
        reason: 'مخزن الفرع ٢ تسرّب لجهاز مربوط بالفرع ١ — هذا هو G1',
      );
    });

    test('safes: الفرع ١ لا يرى خزنة الفرع ٢', () async {
      await seedScopedUser(11, 1);
      await fx.db.into(fx.db.safes).insert(
            SafesCompanion.insert(name: 'خزنة أ')
                .copyWith(branchId: const d.Value(1)),
          );
      await fx.db.into(fx.db.safes).insert(
            SafesCompanion.insert(name: 'خزنة ب')
                .copyWith(branchId: const d.Value(2)),
          );

      final rows = await pull('safes', branchId: 1, userId: 11);
      final names = rows.map((r) => r['name']).toSet();

      expect(names, contains('خزنة أ'));
      expect(names, isNot(contains('خزنة ب')));
    });

    test('الصفوف بلا فرع تظل ظاهرة (قرار المالك §٢-ب)', () async {
      await seedScopedUser(12, 1);
      await fx.db.into(fx.db.warehouses).insert(
            WarehousesCompanion.insert(name: 'مخزن يتيم'),
          ); // branchId يبقى NULL
      await fx.db.into(fx.db.warehouses).insert(
            WarehousesCompanion.insert(name: 'مخزن ب')
                .copyWith(branchId: const d.Value(2)),
          );

      final rows = await pull('warehouses', branchId: 1, userId: 12);
      final names = rows.map((r) => r['name']).toSet();

      expect(
        names,
        contains('مخزن يتيم'),
        reason: 'الحصر الصارم يُخفي مخازن مشروعة من أجهزة قائمة',
      );
      expect(names, isNot(contains('مخزن ب')));
    });

    test('branches: الجهاز يرى فرعه فقط', () async {
      await seedScopedUser(13, 1);

      final rows = await pull('branches', branchId: 1, userId: 13);
      final names = rows.map((r) => r['name']).toSet();

      expect(names, contains('فرع أ'));
      expect(
        names,
        isNot(contains('فرع ب')),
        reason: 'قائمة الفروع كاملة تصل لجهاز مربوط بفرع واحد',
      );
    });

    test('cost_centers: مشتقّة عكسياً من الفرع ومخازنه وخزائنه', () async {
      await seedScopedUser(14, 1);

      // ⚠️ `CostCenters.code` مطلوب وبلا قيمة افتراضية
      // (accounting_tables.dart:109) — إغفاله يفشل بـNOT NULL لا بمنطق
      // الحصر، فيبدو الاختبار أحمر للسبب الخطأ.
      await fx.db.customStatement(
        'INSERT INTO cost_centers (id, code, name) VALUES '
        "(101,'CC101','مركز الفرع أ'),(102,'CC102','مركز مخزن أ'),"
        "(103,'CC103','مركز خزنة أ'),(201,'CC201','مركز الفرع ب') "
        'ON CONFLICT (id) DO NOTHING',
      );
      await fx.db.customStatement(
        'UPDATE branches SET cost_center_id = 101 WHERE id = 1',
      );
      await fx.db.customStatement(
        'UPDATE branches SET cost_center_id = 201 WHERE id = 2',
      );
      await fx.db.into(fx.db.warehouses).insert(
            WarehousesCompanion.insert(name: 'مخزن أ').copyWith(
              branchId: const d.Value(1),
              costCenterId: const d.Value(102),
            ),
          );
      await fx.db.into(fx.db.safes).insert(
            SafesCompanion.insert(name: 'خزنة أ').copyWith(
              branchId: const d.Value(1),
              costCenterId: const d.Value(103),
            ),
          );

      final rows = await pull('cost_centers', branchId: 1, userId: 14);
      final ids = rows.map((r) => r['id']).toSet();

      expect(ids, containsAll(<int>[101, 102, 103]));
      expect(
        ids,
        isNot(contains(201)),
        reason: 'مركز تكلفة الفرع ٢ تسرّب — الاشتقاق العكسي لا يعمل',
      );
    });

    test('cost_centers: فرع بلا أي ارتباط ⇒ صفر صفوف لا كل الصفوف', () async {
      await seedScopedUser(15, 1);
      await fx.db.customStatement(
        "INSERT INTO cost_centers (id, code, name) VALUES "
        "(301,'CC301','مركز غريب') ON CONFLICT (id) DO NOTHING",
      );

      final rows = await pull('cost_centers', branchId: 1, userId: 15);

      expect(
        rows,
        isEmpty,
        reason: 'مجموعة فارغة انقلبت إلى «بلا حصر» — نفس فئة الفشل المفتوح '
            'التي أغلقها سنتينل _kNoBranchAccess',
      );
    });

    test('العدّاد يحصي صفوف IS NULL — ضبط موجب', () async {
      await seedScopedUser(16, 1);
      // صفّان يتيمان معروفان بالعدد + واحد على الفرع. الضبط الموجب: لو
      // أعاد العدّاد صفراً هنا فالأداة لا تلتقط، فأي «صفر» لاحق بلا قيمة.
      await fx.db.into(fx.db.warehouses).insert(
            WarehousesCompanion.insert(name: 'يتيم ١'),
          );
      await fx.db.into(fx.db.warehouses).insert(
            WarehousesCompanion.insert(name: 'يتيم ٢'),
          );
      await fx.db.into(fx.db.warehouses).insert(
            WarehousesCompanion.insert(name: 'مخزن أ')
                .copyWith(branchId: const d.Value(1)),
          );

      await pull('warehouses', branchId: 1, userId: 16);

      expect(
        ApiHandler.debugLastNullBranchRowCount,
        2,
        reason: 'العدّاد لا يلتقط — أي «صفر» منه بلا قيمة',
      );
    });
  });

  // ── المراجعة النهائية / FR-1 ────────────────────────────────────────────
  // جهاز المرآة معفى من الحصر على الواجهة فلا يرسل `branch_id` إطلاقاً.
  // «مدير فروع» عليه ليس `isFullBranchAccessUser`، فالخادم كان يرى
  // `requested == null` مع `allowed = {1,2,3}` **ويقصّه على فرعه الأصلي**.
  // ومعه توكن جلسة ⇒ `shouldWithholdWatermark` كاذبة ⇒ العلامة المائية
  // تتقدّم فوق استجابة مقصوصة والفرعان ٢ و٣ يتوقّفان عن الوصول للأبد.
  // القرار: بلا `branch_id` + أكثر من فرع مسموح ⇒ `IN (allowed)`.
  group('FR-1 — بلا branch_id ومعه أكثر من فرع ⇒ كل فروعه', () {
    Future<void> seedThirdBranch() => fx.db.customStatement(
          "INSERT INTO branches (id, name) VALUES (3,'فرع ج') "
          'ON CONFLICT (id) DO NOTHING',
        );

    test('warehouses: يرى مخازن الفروع الثلاثة لا فرعه الأصلي وحده', () async {
      await seedThirdBranch();
      await seedMultiBranchUser(20, [1, 2, 3]);
      for (final (name, branch) in [('مخزن أ', 1), ('مخزن ب', 2), ('مخزن ج', 3)]) {
        await fx.db.into(fx.db.warehouses).insert(
              WarehousesCompanion.insert(name: name)
                  .copyWith(branchId: d.Value(branch)),
            );
      }

      final rows = await pull('warehouses', userId: 20); // بلا branch_id
      final names = rows.map((r) => r['name']).toSet();

      expect(
        names,
        containsAll(<String>['مخزن أ', 'مخزن ب', 'مخزن ج']),
        reason: 'الخادم قصّ المرآة على فرع واحد، والعلامة المائية تقدّمت '
            'فوق الاستجابة المقصوصة ⇒ فرعان يتجمّدان بصمت',
      );
    });

    test('safes: نفس الاتّساع', () async {
      await seedThirdBranch();
      await seedMultiBranchUser(21, [1, 2, 3]);
      for (final (name, branch) in [('خزنة أ', 1), ('خزنة ب', 2), ('خزنة ج', 3)]) {
        await fx.db.into(fx.db.safes).insert(
              SafesCompanion.insert(name: name)
                  .copyWith(branchId: d.Value(branch)),
            );
      }

      final rows = await pull('safes', userId: 21);
      final names = rows.map((r) => r['name']).toSet();

      expect(names, containsAll(<String>['خزنة أ', 'خزنة ب', 'خزنة ج']));
    });

    test('branches: الفروع الثلاثة تصل — عمود المفتاح الأساسي', () async {
      await seedThirdBranch();
      await seedMultiBranchUser(22, [1, 2, 3]);

      final rows = await pull('branches', userId: 22);
      final names = rows.map((r) => r['name']).toSet();

      expect(names, containsAll(<String>['فرع أ', 'فرع ب', 'فرع ج']));
    });

    test('cost_centers: اتّحاد مراكز الفروع المسموحة، لا فرع واحد', () async {
      await seedThirdBranch();
      await seedMultiBranchUser(23, [1, 2]);
      await fx.db.customStatement(
        'INSERT INTO cost_centers (id, code, name) VALUES '
        "(101,'CC101','مركز الفرع أ'),(201,'CC201','مركز الفرع ب'),"
        "(301,'CC301','مركز الفرع ج') ON CONFLICT (id) DO NOTHING",
      );
      await fx.db.customStatement(
        'UPDATE branches SET cost_center_id = 101 WHERE id = 1',
      );
      await fx.db.customStatement(
        'UPDATE branches SET cost_center_id = 201 WHERE id = 2',
      );
      await fx.db.customStatement(
        'UPDATE branches SET cost_center_id = 301 WHERE id = 3',
      );

      final rows = await pull('cost_centers', userId: 23);
      final ids = rows.map((r) => r['id']).toSet();

      expect(
        ids,
        containsAll(<int>[101, 201]),
        reason: 'مستخدم يرى مخازن فرعين ومركز تكلفة فرع واحد = نصف إصلاح',
      );
      expect(
        ids,
        isNot(contains(301)),
        reason: 'الاتّحاد اتّسع لفرع غير مسموح',
      );
    });

    test('فرع واحد مسموح ⇒ بلا اتّساع (المسار القديم كما هو)', () async {
      await seedMultiBranchUser(24, [1]);
      await fx.db.into(fx.db.warehouses).insert(
            WarehousesCompanion.insert(name: 'مخزن أ')
                .copyWith(branchId: const d.Value(1)),
          );
      await fx.db.into(fx.db.warehouses).insert(
            WarehousesCompanion.insert(name: 'مخزن ب')
                .copyWith(branchId: const d.Value(2)),
          );

      final rows = await pull('warehouses', userId: 24);
      final names = rows.map((r) => r['name']).toSet();

      expect(names, contains('مخزن أ'));
      expect(names, isNot(contains('مخزن ب')));
    });

    test('اتّساع «بلا branch_id» لا يشتغل على مستدعٍ **له** هوية بفرع واحد',
        () async {
      // الحارس الذي يمنع أن يكون FR-1 قد اتّسع لأكثر من حالته: مستخدم
      // بهوية وفرع واحد لا يرى فرعاً غيره مهما كان مسار الحلّ.
      await seedScopedUser(26, 1);
      await fx.db.into(fx.db.warehouses).insert(
            WarehousesCompanion.insert(name: 'مخزن أ')
                .copyWith(branchId: const d.Value(1)),
          );
      await fx.db.into(fx.db.warehouses).insert(
            WarehousesCompanion.insert(name: 'مخزن ب')
                .copyWith(branchId: const d.Value(2)),
          );

      final rows = await pull('warehouses', userId: 26); // بلا branch_id
      final names = rows.map((r) => r['name']).toSet();

      expect(names, contains('مخزن أ'));
      expect(names, isNot(contains('مخزن ب')));
    });

    test('طلب فرع أجنبي ما زال يُقصّ على فرع واحد', () async {
      await seedThirdBranch();
      await seedMultiBranchUser(25, [1, 2]);
      await fx.db.into(fx.db.warehouses).insert(
            WarehousesCompanion.insert(name: 'مخزن ج')
                .copyWith(branchId: const d.Value(3)),
          );
      await fx.db.into(fx.db.warehouses).insert(
            WarehousesCompanion.insert(name: 'مخزن ب')
                .copyWith(branchId: const d.Value(2)),
          );

      final rows = await pull('warehouses', branchId: 3, userId: 25);
      final names = rows.map((r) => r['name']).toSet();

      expect(
        names,
        isNot(contains('مخزن ج')),
        reason: 'طلب فرع خارج النطاق لا يُشرَّف',
      );
      expect(
        names,
        isNot(contains('مخزن ب')),
        reason: 'الطلب الأجنبي يُقصّ على فرع واحد لا يتّسع لكل النطاق',
      );
    });
  });

  // ── المراجعة النهائية / FR-6 ────────────────────────────────────────────
  // قرار المالك: **البيانات الأساسية تظل كاملة للمستدعي بلا هوية**. إدخال
  // `'branches': 'id'` في خريطة الحصر جعل السحب بلا توكن يُقصّ على السنتينل
  // `-1` ويعيد صفر صفوف بينما `serverTime` غير فارغ ⇒ علامة مائية تتقدّم فوق
  // رد فارغ. `_getSyncPull` كان يمرّر `failClosedOnNoIdentity: true` لكل
  // جدول رغم أن عقد العَلَم نفسه يقول إن جداول المرجع لا تفشل مقفولة.
  //
  // الاسترخاء يمسّ **حالة إغفال `branch_id` وحدها**؛ الفوج التالي يثبّت
  // المسارات الثلاثة بالاسم.
  group('FR-6 — البيانات الأساسية بلا توكن', () {
    setUp(() async {
      await fx.db.into(fx.db.warehouses).insert(
            WarehousesCompanion.insert(name: 'مخزن أ')
                .copyWith(branchId: const d.Value(1)),
          );
      await fx.db.into(fx.db.warehouses).insert(
            WarehousesCompanion.insert(name: 'مخزن ب')
                .copyWith(branchId: const d.Value(2)),
          );
      await fx.db.into(fx.db.warehouses).insert(
            WarehousesCompanion.insert(name: 'مخزن يتيم'),
          );
    });

    test('مسار ١: بلا توكن وبلا branch_id ⇒ كامل (منع تعطيل التزويد)',
        () async {
      final rows = await pull('warehouses');
      final names = rows.map((r) => r['name']).toSet();

      expect(
        names,
        containsAll(<String>['مخزن أ', 'مخزن ب', 'مخزن يتيم']),
        reason: 'التزويد قبل أول دخول يقرأ البيانات الأساسية كاملة؛ القصّ '
            'على السنتينل كان يُقدّم العلامة المائية فوق رد فارغ',
      );

      final branchRows = await pull('branches');
      expect(
        branchRows.map((r) => r['name']).toSet(),
        containsAll(<String>['فرع أ', 'فرع ب']),
      );
    });

    test('مسار ٢: بلا توكن مع branch_id=N ⇒ محصور على N', () async {
      // جهاز مربوط قبل الدخول: `_branchScopeQueryParam` يبعث التفضيل بلا
      // نظر للتوكن. حصر العميل الذاتي لا بد أن ينجو من استرخاء FR-6.
      final rows = await pull('warehouses', branchId: 1);
      final names = rows.map((r) => r['name']).toSet();

      expect(names, contains('مخزن أ'));
      expect(names, contains('مخزن يتيم')); // ذراع IS NULL — قرار §٢-ب
      expect(
        names,
        isNot(contains('مخزن ب')),
        reason: 'استرخاء «بلا branch_id» تسرّب لحالة الطلب الصريح',
      );
    });

    test('مسار ٣: بلا توكن مع branch_id=-1 ⇒ صفر (الحصر الذاتي باقٍ)',
        () async {
      // جهاز غير مربوط يفشل مقفولاً من عند نفسه بإرسال السنتينل.
      final rows = await pull('warehouses', branchId: -1);
      final names = rows.map((r) => r['name']).toSet();

      expect(
        names,
        isNot(anyOf(contains('مخزن أ'), contains('مخزن ب'))),
        reason: 'السنتينل انقلب إلى قراءة واسعة — هذا هو الفشل المفتوح الذي '
            'أُغلق في شغل منفصل',
      );

      // `branches` عموده هو المفتاح الأساسي فلا صفوف NULL فيه إطلاقاً:
      // صفر حرفي، وهو أنظف تعبير عن «الحصر الذاتي ما زال يقفل».
      final branchRows = await pull('branches', branchId: -1);
      expect(branchRows, isEmpty);
    });
  });

  // ── المراجعة النهائية / FR-3 ────────────────────────────────────────────
  // السطر كان مشروطاً بـ`nullRows > 0`، فغياب السطر بعد أسبوع تشغيل يعني
  // «نظيف» **أو** «لم يُقَس قط» ولا سبيل للمالك للتفريق. المواصفة §٦ تقول
  // حرفياً إن صفر سطور ليس دليلاً.
  group('FR-3 — أول قياس يُنتج سطراً ولو كان صفراً', () {
    test('صفر صفوف يتيمة ⇒ سطر [BRANCH-SCOPE-NULL] موجود', () async {
      ApiHandler.debugResetNullBranchLogThrottle();
      DiagnosticLogger.enableTestMode();
      await seedScopedUser(30, 1);
      await fx.db.into(fx.db.warehouses).insert(
            WarehousesCompanion.insert(name: 'مخزن أ')
                .copyWith(branchId: const d.Value(1)),
          );

      await pull('warehouses', branchId: 1, userId: 30);

      expect(
        DiagnosticLogger.testLog
            .where((l) => l.contains('BRANCH-SCOPE-NULL'))
            .length,
        1,
        reason: 'الصمت لا يُميّز «نظيف» عن «لم يُقَس» — والعدّاد وُجد ليتّخذ '
            'المالك قرار التشديد على أرقام',
      );
      expect(
        DiagnosticLogger.testLog.last,
        contains('nullRows=0'),
      );
    });

    test('السحب المتكرّر بنفس العدد لا يكرّر السطر (الخانق باقٍ)', () async {
      ApiHandler.debugResetNullBranchLogThrottle();
      DiagnosticLogger.enableTestMode();
      await seedScopedUser(31, 1);
      await fx.db.into(fx.db.warehouses).insert(
            WarehousesCompanion.insert(name: 'مخزن أ')
                .copyWith(branchId: const d.Value(1)),
          );

      await pull('warehouses', branchId: 1, userId: 31);
      await pull('warehouses', branchId: 1, userId: 31);
      await pull('warehouses', branchId: 1, userId: 31);

      expect(
        DiagnosticLogger.testLog
            .where((l) => l.contains('BRANCH-SCOPE-NULL'))
            .length,
        1,
        reason: 'DeltaPull يسحب بلا توقّف — سطر لكل سحب يُغرق الملف ويُتلف '
            'المراجعة نفسها',
      );
    });
  });
}
