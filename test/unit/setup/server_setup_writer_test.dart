// P5 — كاتب بيانات المقرّ (‏قاعدة SQLite في الذاكرة بنفس واجهة PostgreSQL):
// الفروع بالرمز idempotent، كلمة المسؤول تتغير فلا يبقى admin/admin، المستخدمون
// بنطاق فرعهم (HQ · ALL · رمز)، سياسة الدخول دون اتصال، والمعرّف الثابت للشركة.
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/core/i18n/tr.dart';
import 'package:picpos_erp/data/database/database_barrel.dart';
import 'package:picpos_erp/services/setup/server_setup_writer.dart';

ServerSetupInput _input({
  List<ServerSetupBranch> branches = const [],
  List<ServerSetupUser> users = const [],
  int offlineDays = 7,
  String adminPassword = 'Adm1n#Strong',
}) =>
    ServerSetupInput(
      companyName: 'شركة الأمل',
      currency: 'JOD',
      businessProfile: 'restaurant',
      businessType: 'restaurant',
      vatEnabled: true,
      vatRate: 16,
      fiscalYear: 2026,
      branchName: 'المقر الرئيسي',
      branchCode: 'HQ-1',
      warehouseName: 'مخزن المقر',
      adminPassword: adminPassword,
      developerPassword: 'dev12345',
      branches: branches,
      users: users,
      offlineDays: offlineDays,
      tablesEnabled: true,
      deliveryEnabled: true,
      tableSection: 'القاعة',
      tableNames: const ['طاولة 1', 'طاولة 2'],
    );

