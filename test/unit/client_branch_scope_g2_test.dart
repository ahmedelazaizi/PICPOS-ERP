// المرحلة ١ / G2 — دخول «أدمن» على جهاز عميل كان يزيل `branch_id` من كل
// عمليات السحب. المطابقة النصّية على اسم الدور ليست صلاحية.
//
// ── ليه الاختبار بينادي `login()` الحقيقية بدل ما يحطّ العلَم بإيده ──────────
// النسخة الأولى من الاختبار كانت بتضبط العلَم `false` يدوياً لـ«مدير مالي»
// و«كاشير». ده **مدخل مستحيل**: الإنتاج وقتها كان بينشر العمود
// `roles.isSystemRole` وحده، وهو `true` للاتنين
// (`database_seeder_permissions.dart:574-617` بيزرع خمسة أدوار كده: مدير
// النظام · كاشير · مخزني · محاسب · مدير مالي). فالاختبار كان بيأكّد على حالة
// ما بتحصلش، وما كانش يقدر يمسك إن الكاشير بياخد سحب غير مقيّد.
//
// فكل حالة هنا بتعدّي على `AuthNotifier.login()` الحقيقية، فاللي يتأكّد عليه
// هو ما **ينشره الإنتاج فعلاً** لهذا الدور، لا ما يتمنّاه الاختبار.
//
// بلا قاعدة بيانات: المسار المُختبَر يقرأ `SharedPreferences` وحقول
// `SyncInterceptor` الساكنة فقط.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:picpos_erp/data/database/sync_interceptor.dart';
// يُصدِّر `database.dart` و`auth_providers.dart` معاً — استيرادهما بجانبه
// يرفع `unnecessary_import`.
import 'package:picpos_erp/data/providers/providers.dart';
import 'package:picpos_erp/services/network_service.dart';
import 'package:picpos_erp/services/server_proxy.dart';

/// دور + مستخدم كما تزرعهما قاعدة البيانات. [isSystemRole] منفصل عن الاسم
/// عمداً: الاقتران بينهما هو بالضبط ما تفحصه هذه الاختبارات.
UserWithRole _userWithRole({
  required String roleName,
  required bool isSystemRole,
  int userId = 5,
}) {
  final role = Role(
    id: 1,
    name: roleName,
    isSystemRole: isSystemRole,
    createdAt: DateTime(2026),
    rowVersion: 0,
  );
  final user = User(
    id: userId,
    username: 'u$userId',
    passwordHash: 'h',
    passwordSalt: '',
    displayName: 'مستخدم $userId',
    roleId: role.id,
    defaultScreen: 'pos',
    isLocked: false,
    isActive: true,
    discountLimitIsPercent: true,
    forcePasswordChange: false,
    createdAt: DateTime(2026),
    rowVersion: 0,
  );
  return UserWithRole(user: user, role: role);
}

/// جهاز مرآة — الغرض منه قلب [SyncInterceptor.isMirrorMode] فقط.
class _MirrorInterceptor implements SyncInterceptor {
  @override
  bool get isClientModeImpl => true;
  @override
  bool get isMirrorModeImpl => true;
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized(); // لازم لقناة SharedPreferences

  late ProviderContainer container;

  setUp(() {
    SharedPreferences.setMockInitialValues({'client_branch_id': 7});
    NetworkService.instance.debugSetModeForTests(NetworkMode.standalone);
    SyncInterceptor.instance = null;
    SyncInterceptor.currentUserId = null;
    SyncInterceptor.currentUserRole = null;
    SyncInterceptor.currentUserIsSystemAdmin = null;
    // `login()` تُطلق `_refreshActorBranchScope()` بلا انتظار، وهي تقرأ
    // `databaseProvider`. هذا الاختبار لا شأن له بنطاق الفروع، وفتح قاعدة
    // حقيقية يجعل ذلك العمل غير المنتظر يكتمل **بعد** نهاية الاختبار فيلمس
    // حاوية متخلَّصاً منها. نجعل القراءة ترمي: الإنتاج يمسكها بـ try/catch
    // ويسقط على «محصور» وهو الافتراض الآمن — فالمسار المُختبَر لا يتأثر.
    container = ProviderContainer(overrides: [
      databaseProvider.overrideWith(
        (ref) => throw UnimplementedError('لا قاعدة بيانات في اختبار الوحدة'),
      ),
    ]);
    container.read(authProvider);
  });

  tearDown(() {
    container.dispose();
    SyncInterceptor.instance = null;
  });

  /// تسجيل دخول حقيقي ثم قراءة الحصر الناتج.
  Future<String> paramAfterLogin(UserWithRole u) async {
    container.read(authProvider.notifier).login(u);
    return ServerProxy.instance.debugBranchScopeQueryParam();
  }

