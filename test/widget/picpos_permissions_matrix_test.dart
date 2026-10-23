// مصفوفةُ الأدوار والصلاحيات — نسخةُ PicPos.
//
// ═══ لماذا اختبارُ تركيبٍ لا اختبارُ قطعة ═══
//
// المصفوفةُ **جدولٌ ثنائيُّ البعد** داخلَ حوارٍ محدودِ العرض: صفوفٌ بعددِ
// الصلاحيات وأعمدةٌ بعددِ الأدوار. وأخطرُ ما فيها ليس منطقَ التبديل بل
// **التخطيط**: صفٌّ بـ`CrossAxisAlignment.stretch` في ارتفاعٍ غيرِ محدودٍ
// ينهار، وجدولٌ أعرضُ من حاويته يفيض بشريطٍ أصفرَ وأسودَ فوق الواجهة.
//
// ولا يمسك التحليلُ أيّاً من الاثنين — كلاهما يقع في زمن التشغيل. ولذلك
// يُقاس هنا **عرضان**: عرضٌ يتّسع للجدول وعرضٌ لا يتّسع، ويُشترط في كلٍّ
// منهما ألّا ترمي الشجرةُ استثناءً.
//
// ⚠️ **ولا يكفي «لم تنهر»**: كلُّ فحصٍ هنا يؤكّد أنّ المحتوى المقصودَ ظاهرٌ
// فعلاً — أسماءُ الأدوار في الرؤوس، وعنوانُ الصلاحية في الصفّ. فشجرةٌ فارغةٌ
// لا ترمي شيئاً وتمرّ.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:picpos_erp/core/permissions/permission_codes.dart';
import 'package:picpos_erp/data/providers/providers.dart';
import 'package:picpos_erp/domain/repositories/auth_repository.dart';
import 'package:picpos_erp/presentation/settings_picpos/widgets/permissions_matrix_picpos.dart';

/// مستودعٌ زائفٌ ينفّذ الأربعَ التي تستعملها المصفوفةُ وحدَها.
///
/// `noSuchMethod` تغطّي باقي الواجهة: أيُّ نداءٍ لم تُنفَّذ دالّتُه يرمي —
/// وهذا مقصود، فالمصفوفةُ لا يجوز أن تنادي غيرَ هذه الأربع.
class _FakeAuthRepo implements IAuthRepository {
  _FakeAuthRepo({
    required this.roles,
    required this.perms,
    required this.grants,
  });

  final List<Role> roles;
  final List<Permission> perms;
  final Map<int, Set<int>> grants;

  /// أنماطُ المنح — الدور → الصلاحية → `allow` أو `conditional`.
  final Map<int, Map<int, String>> modes = {};

  /// ما وصل إلى الحفظ فعلاً — يقيسه الاختبارُ بدل أن يفترض النجاح.
  final List<(int, List<int>, Map<int, String>?)> saved = [];

  @override
  Future<List<Role>> getAllRoles() async => roles;

  @override
  Future<List<Permission>> getAllPermissions() async => perms;

  @override
  Future<List<Permission>> getPermissionsForRole(int roleId) async {
    final ids = grants[roleId] ?? const <int>{};
    return perms.where((p) => ids.contains(p.id)).toList();
  }

  @override
  Future<void> setRolePermissions(
    int roleId,
    List<int> permissionIds, {
    Map<int, String>? modes,
  }) async {
    saved.add((roleId, permissionIds, modes));
    grants[roleId] = permissionIds.toSet();
    if (modes != null) this.modes[roleId] = modes;
  }

