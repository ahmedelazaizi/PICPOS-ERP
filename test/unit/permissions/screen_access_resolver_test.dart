// P2 (2026-10-18) — قاعدة فتح الشاشة: أيُّ كودٍ من مجموعتها، لا كودٌ واحد.
//
// يثبّت: (١) القاعدة نفسَها، (٢) الاستثناءات (إعدادات/مستخدمون/أدوار)،
// (٣) أنّ فتحَ الشاشة لا يمنح فعلاً فيها (الأمان)، (٤) أنّ المجموعات متّسقة مع
// `masterList` و`screenPermissionMap`، (٥) نقلَ الحجوزات إلى `bookings_view`.
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/core/navigation/screen_id.dart';
import 'package:picpos_erp/core/permissions/permission_codes.dart';
import 'package:picpos_erp/core/permissions/screen_access_resolver.dart';
import 'package:picpos_erp/data/providers/auth_providers.dart';
import 'package:picpos_erp/domain/models/table_actions.dart';
import 'package:picpos_erp/presentation/bookings_picpos/widgets/booking_permission_gates.dart';
import 'package:picpos_erp/domain/models/picpos_booking_view.dart';
import 'package:picpos_erp/presentation/widgets/permission_guard.dart';

bool _opens(Iterable<String> perms, ScreenId id, {bool bypass = false}) =>
    canOpenScreen(perms, id,
        primaryCode: screenPermissionMap[id], bypass: bypass);

