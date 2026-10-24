// P1 — النموذجُ الخالص للإعداد الأول: الخطوات، التحقّق، الإبطال، الآلة، الباقات،
// وصيغة المسودّة (‏بلا أسرار).
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/core/config/business_profile.dart';
import 'package:picpos_erp/core/config/feature_policy.dart';
import 'package:picpos_erp/core/config/feature_validator.dart';
import 'package:picpos_erp/core/constants/app_constants.dart' show CurrencyInfo;
import 'package:picpos_erp/domain/models/first_run/first_run_currency.dart';
import 'package:picpos_erp/domain/models/first_run/first_run_draft.dart';
import 'package:picpos_erp/domain/models/first_run/first_run_invalidation.dart';
import 'package:picpos_erp/domain/models/first_run/first_run_machine.dart';
import 'package:picpos_erp/domain/models/first_run/first_run_packs.dart';
import 'package:picpos_erp/domain/models/first_run/first_run_path.dart';
import 'package:picpos_erp/domain/models/first_run/first_run_steps.dart';
import 'package:picpos_erp/domain/models/first_run/first_run_validation.dart';

FirstRunDraft _d({FirstRunPath path = FirstRunPath.standalone}) =>
    FirstRunDraft(draftId: 'd1', path: path);

FirstRunDraft _validCompany(FirstRunDraft d) => d.copyWith(
      companyName: 'شركة الأمل',
      currency: 'JOD',
      branchName: 'الفرع الرئيسي',
      warehouseName: 'المخزن الرئيسي',
    );

const _okSecrets = FirstRunSecrets(
  adminPassword: 'S3cretPass',
  adminPasswordConfirm: 'S3cretPass',
  developerPassword: 'dev1',
  developerPasswordConfirm: 'dev1',
);

