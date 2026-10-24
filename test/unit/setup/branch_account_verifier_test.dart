// P6 · B10 — التحقق من حساب الفرع المركزي: جلسة الخادم شرط (SEC-004)، رسالة حارس
// وصول الفرع تظهر كما هي، وفرع الجهاز يُحفظ قبل التحقق، وكلمة المرور لا تُستعمل إلا
// في النداء. قاعدة حقيقية في الذاكرة تعطي UserWithRole الحقيقي.
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/core/i18n/tr.dart';
import 'package:picpos_erp/data/database/database_barrel.dart';
import 'package:picpos_erp/domain/repositories/auth_repository.dart';
import 'package:picpos_erp/services/setup/branch_account_verifier.dart';

class _Auth extends Fake implements IAuthRepository {
  _Auth(this.events, this.result, {this.throwing});
  final List<String> events;
  final UserWithRole? result;
  final Object? throwing;
  List<String> codes = ['a', 'b', 'c', 'd'];

  @override
  Future<UserWithRole?> authenticateUser(String username, String password) async {
    events.add('auth:$username');
    if (throwing != null) throw throwing!;
    return result;
  }

  @override
  Future<List<String>> getUserPermissionCodes(int userId) async => codes;
}

void main() {
  late AppDatabase db;
  late UserWithRole admin;

  setUpAll(() => I18nCatalog.setCatalog(const {}));
  setUp(() async {
    db = AppDatabase.forTesting();
    admin = (await db.getUserByUsername('admin'))!;
  });
  tearDown(() async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    await db.close();
  });

  BranchAccountVerifier make(
    List<String> events,
    _Auth auth, {
    bool session = true,
  }) =>
      BranchAccountVerifier(
        auth: auth,
        hasServerSession: (_) => session,
        saveClientBranchId: (id) async => events.add('branch:$id'),
      );

  test('نجاح: جلسة الخادم + الدور + أبرز ثلاث صلاحيات، والفرع قبل التحقق', () async {
    final ev = <String>[];
    final r = await make(ev, _Auth(ev, admin))
        .verify(username: ' admin ', password: 'x', branchId: 7);
    expect(r.ok, isTrue);
    expect(r.permissionCount, 4);
    expect(r.topPermissions, ['a', 'b', 'c']);
    expect(r.roleName, isNotEmpty);
    expect(ev, ['branch:7', 'auth:admin']);
  });

  test('تحقق محلي سليم لكن بلا جلسة خادم ⇒ رفض (SEC-004)', () async {
    // حسابٌ غير ملزَم بتغيير كلمته: السبب «تعذّر إنشاء جلسة».
    final free = UserWithRole(
      user: admin.user.copyWith(forcePasswordChange: false),
      role: admin.role,
    );
    final ev = <String>[];
    final r = await make(ev, _Auth(ev, free), session: false)
        .verify(username: 'admin', password: 'x', branchId: 7);
    expect(r.ok, isFalse);
    expect(r.error, contains('جلسة'));
  });

  test('حساب ملزم بتغيير كلمته بلا جلسة ⇒ سبب محدد لا «تعذّر الاتصال»', () async {
    expect(admin.user.forcePasswordChange, isTrue, reason: 'admin المزروع ملزم');
    final ev = <String>[];
    final r = await make(ev, _Auth(ev, admin), session: false)
        .verify(username: 'admin', password: 'x', branchId: 7);
    expect(r.ok, isFalse);
    expect(r.error, contains('ملزم بتغيير كلمة المرور'));
    // ومعه جلسة (حساب ملزم لكن الخادم قبله) ⇒ يُقبل.
    final ok = await make(ev, _Auth(ev, admin))
        .verify(username: 'admin', password: 'x', branchId: 7);
    expect(ok.ok, isTrue);
  });

  test('بيانات خاطئة، وحارس وصول الفرع، وخطأ غير متوقع', () async {
    final ev = <String>[];
    var r = await make(ev, _Auth(ev, null))
        .verify(username: 'u', password: 'p', branchId: 1);
    expect(r.ok, isFalse);
    expect(r.error, contains('غير صحيحة'));

    r = await make(ev, _Auth(ev, null, throwing: StateError('ليس لديك صلاحية الدخول لهذا الفرع')))
        .verify(username: 'u', password: 'p', branchId: 1);
    expect(r.error, 'ليس لديك صلاحية الدخول لهذا الفرع');

    r = await make(ev, _Auth(ev, null, throwing: Exception('net')))
        .verify(username: 'u', password: 'p', branchId: 1);
    expect(r.ok, isFalse);
    expect(r.error, contains('net'));
  });

  test('حقول فارغة ⇒ رفض فوري دون أي نداء', () async {
    final ev = <String>[];
    final r = await make(ev, _Auth(ev, admin))
        .verify(username: '', password: '', branchId: 1);
    expect(r.ok, isFalse);
    expect(ev, isEmpty);
  });
}