// المرحلة ١ / G2 — دخول «أدمن» على جهاز عميل كان يزيل `branch_id` من كل
// عمليات السحب. المطابقة النصّية على اسم الدور ليست صلاحية.
//
// بلا قاعدة بيانات: المسار المُختبَر يقرأ `SharedPreferences` وحقول
// `SyncInterceptor` الساكنة فقط.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ural_erp/data/database/sync_interceptor.dart';
import 'package:ural_erp/services/server_proxy.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized(); // لازم لقناة SharedPreferences

  setUp(() async {
    SharedPreferences.setMockInitialValues({'client_branch_id': 7});
    SyncInterceptor.currentUserId = null;
    SyncInterceptor.currentUserRole = null;
    SyncInterceptor.currentUserIsSystemRole = null;
  });

  group('G2 — تجاوز الأدمن مُغلق', () {
    test('«مسؤول مبيعات» لا يحصل على سحب غير مقيّد', () async {
      SyncInterceptor.currentUserId = 5;
      SyncInterceptor.currentUserRole = 'مسؤول مبيعات';
      SyncInterceptor.currentUserIsSystemRole = false;

      expect(
        await ServerProxy.instance.debugBranchScopeQueryParam(),
        '&branch_id=7',
        reason: 'المطابقة النصّية على «مسؤول» منحت صلاحية كاملة لدور مبيعات',
      );
    });

    test('«مدير مالي» يتحصر (قرار المالك §٢)', () async {
      SyncInterceptor.currentUserId = 6;
      SyncInterceptor.currentUserRole = 'مدير مالي';
      SyncInterceptor.currentUserIsSystemRole = false;

      expect(
        await ServerProxy.instance.debugBranchScopeQueryParam(),
        '&branch_id=7',
      );
    });

    test('مدير النظام وحده يُعفى — لإعداد البدء', () async {
      SyncInterceptor.currentUserId = 1;
      SyncInterceptor.currentUserRole = 'مدير النظام';
      SyncInterceptor.currentUserIsSystemRole = true;

      expect(await ServerProxy.instance.debugBranchScopeQueryParam(), '');
    });

    test('جهاز عميل بلا client_branch_id يفشل مقفولاً', () async {
      SharedPreferences.setMockInitialValues(const {}); // بلا ربط
      SyncInterceptor.currentUserId = 5;
      SyncInterceptor.currentUserRole = 'كاشير';
      SyncInterceptor.currentUserIsSystemRole = false;

      expect(
        await ServerProxy.instance.debugBranchScopeQueryParam(),
        '&branch_id=-1',
        reason: 'جهاز غير مربوط سحب بلا قيد — هذا هو التسريب',
      );
    });
  });
}