void main() {
  group('الخطوات', () {
    test('ست خطوات لكل مسار رئيسي (والمرآة ثلاث)، بلا تفعيل، ونجاح خارج المسار', () {
      for (final p in FirstRunPath.values) {
        final steps = stepsFor(p);
        expect(steps, hasLength(p == FirstRunPath.mirror ? 3 : 6), reason: p.name);
        expect(steps.first, FirstRunStep.mode);
        expect(steps.last, FirstRunStep.review);
        expect(steps, isNot(contains(FirstRunStep.success)));
      }
      final names = FirstRunStep.values.map((s) => s.name).join(',');
      expect(names, isNot(contains('activation')));
      expect(names, isNot(contains('License')));
    });

    test('الفرع: المزامنة الأولى قبل حساب الفرع', () {
      final s = stepsFor(FirstRunPath.branch);
      expect(s.indexOf(FirstRunStep.firstSync),
          lessThan(s.indexOf(FirstRunStep.account)));
    });
  });

  group('العملة (UX-001)', () {
    test('القائمة المعروضة = CurrencyInfo.all بالضبط', () {
      expect(kFirstRunCurrencies, CurrencyInfo.all.map((c) => c.code).toList());
      expect(kFirstRunCurrencies, ['JOD', 'EGP']);
    });

    test('بلا اختيار مسبق ورمز غير معتمد لا يتحول إلى JOD', () {
      final d = _d();
      expect(d.currency, isEmpty);
      expect(selectCurrency(d, 'SAR').currency, isEmpty);
      expect(selectCurrency(d, 'JOD').currency, 'JOD');
    });

    test('JOD ⇒ 16%/JoFotara و EGP ⇒ 14%/ETA ما لم يعدّلها المستخدم', () {
      final jod = selectCurrency(_d(), 'JOD');
      expect(jod.vatRate, 16);
      expect(jod.eInvoice, FirstRunEInvoice.jordan);
      final egp = selectCurrency(jod, 'EGP');
      expect(egp.vatRate, 14);
      expect(egp.eInvoice, FirstRunEInvoice.egypt);
      final touched = selectCurrency(
        _d().copyWith(vatRateTouched: true, vatRate: 5),
        'EGP',
      );
      expect(touched.vatRate, 5);
    });
  });

  group('التحقق (§0.4 مكيَّفة)', () {
    FirstRunIssue? company(FirstRunDraft d) =>
        validateStep(FirstRunStep.company, d, const FirstRunSecrets());

    test('اسم الشركة والعملة والسنة والفرع والمخزن', () {
      expect(company(_d()), FirstRunIssue.companyNameRequired);
      final base = _validCompany(_d());
      expect(company(base), isNull);
      expect(company(base.copyWith(currency: '')), FirstRunIssue.currencyRequired);
      expect(company(base.copyWith(currency: 'SAR')),
          FirstRunIssue.currencyUnsupported);
      expect(company(base.copyWith(fiscalYear: 1999)),
          FirstRunIssue.fiscalYearInvalid);
      expect(company(base.copyWith(branchName: ' ')),
          FirstRunIssue.branchNameRequired);
      expect(company(base.copyWith(warehouseName: '')),
          FirstRunIssue.warehouseRequired);
      expect(company(base.copyWith(branchCode: '12345678901')),
          FirstRunIssue.branchCodeTooLong);
    });

    test('اسم شركة عربي صالح (UX-005)', () {
      expect(company(_validCompany(_d()).copyWith(companyName: 'مؤسسة النور')),
          isNull);
    });

    test('كلمة المرور 8 أحرف (E11) وتطابق وليست admin', () {
      FirstRunIssue? users(FirstRunSecrets s) =>
          validateStep(FirstRunStep.users, _d(), s);
      expect(users(_okSecrets), isNull);
      expect(
        users(_okSecrets.copyWith(
            adminPassword: 'abc1234', adminPasswordConfirm: 'abc1234')),
        FirstRunIssue.adminPasswordShort,
      );
      expect(users(_okSecrets.copyWith(adminPasswordConfirm: 'other-pass')),
          FirstRunIssue.adminPasswordMismatch);
      expect(
        users(_okSecrets.copyWith(
            adminPassword: 'ADMIN', adminPasswordConfirm: 'ADMIN')),
        FirstRunIssue.adminPasswordShort,
      );
      expect(users(_okSecrets.copyWith(developerPassword: 'ab')),
          FirstRunIssue.developerPasswordShort);
      expect(users(_okSecrets.copyWith(developerPasswordConfirm: 'zz99')),
          FirstRunIssue.developerPasswordMismatch);
    });

    test('الطاولات 0..1000 عند باقة تحوي طاولات فقط', () {
      FirstRunIssue? prep(FirstRunDraft d) =>
          validateStep(FirstRunStep.prep, d, const FirstRunSecrets());
      final r = _d().copyWith(pack: FirstRunPack.restaurant);
      expect(prep(r), isNull);
      expect(prep(r.copyWith(tablesCount: '1001')),
          FirstRunIssue.tablesCountInvalid);
      expect(prep(r.copyWith(tablesCount: 'x')), FirstRunIssue.tablesCountInvalid);
      expect(prep(r.copyWith(tablesCount: '0')), isNull);
      expect(prep(_d().copyWith(tablesCount: 'x')), isNull); // pos: لا طاولات
    });

    test('مسار المقر: تكرار رموز الفروع case-insensitive وأسماء دخول فريدة ونطاق', () {
      final hq = _validCompany(_d(path: FirstRunPath.hq));
      FirstRunIssue? comp(FirstRunDraft d) =>
          validateStep(FirstRunStep.company, d, const FirstRunSecrets());
      expect(
        comp(hq.copyWith(branches: const [
          FirstRunBranchRow(code: 'br-1', name: 'أ'),
          FirstRunBranchRow(code: ' BR-1 ', name: 'ب'),
        ])),
        FirstRunIssue.branchCodesDuplicate,
      );
      expect(
        comp(hq.copyWith(branches: const [
          FirstRunBranchRow(code: '', name: 'أ'),
        ])),
        FirstRunIssue.branchRowsIncomplete,
      );
      final withBranch = hq.copyWith(
        branches: const [FirstRunBranchRow(code: 'BR-1', name: 'عمّان')],
      );
      FirstRunIssue? users(List<FirstRunUserRow> rows) => validateStep(
            FirstRunStep.users,
            withBranch.copyWith(hqUsers: rows),
            _okSecrets.copyWith(userPasswords: {0: 'Branch#Pass1'}),
          );
      expect(users([const FirstRunUserRow(name: 'س', username: 'c1', roleId: 2, scope: 'BR-1')]),
          isNull);
      expect(users([const FirstRunUserRow(name: 'س', username: 'ADMIN', roleId: 2)]),
          FirstRunIssue.usernamesDuplicate);
      expect(users([const FirstRunUserRow(name: 'س', username: 'c1', roleId: 2, scope: 'XX')]),
          FirstRunIssue.userScopeInvalid);
      expect(users([const FirstRunUserRow(name: 'س', username: 'c1')]),
          FirstRunIssue.userRowsIncomplete);
    });

    test('الفرع: الربط ثم المزامنة ثم الحساب', () {
      final b = _d(path: FirstRunPath.branch).copyWith(
        endpoint: '192.168.1.5',
        deviceName: 'POS-1',
      );
      FirstRunIssue? v(FirstRunStep s, FirstRunDraft d) =>
          validateStep(s, d, const FirstRunSecrets());
      expect(v(FirstRunStep.link, b), FirstRunIssue.linkNotVerified);
      expect(v(FirstRunStep.link, b.copyWith(port: '0')), FirstRunIssue.portInvalid);
      expect(v(FirstRunStep.link, b.copyWith(endpoint: '')),
          FirstRunIssue.endpointRequired);
      expect(
        v(FirstRunStep.link, b.copyWith(checks: const FirstRunChecks(linked: true))),
        isNull,
      );
      expect(v(FirstRunStep.firstSync, b), FirstRunIssue.firstSyncPending);
      expect(v(FirstRunStep.account, b), FirstRunIssue.accountNotVerified);
    });

    test('validateAll يرجع أول خطوة فاشلة', () {
      final d = _d();
      final f = validateAll(d, _okSecrets)!;
      expect(f.step, FirstRunStep.company);
      final ok = _validCompany(d).copyWith(
        checks: const FirstRunChecks(storageChecked: true),
      );
      expect(validateAll(ok, _okSecrets), isNull);
      final f2 = validateAll(ok, const FirstRunSecrets())!;
      expect(f2.step, FirstRunStep.users);
    });
  });

  group('الآلة', () {
    test('التالي محروس بتحقق الخطوة ولا قفز فوق maxStep', () {
      var d = _d();
      expect(advance(d, _okSecrets).ok, isTrue); // mode
      d = advance(d, _okSecrets).draft;
      expect((d.step, d.maxStep), (1, 1));
      final blocked = advance(d, _okSecrets); // company ناقصة
      expect(blocked.ok, isFalse);
      expect(blocked.draft.step, 1);
      expect(jumpTo(d, 4).step, 1);
      expect(jumpTo(d, 0).step, 0);
      expect(back(d).step, 0);
    });

    test('تبديل المسار يصفّر التحقق والتقدم', () {
      final d = _d().copyWith(
        step: 3,
        maxStep: 3,
        checks: const FirstRunChecks(storageChecked: true, linked: true),
      );
      final b = selectPath(d, FirstRunPath.branch);
      expect((b.step, b.maxStep), (0, 0));
      expect(b.checks.storageChecked, isFalse);
      expect(b.checks.linked, isFalse);
      expect(selectPath(d, FirstRunPath.standalone), same(d));
    });

    test('beginFinish يقفز لأول خطوة فاشلة', () {
      final d = _validCompany(_d()).copyWith(step: 5, maxStep: 5);
      final m = beginFinish(d, _okSecrets); // storage غير مفحوص
      expect(m.ok, isFalse);
      expect(m.draft.currentStep, FirstRunStep.storage);
    });

    test('إبطال الربط ينقل المزامنة والحساب', () {
      final d = _d(path: FirstRunPath.branch).copyWith(
        checks: const FirstRunChecks(
          linked: true,
          firstSyncDone: true,
          accountVerified: true,
          storageChecked: true,
        ),
      );
      final i = invalidate(d, FirstRunField.endpoint);
      expect(i.checks.linked, isFalse);
      expect(i.checks.firstSyncDone, isFalse);
      expect(i.checks.accountVerified, isFalse);
      expect(i.checks.storageChecked, isTrue);
      final r = invalidate(d, FirstRunField.branchRole);
      expect(r.checks.storageChecked, isFalse);
      expect(r.checks.linked, isTrue);
      expect(invalidate(d, FirstRunField.branchUser).checks.accountVerified,
          isFalse);
    });
  });

  group('الباقات', () {
    test('كل باقة تنتج FeaturePolicy صالحة عبر FeatureValidator', () {
      for (final p in FirstRunPack.values) {
        final profile = BusinessProfile.values.byName(p.profileName);
        final result =
            FeatureValidator.validate(FeaturePolicy.fromProfile(profile), {});
        expect(result.rejectedOverrides, isEmpty, reason: p.name);
      }
    });

    test('طريقة الخدمة → طاولات/توصيل', () {
      expect(FirstRunServiceType.tablesOnly.delivery, isFalse);
      expect(FirstRunServiceType.takeawayDelivery.tables, isFalse);
      expect(FirstRunServiceType.all.tables && FirstRunServiceType.all.delivery,
          isTrue);
    });
  });

  group('المسودة JSON', () {
    test('لا أسرار ولا أعلام تحقق في JSON', () {
      final d = _validCompany(_d()).copyWith(
        checks: const FirstRunChecks(storageChecked: true, linked: true),
      );
      final text = jsonEncode(d.toJson());
      for (final bad in ['password', 'Password', 'pairing', 'license', 'secret', 'key']) {
        expect(text.contains(bad), isFalse, reason: bad);
      }
      expect(text.contains('S3cretPass'), isFalse);
      expect(text.contains('storageChecked'), isFalse);
    });

    test('ذهاب وإياب', () {
      final d = _validCompany(_d()).copyWith(
        pack: FirstRunPack.restaurant,
        step: 2,
        maxStep: 3,
        tablesCount: '20',
        serviceType: FirstRunServiceType.tablesOnly,
        eInvoice: FirstRunEInvoice.egypt,
        branches: const [FirstRunBranchRow(code: 'A', name: 'ب')],
        hqUsers: const [FirstRunUserRow(name: 'n', username: 'u', roleId: 3)],
      );
      final back = FirstRunDraft.fromJson(
        jsonDecode(jsonEncode(d.toJson())),
        fallbackId: 'x',
      )!;
      expect(back.toJson(), d.toJson());
      expect(back.checks.storageChecked, isFalse);
    });

    test('إصدار مجهول أو بنية تالفة ⇒ null، وقيم خارج المدى تُقصّ', () {
      expect(FirstRunDraft.fromJson({'version': 99}, fallbackId: 'x'), isNull);
      expect(FirstRunDraft.fromJson('junk', fallbackId: 'x'), isNull);
      final d = FirstRunDraft.fromJson(
        {'version': 1, 'step': 50, 'maxStep': 99, 'currency': 'SAR'},
        fallbackId: 'fb',
      )!;
      expect(d.maxStep, 5);
      expect(d.step, 5);
      expect(d.currency, isEmpty);
      expect(d.draftId, 'fb');
    });

    test('FirstRunSecrets بلا toJson', () {
      expect(const FirstRunSecrets() as Object, isNot(isA<Map>()));
    });
  });

  test('نطاق domain/models/first_run بلا Flutter ولا UralCash', () {
    final dir = Directory('lib/domain/models/first_run');
    var total = 0;
    for (final f in dir.listSync().whereType<File>()) {
      final src = f.readAsStringSync();
      expect(src.contains("package:flutter"), isFalse, reason: f.path);
      expect(src.toLowerCase().contains('uralcash'), isFalse, reason: f.path);
      expect(f.lengthSync(), lessThan(30720), reason: f.path);
      total += f.lengthSync();
    }
    expect(total, greaterThan(0));
  });
}