  @override
  Future<Map<int, String>> getRolePermissionModes(int roleId) async => {
        for (final id in grants[roleId] ?? const <int>{})
          id: modes[roleId]?[id] ?? 'allow',
      };

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

Role _role(int id, String name) => Role(
      id: id,
      name: name,
      isSystemRole: true,
      createdAt: DateTime(2026, 1, 1),
      rowVersion: 0,
    );

Permission _perm(int id, String code, String name, String category) =>
    Permission(id: id, code: code, name: name, category: category);

void main() {
  // صلاحيةٌ ماليّةٌ حرجةٌ حقيقيّة — لا كودٌ مخترَعٌ للاختبار. لو خرجت من
  // `criticalFinancialOps` يوماً سقط هذا الفحصُ بدل أن يمرَّ على وهم.
  //
  // ⚠️ **وحرجٌ لا يكفي — لازم يكون قابلَ التبديل أيضاً.** أوّلُ اختيارٍ كان
  //    `deletePostedJournal` وهو حرجٌ **و**في `nonToggleable` معاً، فالمصفوفةُ
  //    تستبعده بحقٍّ ووجدَ الفحصُ صفراً. صفرُ المطابقات اختيارٌ غلطٌ لا عطبٌ.
  const criticalCode = PermissionCodes.overrideCreditLimit;

  late _FakeAuthRepo repo;

  setUp(() {
    repo = _FakeAuthRepo(
      roles: [
        _role(1, 'مدير النظام'),
        _role(2, 'كاشير'),
        _role(3, 'محاسب'),
        _role(4, 'مخزني'),
        _role(5, 'مدير فرع'),
        _role(6, 'مدير مالي'),
      ],
      perms: [
        _perm(10, 'pos_access', 'الوصول للبيع السريع', 'pos'),
        _perm(11, 'pos_discount', 'تطبيق خصم', 'pos'),
        _perm(20, 'treasury_view', 'عرض الخزينة', 'treasury'),
        _perm(30, criticalCode, 'تجاوز حدّ الائتمان', 'critical_financial'),
        // كودٌ غيرُ قابلٍ للتبديل — يجب ألّا يظهر في المصفوفة أصلاً.
        _perm(40, 'products_view', 'عرض المنتجات', 'products'),
      ],
      grants: {
        1: {10, 11, 20},
        2: {10},
        3: {20},
        4: <int>{},
        5: {10, 20},
        6: {20, 30},
      },
    );
  });

  Future<void> open(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [authRepositoryProvider.overrideWithValue(repo)],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => showPermissionsMatrixPicpos(context),
                  child: const Text('افتح'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('افتح'));
    await tester.pumpAndSettle();
  }

  /// تفكيكُ الشجرة ودفعُ إطارٍ — الوصفةُ التي تمنع تعليقَ اختبارات الشاشات.
  Future<void> teardownTree(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }

  group('التركيب على عرضين', () {
    for (final entry in const [
      ('عرضٌ يتّسع للجدول', Size(1600, 900)),
      ('عرضٌ لا يتّسع فيُمرَّر أفقيّاً', Size(1000, 760)),
    ]) {
      final label = entry.$1;
      final size = entry.$2;

      testWidgets('$label — بلا فيضٍ ولا انهيار', (tester) async {
        await open(tester, size);

        // ‏١) لا استثناءَ تخطيطٍ (‏الفيضُ يُبلَّغ استثناءً في الاختبارات).
        expect(tester.takeException(), isNull,
            reason: 'انهيارُ تخطيطٍ أو فيضٌ عند العرض ${size.width}');

        // ‏٢) والمحتوى ظاهرٌ فعلاً — لا شجرةٌ فارغةٌ تمرّ بصمت.
        expect(find.text('مصفوفة الأدوار والصلاحيات'), findsOneWidget);
        expect(find.text('مدير النظام'), findsOneWidget);
        expect(find.text('كاشير'), findsOneWidget);
        expect(find.text('الصلاحية'), findsOneWidget);
        expect(find.text('الوصول للبيع السريع'), findsOneWidget);

        await teardownTree(tester);
      });
    }
  });

  testWidgets('الأكوادُ غيرُ القابلة للتبديل مستبعدةٌ من المصفوفة',
      (tester) async {
    // فرضيّةُ الفحص مقيسةٌ لا مفترَضة: `products_view` ما زال في القائمة.
    expect(PermissionCodes.nonToggleable.containsKey('products_view'), isTrue,
        reason: 'تغيّرت القائمةُ — اختر كوداً آخرَ بدل إسقاط الفحص');

    await open(tester, const Size(1600, 900));
    expect(find.text('عرض المنتجات'), findsNothing);
    // والقابلةُ للتبديل من نفس الجولة ظاهرةٌ — فالغيابُ ترشيحٌ لا فشلُ تحميل.
    expect(find.text('عرض الخزينة'), findsOneWidget);
    await teardownTree(tester);
  });

  testWidgets('الصلاحيةُ الماليّةُ الحرجةُ تحمل مثلَّثَ التحذير',
      (tester) async {
    // فرضيّتان تُقاسان لا تُفترَضان: الكودُ حرجٌ **و**قابلٌ للتبديل. سقوطُ
    // أيٍّ منهما يعني اختيارَ كودٍ آخرَ لا إسقاطَ الفحص.
    expect(PermissionCodes.criticalFinancialOps.contains(criticalCode), isTrue);
    expect(PermissionCodes.nonToggleable.containsKey(criticalCode), isFalse,
        reason: 'كودٌ حرجٌ وغيرُ قابلٍ للتبديل تستبعده المصفوفةُ بحقّ — '
            'فيقرأ الفحصُ صفراً ويبدو عطباً وليس بعطب');

    await open(tester, const Size(1600, 900));
    expect(find.text('تجاوز حدّ الائتمان'), findsOneWidget);
    expect(find.byIcon(PhosphorIconsBold.warning), findsWidgets);
    await teardownTree(tester);
  });

  group('التعديلُ المعلَّق', () {
    testWidgets('الضغطةُ تُنشئ بطاقةَ تعديلٍ ورقاقةَ ترويسة، والعكسُ يمحوهما',
        (tester) async {
      await open(tester, const Size(1600, 900));

      // لا تعديلَ بعد — التلميحُ يعلن صفراً والرقاقةُ غائبة.
      expect(find.textContaining('0 تعديل معلّق'), findsOneWidget);
      expect(find.textContaining('تعديل غير محفوظ'), findsNothing);

      // خليّةُ «تطبيق خصم» (‏١١) لدور «مدير النظام» (‏١) — وهو يملكها
      // **مسموحةً**، فالدورةُ منها: مسموح ← مشروط ← ممنوع ← مسموح.
      final cell = find.byKey(const ValueKey('mx-cell-1-11'));
      expect(cell, findsOneWidget);
      await tester.tap(cell);
      await tester.pumpAndSettle();

      expect(find.textContaining('1 تعديل معلّق'), findsOneWidget);
      expect(find.textContaining('1 تعديل غير محفوظ'), findsOneWidget);
      // ⚠️ **النصُّ يجب أن يقول «مشروطاً» لا «منح»**: الصلاحيةُ ممنوحةٌ في
      //    الحالتين، والفرقُ أنّ التنفيذَ يمرّ بموافقة. فنصٌّ يقول «منح»
      //    يُخفي عن المديرِ أنّه اشترط شيئاً.
      expect(
        find.textContaining('جعل «تطبيق خصم» مشروطاً'),
        findsOneWidget,
        reason: 'بطاقةُ التعديل لا تصف الانتقالَ إلى «مشروط».',
      );

      // ← ممنوع
      await tester.tap(cell);
      await tester.pumpAndSettle();
      expect(find.textContaining('سحب «تطبيق خصم»'), findsOneWidget);
      expect(find.textContaining('1 تعديل معلّق'), findsOneWidget);

      // ← مسموح = خطُّ الأساس، فيختفي التعديلُ تماماً ولا يبقى مدخلٌ معلَّقٌ
      //   يساوي أصلَه.
      await tester.tap(cell);
      await tester.pumpAndSettle();
      expect(find.textContaining('0 تعديل معلّق'), findsOneWidget);
      expect(find.textContaining('تعديل غير محفوظ'), findsNothing);

      await teardownTree(tester);
    });

    testWidgets('⚠️ ومفتاحُ الرموز يعلن الحالاتِ الثلاثَ لا حالتين',
        (tester) async {
      // مفتاحٌ ناقصٌ يجعل الخليّةَ الكهرمانيّةَ لغزاً — والمشغّلُ لا يعرف
      // أنّها ممنوحةٌ بشرطٍ لا ممنوعة.
      await open(tester, const Size(1600, 900));
      expect(find.text('مسموح بلا شرط'), findsOneWidget);
      expect(find.text('مشروط — موافقةُ مسؤولٍ في كلّ مرّة'), findsOneWidget);
      expect(find.text('ممنوع'), findsOneWidget);
      await teardownTree(tester);
    });

    testWidgets('زرُّ الحفظ معطَّلٌ بلا تعديل، ويكتب مجموعةَ الدور كاملةً',
        (tester) async {
      await open(tester, const Size(1600, 900));

      final saveBtn = find.widgetWithText(ElevatedButton, 'حفظ المصفوفة');
      expect(saveBtn, findsOneWidget);
      expect(
        tester.widget<ElevatedButton>(saveBtn).onPressed,
        isNull,
        reason: 'الحفظُ مفعَّلٌ بلا تعديلٍ معلَّق',
      );

      // «تطبيق خصم» (‏١١) لدور «مدير النظام» (‏١): ضغطةٌ ⇒ **مشروط**.
      await tester.tap(find.byKey(const ValueKey('mx-cell-1-11')));
      await tester.pumpAndSettle();

      expect(tester.widget<ElevatedButton>(saveBtn).onPressed, isNotNull);
      await tester.tap(saveBtn);
      await tester.pumpAndSettle();

      // ‏`setRolePermissions` تكتب المجموعةَ كاملةً — فالمقيسُ أنّ نداءً
      // واحداً وقع لدورٍ واحد.
      expect(repo.saved.length, 1, reason: 'نداءُ حفظٍ لكلّ خليّةٍ لا لكلّ دور');
      final (roleId, ids, modes) = repo.saved.single;
      expect(roleId, 1);

      // ⚠️ **المشروطُ يبقى في قائمة المعرِّفات** — فهو ممنوحٌ. وإسقاطُه منها
      //    كان سيحوّل «مشروط» إلى «ممنوع» صامتاً، وهو أخطرُ خطأٍ ممكنٍ هنا.
      expect(ids, contains(11),
          reason: 'الصلاحيةُ المشروطةُ سقطت من المنح — صارت ممنوعةً بدل '
              'أن تصير مشروطة.');
      expect(ids, contains(10));
      expect(ids, contains(20));

      // والنمطُ وصل مع المعرِّفات.
      expect(modes, isNotNull, reason: 'حُفظت المعرِّفاتُ بلا أنماطٍ.');
      expect(modes![11], PermissionCodes.grantConditional);
      expect(modes[10], PermissionCodes.grantAllow);
      expect(modes[20], PermissionCodes.grantAllow);

      // ⚠️ الحفظُ يُظهر توستاً بمؤقّتٍ (‏٥ ثوانٍ للنجاح في `AppToast`).
      //    وتفكيكُ الشجرة ومؤقّتٌ معلَّقٌ = فشلُ `!timersPending` — والفحوصُ
      //    أعلاه كانت كلُّها خضراء. فيُستنفَد المؤقّتُ قبل التفكيك.
      await tester.pump(const Duration(seconds: 6));
      await tester.pumpAndSettle();
      await teardownTree(tester);
    });
  });
}