void main() {
  group('canOpenScreen', () {
    test('أيُّ كودٍ من مجموعة الشاشة يفتحها', () {
      // `products_edit` وحدَه (والكودُ الأصلي `products_add`) — القبول الحرفي.
      expect(_opens({'products_edit'}, ScreenId.products), isTrue);
      expect(_opens({'products_add'}, ScreenId.products), isTrue);
      expect(_opens({'bookings_add'}, ScreenId.bookings), isTrue);
      expect(_opens({'tables_reserve'}, ScreenId.tables), isTrue);
    });

    test('بلا أيّ كودٍ من المجموعة لا تُفتح', () {
      expect(_opens(<String>{}, ScreenId.tables), isFalse);
      expect(_opens({'sales_view'}, ScreenId.tables), isFalse);
      expect(_opens({'pos_access'}, ScreenId.products), isFalse);
    });

    test('كودُ شاشةٍ أخرى لا يفتح هذه (tables_view لم يعد يفتح الحجوزات)', () {
      expect(_opens({'tables_view'}, ScreenId.bookings), isFalse);
      expect(_opens({'bookings_view'}, ScreenId.tables), isFalse);
      expect(_opens({'products_edit'}, ScreenId.categories), isFalse);
    });

    test('تجاوزُ مدير النظام يفتح كلَّ شيء، حتى بلا أكواد', () {
      for (final id in screenPermissionMap.keys) {
        expect(_opens(<String>{}, id, bypass: true), isTrue, reason: '$id');
      }
    });

    test('strict يعيد السلوكَ القديم (كودٌ واحد بالضبط)', () {
      expect(
        canOpenScreen({'products_edit'}, ScreenId.products,
            primaryCode: 'products_add', bypass: false, strict: true),
        isFalse,
      );
      expect(
        canOpenScreen({'products_add'}, ScreenId.products,
            primaryCode: 'products_add', bypass: false, strict: true),
        isTrue,
      );
    });

    test('شاشةٌ بلا بوّابة (primaryCode=null) مفتوحة', () {
      expect(
          canOpenScreen(<String>{}, ScreenId.pos, primaryCode: null,
              bypass: false),
          isTrue);
    });

    test('الصلاحيةُ المشروطة (cond:) تفتح الشاشة وتُعرَف كمشروطة', () {
      final perms = ['tables_reserve', 'cond:tables_reserve'];
      expect(_opens(perms, ScreenId.tables), isTrue);
      expect(isConditional(perms, 'tables_reserve'), isTrue);
      expect(isConditional(['tables_reserve'], 'tables_reserve'), isFalse);
    });
  });

  group('استثناءات F.2: الإعدادات والمستخدمون والأدوار', () {
    test('الإعدادات تبقى على settings_view وحده', () {
      // أيُّ كودٍ فرعيٍّ من فئة الإعدادات لا يفتحها.
      for (final code in [
        'settings_edit',
        'settings_company',
        'settings_backup',
        'settings_tax',
        'users_manage',
      ]) {
        expect(_opens({code}, ScreenId.settings), isFalse, reason: code);
      }
      expect(_opens({'settings_view'}, ScreenId.settings), isTrue);
    });

    test('مجموعةُ الشاشة الصارمة هي كودُها فقط', () {
      for (final id in strictPermissionScreens) {
        expect(screenPermissionSet(id, 'x_code'), {'x_code'}, reason: '$id');
        expect(screenActionCodes.containsKey(id), isFalse, reason: '$id');
      }
      expect(strictPermissionScreens, containsAll(<ScreenId>[
        ScreenId.settings,
        ScreenId.users,
        ScreenId.rolesAndPermissions,
      ]));
    });
  });

  group('الأمان: فتحُ الشاشة لا يمنح فعلاً فيها', () {
    test('مستخدمٌ بـ tables_reserve فقط يفتح الطاولات ولا ينفّذ غير الحجز', () {
      final perms = ['tables_reserve'];
      expect(_opens(perms, ScreenId.tables), isTrue);
      final allowed = <TableAction>[];
      for (final a in TableAction.values) {
        final code = permissionForAction(a);
        if (code == null) continue; // قراءةُ السجلّ لا تحتاج كوداً
        if (hasPermissionWithAdminBypass(perms, code)) allowed.add(a);
      }
      expect(allowed, [TableAction.reserve]);
    });

    test('مستخدمٌ بـ bookings_add فقط يفتح الحجوزات ولا يرى التقارير/الإعدادات', () {
      final perms = ['bookings_add'];
      expect(_opens(perms, ScreenId.bookings), isTrue);
      expect(bookingDestinationAllowed(perms, BookingsDestination.board), isTrue);
      expect(bookingDestinationAllowed(perms, BookingsDestination.reports),
          isFalse);
      expect(bookingDestinationAllowed(perms, BookingsDestination.settings),
          isFalse);
      // ولا يملك أفعالَ الحالة/الإلغاء/إدارة الكتالوج.
      for (final code in [
        bookingStatusPermission('confirmed'),
        bookingStatusPermission('cancelled'),
        PermissionCodes.bookingsServicesManage,
        PermissionCodes.bookingsResourcesManage,
        PermissionCodes.bookingsDeposit,
      ]) {
        expect(hasPermissionWithAdminBypass(perms, code), isFalse,
            reason: code);
      }
      expect(hasPermissionWithAdminBypass(perms, PermissionCodes.bookingsAdd),
          isTrue);
    });

    test('مديرُ النظام يرى كلَّ وجهات الحجوزات', () {
      final admin = ['system_admin'];
      for (final d in BookingsDestination.values) {
        expect(bookingDestinationAllowed(admin, d), isTrue, reason: '$d');
      }
    });

    test('الإلغاء كودٌ مستقلٌّ عن تغيير الحالة', () {
      expect(bookingStatusPermission('cancelled'), PermissionCodes.bookingsCancel);
      expect(bookingStatusPermission('seated'), PermissionCodes.bookingsStatus);
      expect(bookingStatusPermission(''), PermissionCodes.bookingsStatus);
    });

    test('مستخدمٌ بلا أيّ كودٍ لا يفتح الطاولات ولا الحجوزات', () {
      expect(_opens(<String>[], ScreenId.tables), isFalse);
      expect(_opens(<String>[], ScreenId.bookings), isFalse);
    });
  });

  group('اتّساق المجموعات', () {
    final master = PermissionCodes.masterList.map((m) => m['code']!).toSet();

    test('كلُّ كودٍ في screenActionCodes موجود في masterList', () {
      for (final e in screenActionCodes.entries) {
        for (final c in e.value) {
          expect(master.contains(c), isTrue, reason: '${e.key}: $c');
        }
      }
    });

    test('لا كودَ nonToggleable ولا حرجٌ ماليّاً في مجموعات الأفعال', () {
      for (final e in screenActionCodes.entries) {
        for (final c in e.value) {
          expect(PermissionCodes.nonToggleable.containsKey(c), isFalse,
              reason: '${e.key}: $c لا يفعل شيئاً أصلاً');
          expect(PermissionCodes.criticalFinancialOps.contains(c), isFalse,
              reason: '${e.key}: $c حرجٌ ماليّاً');
        }
      }
    });

    test('كلُّ شاشةٍ في screenPermissionMap مجموعتُها تحوي كودَها', () {
      for (final e in screenPermissionMap.entries) {
        expect(screenPermissionSet(e.key, e.value), contains(e.value),
            reason: '${e.key}');
      }
    });

    test('كلُّ شاشةٍ في screenActionCodes مسجّلةٌ في screenPermissionMap', () {
      for (final id in screenActionCodes.keys) {
        expect(screenPermissionMap.containsKey(id), isTrue,
            reason: '$id بلا كودٍ أصليّ في الخريطة');
      }
    });
  });

  group('F.6: الحجوزات على bookings_view', () {
    test('الخريطةُ وعنصرُ القائمة', () {
      expect(screenPermissionMap[ScreenId.bookings], 'bookings_view');
      final nav = kAllNavItemDefs
          .where((i) => i.index == ScreenId.bookings.navigationIndex)
          .toList();
      expect(nav, isNotEmpty);
      expect(nav.every((i) => i.permission == 'bookings_view'), isTrue);
    });
  });
}