void main() {
  late AppDatabase db;
  final writer = ServerSetupWriter();

  setUpAll(() => I18nCatalog.setCatalog(const {}));

  setUp(() async {
    db = AppDatabase.forTesting();
    await db.getBranches(); // يفتح القاعدة ويشغّل البذر
  });

  tearDown(() async {
    // فاحصُ تصادم كلمات المرور يعمل بلا انتظار — يُترك ينتهي قبل الإغلاق.
    await Future<void>.delayed(const Duration(milliseconds: 600));
    await db.close();
  });

  Future<List<Branche>> allBranches() => db.select(db.branches).get();

  test('الفروع بالرمز: تشغيلان ⇒ لا تكرار، والرئيسي المزروع يُعاد تسميته', () async {
    final input = _input(branches: const [
      ServerSetupBranch(code: 'AMM', name: 'فرع عمّان'),
      ServerSetupBranch(code: 'ZRQ', name: 'فرع الزرقاء'),
    ]);
    final before = (await allBranches()).length;
    final r1 = await writer.apply(db, input);
    final afterFirst = await allBranches();
    final r2 = await writer.apply(db, input);
    final afterSecond = await allBranches();

    expect(afterSecond.length, afterFirst.length, reason: 'لا فرع جديد في الثانية');
    expect(afterFirst.length, before + 2, reason: 'الرئيسي أُعيد استعماله + فرعان');
    expect(r1.branchIds['HQ'], r2.branchIds['HQ']);
    final main = afterSecond.firstWhere((b) => b.id == r2.branchIds['HQ']);
    expect(main.name, 'المقر الرئيسي');
    expect(main.code, 'HQ-1');
    expect(afterSecond.where((b) => b.code == 'AMM'), hasLength(1));
  });

  test('كلمة المسؤول تتغير ولا تعمل admin/admin بعد الإنهاء', () async {
    await writer.apply(db, _input());
    expect(await db.authenticateUser('admin', 'admin'), isNull);
    expect(await db.authenticateUser('admin', 'Adm1n#Strong'), isNotNull);
  });

  test('المستخدمون: HQ ⇒ الرئيسي، ALL ⇒ كل الفروع، رمز ⇒ فرعه، وإعادة التشغيل تحدّث', () async {
    final roles = await db.getAllRoles();
    final cashier = roles.firstWhere((r) => r.name == 'كاشير');
    final manager = roles.firstWhere((r) => r.name == 'مدير فرع');
    final input = _input(
      branches: const [ServerSetupBranch(code: 'AMM', name: 'فرع عمّان')],
      users: [
        ServerSetupUser(
          name: 'كاشير عمّان',
          username: 'cash.amm',
          password: 'Cash#Amm123',
          roleName: cashier.name,
          scope: 'AMM',
        ),
        ServerSetupUser(
          name: 'مدير الكل',
          username: 'mgr.all',
          password: 'Mgr#All4567',
          roleName: manager.name,
          scope: 'ALL',
        ),
        ServerSetupUser(
          name: 'كاشير المقر',
          username: 'cash.hq',
          password: 'Cash#Hq9876',
          roleId: cashier.id,
          scope: 'HQ',
          forcePasswordChange: false,
        ),
      ],
    );
    final r1 = await writer.apply(db, input);
    expect((r1.createdUsers, r1.updatedUsers), (3, 0));
    final ids = r1.branchIds;

    Future<List<int>> access(String u) async {
      final user = (await db.getUserByUsername(u))!;
      return (await db.getRawUserBranchAssignments(user.user.id))..sort();
    }

    expect(await access('cash.amm'), [ids['AMM']]);
    expect(await access('cash.hq'), [ids['HQ']]);
    expect(await access('mgr.all'), ([ids['HQ']!, ids['AMM']!]..sort()));
    final amm = (await db.getUserByUsername('cash.amm'))!;
    expect(amm.role?.name, 'كاشير');
    expect(amm.user.forcePasswordChange, isTrue);
    expect((await db.getUserByUsername('cash.hq'))!.user.forcePasswordChange, isFalse,
        reason: 'التعطيل من جدول المقر يُحترم عند الإنشاء');

    final r2 = await writer.apply(db, input);
    expect((r2.createdUsers, r2.updatedUsers), (0, 3));
    final usernames = (await db.select(db.users).get())
        .where((u) => u.username == 'cash.amm')
        .length;
    expect(usernames, 1);
  });

  test('سياسة الأوفلاين ومعرّف الشركة ثابت والطاولات idempotent وsetup_completed', () async {
    await writer.apply(db, _input(offlineDays: 14));
    final gid = await db.getSettingValue('company_global_id');
    expect(gid, isNotEmpty);
    expect(await db.getSettingValue('offline_login_grace_days'), '14');
    expect(await db.getSettingValue('system_currency'), 'JOD');
    expect(await db.getSettingValue('business_profile'), 'restaurant');
    expect(await db.getSettingValue('feature.pos.tables'), 'true');
    expect(await db.getSettingValue('setup_completed'), 'true');
    expect(await db.getSettingValue('network_mode'), 'server');
    expect(await db.getSettingValue('developer_password_hash'), isNotEmpty);

    await writer.apply(db, _input(offlineDays: 3));
    expect(await db.getSettingValue('company_global_id'), gid, reason: 'يُولَّد مرة واحدة');
    expect(await db.getSettingValue('offline_login_grace_days'), '3');
    final tables = await db.select(db.restaurantTables).get();
    expect(tables.where((t) => t.name == 'طاولة 1'), hasLength(1));
    final sections = await db.getAllSections();
    expect(sections.where((s) => s.name == 'القاعة'), hasLength(1));
  });

  test('فشل كتابة مستخدم لا يُكتب setup_completed، والإعادة بعد التصحيح تنجح بلا تكرار', () async {
    final roles = await db.getAllRoles();
    final input = _input(users: [
      ServerSetupUser(
        name: 'أ',
        username: 'dup.a',
        password: 'Same#Pass123',
        roleId: roles.first.id,
      ),
      ServerSetupUser(
        name: 'ب',
        username: 'dup.b',
        password: 'Same#Pass123', // كلمة متطابقة ⇒ DuplicatePasswordException
        roleId: roles.first.id,
      ),
    ]);
    await expectLater(writer.apply(db, input), throwsA(anything));
    expect(await db.getSettingValue('setup_completed'), isNot('true'));
    expect(await db.getUserByUsername('dup.b'), isNull);
    // تصحيح الكلمة ثم إعادة المحاولة: dup.a موجود فيُحدَّث ولا يتكرر.
    final fixed = _input(users: [
      input.users[0],
      ServerSetupUser(
        name: 'ب',
        username: 'dup.b',
        password: 'Other#Pass456',
        roleId: roles.first.id,
      ),
    ]);
    final r = await writer.apply(db, fixed);
    expect((r.createdUsers, r.updatedUsers), (1, 1));
    expect(await db.getSettingValue('setup_completed'), 'true');
  });
}
