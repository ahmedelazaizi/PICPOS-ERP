// P0 (خطة إعادة تصميم الإعداد الأول): الخدمةُ المستخرجةُ من step_provisioning
// تُرجع نتيجةً وتبثّ تقدّماً — ولا ترسم ولا تنهي العملية.
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/services/setup/server_provisioning_service.dart';

PostgresConfig _cfg() => const PostgresConfig(
      host: 'localhost',
      port: 5432,
      database: 'db',
      username: 'u',
      password: 'p',
    );

void main() {
  group('ServerProvisioningService', () {
    test('فشل الاتصال يُرجع رسالة ولا يفتح القاعدة', () async {
      var opened = 0;
      final events = <String>[];
      final svc = ServerProvisioningService(
        testConnection: (_) async => 'refused',
        openDatabase: (_) {
          opened++;
          throw StateError('must not open');
        },
      );
      final out = await svc.provision(
        _cfg(),
        onStep: (i, s, d) => events.add('$i:${s.name}'),
      );
      expect(out.ok, isFalse);
      expect(out.error, contains('refused'));
      expect(opened, 0);
      expect(events, ['0:running', '0:failed']);
    });

    test('استثناءٌ من اختبار الاتصال يتحوّل إلى نصّ', () async {
      final svc = ServerProvisioningService(
        testConnection: (_) async => throw Exception('socket'),
      );
      final err = await svc.testConnection(_cfg());
      expect(err, contains('socket'));
    });

    test('نجاح الاختبار ثم فشل فتح القاعدة يُرجع فشلاً بعد خطوة 0 ok', () async {
      final events = <String>[];
      final svc = ServerProvisioningService(
        testConnection: (_) async => null,
        openDatabase: (_) => throw StateError('no driver'),
      );
      final out = await svc.provision(
        _cfg(),
        onStep: (i, s, d) => events.add('$i:${s.name}'),
      );
      expect(out.ok, isFalse);
      expect(out.error, contains('no driver'));
      expect(events, ['0:running', '0:ok']);
    });

    test('ProvisionStatus يطابق ترتيب حالات صفّ الشاشة', () {
      // الشاشة تحوّل بـ`_ProvisionState.values[status.index]`.
      expect(ProvisionStatus.values.map((s) => s.name),
          ['pending', 'running', 'ok', 'failed']);
    });
  });
}
