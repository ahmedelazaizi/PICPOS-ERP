// بند 9 — كلمة مرور المطوّر تُطلب في كل جلسة جديدة.
//
// الفتح حالةٌ في الذاكرة فقط (`developerSessionProvider`)، ويجب أن:
//   * يُمسح عند `logout()` وعند تبدّل المستخدم (يغطي قفلَ الخمول لأنه ينتهي
//     بـ`logout()`)،
//   * لا يُمسح بتجديد/نشاط نفس المستخدم،
//   * لا يعيش في أي تخزين: `ProviderContainer` جديد (محاكاة إعادة التشغيل) = مقفل.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/core/config/business_profile_provider.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/data/providers/auth_providers.dart';
import 'package:picpos_erp/presentation/screens/developer_tools_screen.dart';
import 'package:picpos_erp/services/developer_auth_service.dart';
import 'package:picpos_erp/services/network_service.dart';
import 'package:picpos_erp/services/websocket_sync_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

UserWithRole _user(int id) {
  final role = Role(
    id: 1,
    name: 'مدير النظام',
    isSystemRole: true,
    createdAt: DateTime(2026),
    rowVersion: 0,
  );
  final user = User(
    id: id,
    username: 'u$id',
    passwordHash: 'h',
    passwordSalt: '',
    displayName: 'مستخدم $id',
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

class _FakeDevAuth implements DeveloperAuthService {
  @override
  bool get isConfigured => true;

  @override
  Future<bool> verify(String plaintext) async => plaintext == 'dev';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUp(() {
    NetworkService.instance.debugSetModeForTests(NetworkMode.standalone);
    WebSocketSyncClient.instance.connected.value = false;
    SharedPreferences.setMockInitialValues({});
  });

  ProviderContainer newContainer() {
    final c = ProviderContainer();
    // `login()` يطلق تحديثَ نطاق الفروع بشكل غير متزامن؛ نمهله قبل التخلص.
    addTearDown(() async {
      await Future<void>.delayed(const Duration(milliseconds: 300));
      c.dispose();
    });
    c.read(authProvider);
    // الاستماع حيٌّ طوال الاختبار (كما في التطبيق حيث تراقبه الشاشة).
    c.listen(developerSessionProvider, (_, _) {});
    return c;
  }

  group('الجلسة', () {
    test('البداية مقفلة؛ unlock ثم clear؛ extend على مقفلة لا يفعل شيئاً', () {
      final c = newContainer();
      final n = c.read(developerSessionProvider.notifier);
      expect(c.read(developerSessionProvider).isActive, isFalse);
      n.extend();
      expect(c.read(developerSessionProvider).isActive, isFalse);
      n.unlock();
      expect(c.read(developerSessionProvider).isActive, isTrue);
      n.clear();
      expect(c.read(developerSessionProvider).isActive, isFalse);
    });

    test('بعد logout() تُطلب كلمة المرور من جديد', () {
      final c = newContainer();
      c.read(authProvider.notifier).login(_user(1));
      c.read(developerSessionProvider.notifier).unlock();
      expect(c.read(developerSessionProvider).isActive, isTrue);

      c.read(authProvider.notifier).logout();

      expect(c.read(developerSessionProvider).isActive, isFalse);
    });

    test('تبدّل المستخدم (switchUser) يقفل، ودخولُ مستخدمٍ آخر يبقى مقفلاً', () {
      final c = newContainer();
      c.read(authProvider.notifier).login(_user(1));
      c.read(developerSessionProvider.notifier).unlock();

      c.read(authProvider.notifier).switchUser(_user(2));
      expect(c.read(developerSessionProvider).isActive, isFalse);

      c.read(authProvider.notifier).logout();
      c.read(authProvider.notifier).login(_user(3));
      expect(c.read(developerSessionProvider).isActive, isFalse);
    });

    test('نشاطُ نفس المستخدم لا يقفل أثناء العمل', () {
      final c = newContainer();
      c.read(authProvider.notifier).login(_user(1));
      c.read(developerSessionProvider.notifier).unlock();

      c.read(authProvider.notifier).updateActivity();

      expect(c.read(developerSessionProvider).isActive, isTrue);
      expect(c.read(developerSessionProvider).userId, 1);
    });

    test('ProviderContainer جديد (إعادة تشغيل) = مقفل ولو كان السابق مفتوحاً',
        () {
      final first = newContainer();
      first.read(authProvider.notifier).login(_user(1));
      first.read(developerSessionProvider.notifier).unlock();
      expect(first.read(developerSessionProvider).isActive, isTrue);

      final second = newContainer();
      second.read(authProvider.notifier).login(_user(1));
      expect(second.read(developerSessionProvider).isActive, isFalse);
    });

    test('لا شيء يُحفَظ في SharedPreferences عند الفتح', () async {
      final c = newContainer();
      c.read(authProvider.notifier).login(_user(1));
      c.read(developerSessionProvider.notifier).unlock();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys(), isEmpty);
    });
  });

  group('ساكن', () {
    test('ملف الجلسة بلا أي تخزين دائم ولا static متغيّر', () {
      final src = File('lib/core/config/developer_session.dart')
          .readAsLinesSync()
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');
      for (final banned in [
        'SharedPreferences',
        'secure_storage',
        'SecureStorage',
        'settingsRepository',
        'dart:io',
      ]) {
        expect(src.contains(banned), isFalse, reason: banned);
      }
      expect(RegExp(r'static\s+(?!const)(?!final)\w').hasMatch(src), isFalse,
          reason: 'لا حالة static متغيّرة');
    });

    test('جلسة المطوّر تستمع لـauthProvider وتمسح عند الخروج/تبدّل المعرّف', () {
      final src = File('lib/core/config/developer_session.dart')
          .readAsStringSync();
      expect(src.contains('ref.listen<AuthState>(authProvider'), isTrue);
      expect(src.contains('nextId != s.userId'), isTrue);
    });
  });

  group('البوابة', () {
    testWidgets('بعد logout تُظهر البوابة حقل كلمة المرور بدل المحتوى',
        (tester) async {
      final c = ProviderContainer(overrides: [
        developerAuthServiceProvider.overrideWithValue(_FakeDevAuth()),
      ]);
      addTearDown(c.dispose);
      c.read(authProvider);
      c.read(authProvider.notifier).login(_user(1));

      await tester.pumpWidget(UncontrolledProviderScope(
        container: c,
        child: const MaterialApp(
          home: Scaffold(
            body: DeveloperPasswordGate(child: Text('INSIDE-DEV-TOOLS')),
          ),
        ),
      ));
      expect(find.text('INSIDE-DEV-TOOLS'), findsNothing);
      expect(find.byType(TextField), findsWidgets);

      // فتح
      c.read(developerSessionProvider.notifier).unlock();
      await tester.pump();
      expect(find.text('INSIDE-DEV-TOOLS'), findsOneWidget);

      // خروج ثم عودة ⇒ تُطلب من جديد
      c.read(authProvider.notifier).logout();
      await tester.pump();
      c.read(authProvider.notifier).login(_user(1));
      await tester.pump();
      expect(find.text('INSIDE-DEV-TOOLS'), findsNothing);
      expect(find.byType(TextField), findsWidgets);
    });
  });
}