  group('G2 — تجاوز الأدمن مُغلق', () {
    test('«كاشير» دورٌ مزروع بـ isSystemRole=true ومع ذلك يتحصر', () async {
      final param = await paramAfterLogin(
        _userWithRole(roleName: 'كاشير', isSystemRole: true),
      );

      expect(SyncInterceptor.currentUserIsSystemAdmin, isFalse,
          reason: 'isSystemRole وحده يعني «دور مدمج» لا «مدير نظام» — الزارع '
              'يضعه true للكاشير أيضاً');
      expect(param, '&branch_id=7',
          reason: 'بناء العلَم على العمود وحده كان يمنح الكاشير سحباً غير '
              'مقيّد — أوسع من المطابقة النصّية التي جاء ليستبدلها');
    });

    test('«مدير مالي» مزروع بـ isSystemRole=true ويتحصر (قرار المالك §٢)',
        () async {
      final param = await paramAfterLogin(
        _userWithRole(roleName: 'مدير مالي', isSystemRole: true, userId: 6),
      );

      expect(SyncInterceptor.currentUserIsSystemAdmin, isFalse);
      expect(param, '&branch_id=7');
    });

    test('«مسؤول مبيعات» لا يحصل على سحب غير مقيّد', () async {
      final param = await paramAfterLogin(
        _userWithRole(roleName: 'مسؤول مبيعات', isSystemRole: false),
      );

      expect(param, '&branch_id=7',
          reason: 'المطابقة النصّية على «مسؤول» منحت صلاحية كاملة لدور مبيعات');
    });

    test('دور مخصص اسمه «مدير النظام» لا يُعفى — شرط isSystemRole', () async {
      final param = await paramAfterLogin(
        _userWithRole(roleName: 'مدير النظام', isSystemRole: false),
      );

      expect(param, '&branch_id=7',
          reason: 'بدون شرط isSystemRole يخترع أي مشغّل دوراً بهذا الاسم '
              'ويتجاوز الحصر');
    });

    test('مدير النظام وحده يُعفى — لإعداد البدء', () async {
      final param = await paramAfterLogin(
        _userWithRole(roleName: 'مدير النظام', isSystemRole: true, userId: 1),
      );

      expect(SyncInterceptor.currentUserIsSystemAdmin, isTrue);
      expect(param, '');
    });

    test('جهاز عميل بلا client_branch_id يفشل مقفولاً', () async {
      SharedPreferences.setMockInitialValues(const {}); // بلا ربط
      final param = await paramAfterLogin(
        _userWithRole(roleName: 'كاشير', isSystemRole: true),
      );

      expect(param, '&branch_id=-1',
          reason: 'جهاز غير مربوط سحب بلا قيد — هذا هو التسريب');
    });

    test('جهاز المرآة بلا تغيير — لا سنتينل ولا حصر (المواصفة §٢)', () async {
      SharedPreferences.setMockInitialValues(const {}); // المرآة لا تُربط بفرع
      SyncInterceptor.instance = _MirrorInterceptor();

      expect(await ServerProxy.instance.debugBranchScopeQueryParam(), '',
          reason: 'سنتينل -1 على مرآة معها توكن أدمن = صفر صفوف بينما '
              'العلامة المائية تتقدّم فوق استجابة فارغة');
    });
  });

  group('G2 — دورة حياة العلَم', () {
    test('الخروج يمسح العلَم فلا يرثه المستخدم التالي', () async {
      await paramAfterLogin(
        _userWithRole(roleName: 'مدير النظام', isSystemRole: true, userId: 1),
      );
      expect(SyncInterceptor.currentUserIsSystemAdmin, isTrue);

      container.read(authProvider.notifier).logout();

      expect(SyncInterceptor.currentUserIsSystemAdmin, isNull);
      expect(await ServerProxy.instance.debugBranchScopeQueryParam(),
          '&branch_id=7',
          reason: 'علَم جلسة سابقة باقٍ = إعفاء موروث');
    });

    test('الترقية ترفع العلَم وإسقاطها يعيده', () async {
      final param = await paramAfterLogin(
        _userWithRole(roleName: 'كاشير', isSystemRole: true),
      );
      expect(param, '&branch_id=7');

      container.read(authProvider.notifier).elevate(
            _userWithRole(
                roleName: 'مدير النظام', isSystemRole: true, userId: 1),
          );
      expect(await ServerProxy.instance.debugBranchScopeQueryParam(), '',
          reason: 'الترقية تعمل بهوية الأدمن');

      container.read(authProvider.notifier).dropElevation();
      expect(await ServerProxy.instance.debugBranchScopeQueryParam(),
          '&branch_id=7',
          reason: 'إسقاط الترقية لا بد أن يسحب الإعفاء معه');
    });
  });
}
