// P5/P6 — منطقُ المجال لمساري المقرّ والفرع (والمرآة): التحقق، الإبطال، المسودة بلا
// أسرار، ومحوّل مدخل كاتب الخادم، ومنفّذ الإنهاء المرتبط بخادم.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/core/i18n/tr.dart';
import 'package:picpos_erp/domain/models/first_run/first_run_currency.dart';
import 'package:picpos_erp/domain/models/first_run/first_run_draft.dart';
import 'package:picpos_erp/domain/models/first_run/first_run_invalidation.dart';
import 'package:picpos_erp/domain/models/first_run/first_run_packs.dart';
import 'package:picpos_erp/domain/models/first_run/first_run_path.dart';
import 'package:picpos_erp/domain/models/first_run/first_run_steps.dart';
import 'package:picpos_erp/domain/models/first_run/first_run_validation.dart';
import 'package:picpos_erp/presentation/screens/first_run/first_run_finish_server.dart';
import 'package:picpos_erp/presentation/screens/setup_wizard/setup_finish_runner.dart';

import '../../widget/first_run/first_run_test_kit.dart';

FirstRunDraft _hq() => const FirstRunDraft(draftId: 'h1', path: FirstRunPath.hq)
    .copyWith(
      companyName: 'شركة',
      currency: 'JOD',
      branchName: 'الرئيسي',
      warehouseName: 'المخزن',
      branches: const [FirstRunBranchRow(code: 'AMM', name: 'عمّان')],
    );

const _admin = FirstRunSecrets(
  adminPassword: 'S3cretPass',
  adminPasswordConfirm: 'S3cretPass',
  developerPassword: 'dev1',
  developerPasswordConfirm: 'dev1',
);

FirstRunIssue? _users(FirstRunDraft d, FirstRunSecrets s) =>
    validateStep(FirstRunStep.users, d, s);

