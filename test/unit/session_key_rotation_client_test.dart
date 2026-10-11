// E-02 T5: العميل يُبطل رموز الجلسات المخزّنة عند تغيّر sessionKeyId.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/services/api/session_key_watch.dart';

void main() {
  test('الأسلاك: _probeHealth يغذّي SessionKeyWatch ويستدعي invalidateAllSessionTokens',
      () {
    final ns = File('lib/services/network_service.dart').readAsStringSync();
    expect(ns, contains("_sessionKeyWatch.observe(data['sessionKeyId']"));
    expect(ns, contains('ServerProxy.instance.invalidateAllSessionTokens'));
    final proxy = File('lib/services/server_proxy.dart').readAsStringSync();
    expect(proxy, contains('void invalidateAllSessionTokens()'));
    // الإثباتات تبقى ليُعاد السكّ: الدالة لا تلمس _sessionProofs.
    final body = proxy.substring(proxy.indexOf('void invalidateAllSessionTokens()'));
    final fn = body.substring(0, body.indexOf('}'));
    expect(fn.contains('_sessionProofs'), isFalse);
  });

  test('دورة تدوير كاملة: تغيّر المعرّف في فحص الدورة التالية يُبطل مرة واحدة', () {
    final watch = SessionKeyWatch();
    final cache = <int, String>{1: 'tok'};
    void invalidate() => cache.clear();

    watch.observe('11111111', invalidate); // أول فحص
    expect(cache, isNotEmpty);
    watch.observe('11111111', invalidate); // فحص دوري بلا تغيّر
    expect(cache, isNotEmpty);
    watch.observe('22222222', invalidate); // تدوير على الخادم
    expect(cache, isEmpty);
  });
}
