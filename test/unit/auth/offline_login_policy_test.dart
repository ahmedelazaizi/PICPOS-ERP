// P7 + حالة القبول 5 (فرع مهيأ عند الانقطاع): مدة السماح من آخر تحقق ناجح بجلسة
// خادم، رفض بعد انقضائها، رفض إرجاع الساعة، تجديد بالاتصال، وقرار «لم يُتحقق قط»
// منفصل. ويُحرس أن مسارات الدخول الثلاثة في مستودع المصادقة تمرّ بالسياسة.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/services/auth/offline_login_policy.dart';

class _MemStore implements OfflineLoginStore {
  String? json;
  bool failing = false;
  @override
  Future<String?> read() async {
    if (failing) throw StateError('no secure storage');
    return json;
  }

  @override
  Future<void> write(String j) async {
    if (failing) throw StateError('no secure storage');
    json = j;
  }
}

void main() {
  late _MemStore store;
  late DateTime now;
  int? grace;

  OfflineLoginPolicy make() => OfflineLoginPolicy(
        store: store,
        readGraceDays: () async => grace,
        clock: () => now,
      );

  setUp(() {
    store = _MemStore();
    now = DateTime.utc(2026, 10, 1, 9);
    grace = 7;
  });

  test('داخل المدة ⇒ مسموح، وبعدها ⇒ منتهٍ (7 أيام)', () async {
    final p = make();
    await p.recordVerified(12);
    now = now.add(const Duration(days: 6, hours: 23));
    expect((await p.check(12)).decision, OfflineLoginDecision.allowed);
    now = now.add(const Duration(hours: 2));
    final v = await p.check(12);
    expect(v.decision, OfflineLoginDecision.expired);
    expect(v.graceDays, 7);
  });

  test('تجديد التحقق بجلسة خادم يبدأ مدة جديدة', () async {
    final p = make();
    await p.recordVerified(12);
    now = now.add(const Duration(days: 8));
    expect((await p.check(12)).decision, OfflineLoginDecision.expired);
    await p.recordVerified(12);
    now = now.add(const Duration(days: 3));
    expect((await p.check(12)).allowed, isTrue);
  });

  test('مدة السماح قابلة للتعديل من الرئيسي ولها حدّ أعلى وافتراضي', () async {
    final p = make();
    await p.recordVerified(5);
    grace = 1;
    now = now.add(const Duration(days: 2));
    expect((await p.check(5)).decision, OfflineLoginDecision.expired);
    grace = null; // غير مضبوط ⇒ 7
    expect((await p.check(5)).graceDays, 7);
    grace = 9999;
    expect((await p.check(5)).graceDays, OfflineLoginPolicy.maxGraceDays);
  });

  test('إرجاع ساعة الجهاز يُرفض بعد رؤية وقت أحدث (تسامح 10 دقائق)', () async {
    final p = make();
    await p.recordVerified(12);
    now = now.add(const Duration(days: 5));
    expect((await p.check(12)).allowed, isTrue); // يسجّل أعلى وقت شوهد
    now = now.subtract(const Duration(days: 4)); // رجوع للخلف لتمديد المدة
    expect((await p.check(12)).decision, OfflineLoginDecision.clockRolledBack);
    now = now.add(const Duration(days: 4)).subtract(const Duration(minutes: 5));
    expect((await p.check(12)).allowed, isTrue, reason: 'ضمن التسامح');
  });

  test('مستخدم لم يُتحقق منه قط ⇒ قرار منفصل، ولا يُمنح طابع المستخدم الآخر', () async {
    final p = make();
    await p.recordVerified(12);
    expect((await p.check(99)).decision, OfflineLoginDecision.neverVerified);
  });

  test('تخزين تالف أو معطّل لا يُسقط التحقق (قرار الاستدعاء)', () async {
    store.json = '{not json';
    expect((await make().check(1)).decision, OfflineLoginDecision.neverVerified);
    store.failing = true;
    await expectLater(make().recordVerified(1), throwsA(anything));
  });

  test('مسارات الدخول الثلاثة في مستودع المصادقة تمرّ بالسياسة', () {
    final src = File('lib/data/repositories/auth_repository_impl.dart')
        .readAsStringSync();
    expect('_enforceOfflineLoginPolicy(result)'.allMatches(src).length, 3);
    expect(src, contains('hasSessionToken(id)'));
    expect(src, contains('recordVerified(id)'));
    // مفتاح المدة هو المزامَن من الرئيسي.
    expect(src, contains("'offline_login_grace_days'"));
  });
}