void main() {
  setUpAll(() => I18nCatalog.setCatalog(const {}));

  group('المقر — قاعدة PostgreSQL', () {
    FirstRunIssue? storage(FirstRunDraft d) =>
        validateStep(FirstRunStep.storage, d, const FirstRunSecrets());

    test('حقول الاتصال ثم التهيئة الفعلية', () {
      final d = _hq();
      expect(storage(d), FirstRunIssue.serverNotProvisioned);
      expect(storage(d.copyWith(pgHost: ' ')), FirstRunIssue.pgHostRequired);
      expect(storage(d.copyWith(pgPort: '0')), FirstRunIssue.pgPortInvalid);
      expect(storage(d.copyWith(pgPort: '70000')), FirstRunIssue.pgPortInvalid);
      expect(storage(d.copyWith(pgDatabase: '')), FirstRunIssue.pgDatabaseRequired);
      expect(storage(d.copyWith(pgUser: '')), FirstRunIssue.pgUserRequired);
      final ok = d.copyWith(checks: const FirstRunChecks(provisioned: true));
      expect(storage(ok), isNull, reason: 'فحص مجلد SQLite المحلي لا يعني المقر');
    });

    test('تعديل أي حقل PG يبطل التهيئة فقط', () {
      final d = _hq().copyWith(
        checks: const FirstRunChecks(provisioned: true, storageChecked: true),
      );
      final i = invalidate(d.copyWith(pgHost: 'other'), FirstRunField.postgres);
      expect(i.checks.provisioned, isFalse);
      expect(i.checks.storageChecked, isTrue);
    });
  });

  group('المقر — المستخدمون', () {
    FirstRunDraft withUser({String scope = 'AMM', String username = 'c1'}) =>
        _hq().copyWith(hqUsers: [
          FirstRunUserRow(
              name: 'س', username: username, roleId: 2, scope: scope, rowId: 1),
        ]);

    test('كلمة أولية ≥ 8 وليست admin ولا اسم الدخول ولا مكررة', () {
      FirstRunSecrets s(Map<int, String> pw) => _admin.copyWith(userPasswords: pw);
      final d = withUser();
      expect(_users(d, s({})), FirstRunIssue.userPasswordShort);
      expect(_users(d, s({1: 'short'})), FirstRunIssue.userPasswordShort);
      expect(_users(d, s({1: 'c1c1c1c1'})), isNull);
      expect(_users(withUser(username: 'cashier99'), s({1: 'cashier99'})),
          FirstRunIssue.userPasswordWeak);
      expect(_users(d, s({1: 'S3cretPass'})), FirstRunIssue.userPasswordDuplicate,
          reason: 'تساوي كلمة المسؤول');
      expect(_users(d, s({1: 'Branch#Pass1'})), isNull);
      final two = d.copyWith(hqUsers: [
        ...d.hqUsers,
        const FirstRunUserRow(name: 'ص', username: 'c2', roleId: 2, scope: 'HQ', rowId: 2),
      ]);
      expect(_users(two, s({1: 'Same#Pass123', 2: 'Same#Pass123'})),
          FirstRunIssue.userPasswordDuplicate);
    });

    test('مدة الأوفلاين ∈ {1,3,7,14,30} والنطاق ضمن الرموز المعرّفة', () {
      final ok = _admin.copyWith(userPasswords: {1: 'Branch#Pass1'});
      expect(_users(withUser().copyWith(offlineDays: 5), ok),
          FirstRunIssue.offlineDaysInvalid);
      for (final n in kFirstRunOfflineDays) {
        expect(_users(withUser().copyWith(offlineDays: n), ok), isNull);
      }
      expect(_users(withUser(scope: 'XX'), ok), FirstRunIssue.userScopeInvalid);
    });
  });

  group('الفرع والمرآة', () {
    test('المزامنة الأولى لا تكفي دون اختيار الفرع', () {
      final b = const FirstRunDraft(draftId: 'b', path: FirstRunPath.branch)
          .copyWith(checks: const FirstRunChecks(firstSyncDone: true));
      FirstRunIssue? v(FirstRunDraft d) =>
          validateStep(FirstRunStep.firstSync, d, const FirstRunSecrets());
      expect(v(b), FirstRunIssue.branchNotSelected);
      expect(v(b.copyWith(selectedBranchId: 7)), isNull);
      expect(v(const FirstRunDraft(draftId: 'b', path: FirstRunPath.branch)),
          FirstRunIssue.firstSyncPending);
    });

    test('تغيير الفرع المختار يبطل تحقق الحساب فقط', () {
      final d = const FirstRunDraft(draftId: 'b', path: FirstRunPath.branch)
          .copyWith(
        checks: const FirstRunChecks(
            linked: true, firstSyncDone: true, accountVerified: true),
      );
      final i = invalidate(d, FirstRunField.branchSelection);
      expect((i.checks.linked, i.checks.firstSyncDone, i.checks.accountVerified),
          (true, true, false));
    });

    test('المرآة: ثلاث خطوات، مدير بدل اسم الجهاز', () {
      expect(stepsFor(FirstRunPath.mirror),
          [FirstRunStep.mode, FirstRunStep.link, FirstRunStep.review]);
      final m = const FirstRunDraft(draftId: 'm', path: FirstRunPath.mirror)
          .copyWith(endpoint: '10.0.0.1');
      FirstRunIssue? v(FirstRunDraft d) =>
          validateStep(FirstRunStep.link, d, const FirstRunSecrets());
      expect(v(m), FirstRunIssue.mirrorAdminRequired);
      final named = m.copyWith(accountUsername: 'admin');
      expect(v(named), FirstRunIssue.linkNotVerified, reason: 'اسم الجهاز غير مطلوب');
      expect(v(named.copyWith(checks: const FirstRunChecks(linked: true))), isNull);
    });
  });

  group('المسودة بلا أسرار', () {
    test('JSON لا يحوي كلمات المرور ولا رمز الإقران، والحقول الجديدة تُستعاد', () {
      const secrets = FirstRunSecrets(
        pgPassword: 'PG-SECRET-1',
        accountPassword: 'ACC-SECRET-2',
        pairingCode: 'PAIR-CODE-3',
        userPasswords: {1: 'USER-SECRET-4'},
        adminPassword: 'ADM-SECRET-5',
      );
      expect(secrets.pgPassword, isNotEmpty); // تُستعمل في الذاكرة فقط
      final d = _hq().copyWith(
        pgHost: '10.1.1.1',
        pgDatabase: 'erp',
        selectedBranchId: 9,
        selectedBranchName: 'عمّان',
        selectedBranchCode: 'AMM',
        accountUsername: 'cash.amm',
        hqUsers: const [
          FirstRunUserRow(
              name: 'س', username: 'c1', roleId: 2, roleName: 'كاشير', rowId: 4, forceChange: false),
        ],
      );
      final json = jsonEncode(d.toJson());
      for (final s in [
        'PG-SECRET-1', 'ACC-SECRET-2', 'PAIR-CODE-3', 'USER-SECRET-4', 'ADM-SECRET-5'
      ]) {
        expect(json.contains(s), isFalse, reason: s);
      }
      final back = FirstRunDraft.fromJson(jsonDecode(json), fallbackId: 'x')!;
      expect(back.pgHost, '10.1.1.1');
      expect(back.pgDatabase, 'erp');
      expect(back.selectedBranchId, 9);
      expect(back.selectedBranchCode, 'AMM');
      expect(back.accountUsername, 'cash.amm');
      expect(back.hqUsers.single.rowId, 4);
      expect(back.hqUsers.single.roleName, 'كاشير');
      expect(back.hqUsers.single.forceChange, isFalse);
      expect(back.checks.provisioned, isFalse, reason: 'الأعلام لا تُسلسَل');
    });
  });

  group('محوّل مدخل كاتب الخادم', () {
    test('مطاعم ⇒ قسم وطاولات وعلامات؛ نقطة بيع ⇒ لا شيء', () {
      final r = _hq().copyWith(
        pack: FirstRunPack.restaurant,
        tablesCount: '3',
        serviceType: FirstRunServiceType.all,
        vatRate: 16,
        eInvoice: FirstRunEInvoice.jordan,
      );
      final i = buildServerSetupInput(r, _admin);
      expect(i.businessProfile, 'restaurant');
      expect(i.tableNames, hasLength(3));
      expect(i.tablesEnabled, isTrue);
      expect(i.deliveryEnabled, isTrue);
      expect(i.eInvoice, 'jordan');
      final u = buildServerSetupInput(
        _hq().copyWith(hqUsers: const [
          FirstRunUserRow(name: 'س', username: 'u', roleId: 2, rowId: 1, forceChange: false),
          FirstRunUserRow(name: 'ص', username: 'v', roleId: 2, rowId: 2),
        ]),
        _admin.copyWith(userPasswords: {1: 'Pass#One123', 2: 'Pass#Two456'}),
      );
      expect(u.users.map((x) => x.forcePasswordChange), [false, true]);
      expect(i.branches.single.code, 'AMM');
      final p = buildServerSetupInput(_hq().copyWith(pack: FirstRunPack.pos), _admin);
      expect(p.tableNames, isEmpty);
      expect(p.tablesEnabled, isNull);
    });
  });

  group('منفّذ الإنهاء المرتبط بخادم', () {
    test('فشل اعتماد النمط يوقف بلا setup_completed، والفرع بلا فرع مختار يفشل', () async {
      final events = <String>[];
      final prov = FakeProvisioning(events);
      final writer = FakeServerWriter(events);
      final fin = serverBoundFinisher(writer: writer, provisioning: prov);
      final p = RecordingPersistence()..timeline = events;
      p.deploymentFailure = 'تعذّر اعتماد النمط';

      final r = await fin(_hq(), _admin, p);
      expect(r.ok, isFalse);
      expect(r.failedStage, SetupRunStage.mode);
      expect(r.error, 'تعذّر اعتماد النمط');
      expect(events, contains('server-write'));
      expect(events, isNot(contains('save:setup_completed')));

      final noBranch = await fin(
        const FirstRunDraft(draftId: 'b', path: FirstRunPath.branch),
        const FirstRunSecrets(),
        RecordingPersistence(),
      );
      expect(noBranch.ok, isFalse);
    });

    test('فشل كاتب الخادم ⇒ مرحلة serverData وبلا تسليح', () async {
      final events = <String>[];
      final prov = FakeProvisioning(events);
      final writer = FakeServerWriter(events)..failWith = StateError('boom');
      final fin = serverBoundFinisher(writer: writer, provisioning: prov);
      final r = await fin(_hq(), _admin, RecordingPersistence());
      expect(r.ok, isFalse);
      expect(r.failedStage, SetupRunStage.serverData);
      expect(prov.armed, 0);
    });
  });
}