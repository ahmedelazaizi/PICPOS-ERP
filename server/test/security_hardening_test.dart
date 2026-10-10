@Tags(['postgres'])
library;

import 'dart:async';
import 'dart:convert';

import 'package:picpos_cloud/picpos_cloud.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import 'support/harness.dart';

/// S-9 body limit, S-1 employee deactivation, S-5 admin key, S-12 mock log.
void main() {
  late Harness h;
  setUp(() async => h = await Harness.start());
  tearDown(() async => h.stop());

  Future<Response> send(String path, Stream<List<int>> body, {Map<String, String> headers = const {}}) =>
      Future.sync(() => h.services.app.handler(Request('POST', Uri.parse('http://localhost$path'),
          body: body, headers: headers)));

  group('S-9 request body limit', () {
    for (final path in ['/mobile/pair', '/manage/pair']) {
      test('$path: oversized Content-Length -> 413 without reading the body', () async {
        var listened = false;
        final body = Stream<List<int>>.multi((c) {
          listened = true;
          c.close();
        });
        final res = await send(path, body, headers: {'content-length': '${2 * 1024 * 1024}'});
        expect(res.statusCode, 413);
        expect(jsonDecode(await res.readAsString()), {'error': 'payload_too_large'});
        expect(listened, isFalse, reason: 'must reject before touching the stream');
      });

      test('$path: chunked body (no Content-Length) is cut at the cap with bounded reads', () async {
        var pulled = 0;
        final chunk = List<int>.filled(64 * 1024, 0x61);
        Stream<List<int>> endless() async* {
          while (pulled < 100000) {
            pulled++;
            yield chunk;
          }
        }

        final res = await send(path, endless());
        expect(res.statusCode, 413);
        expect(jsonDecode(await res.readAsString()), {'error': 'payload_too_large'});
        // 1 MiB cap / 64 KiB chunks = 16 chunks allowed; the 17th trips it.
        expect(pulled, lessThanOrEqualTo(20));
      });
    }

    test('413 happens before the pairing rate limiter is touched', () async {
      for (var i = 0; i < 8; i++) {
        final res = await send('/mobile/pair', const Stream.empty(), headers: {'content-length': '${5 * 1024 * 1024}'});
        expect(res.statusCode, 413);
      }
      final (st, b) = await h.call('POST', '/mobile/pair', body: {'code': 'ABCDEFGH', 'deviceId': 'd'});
      expect((st, b['error']), (401, 'invalid_code')); // still not rate limited (limit is 5 real attempts)
    });

    test('bulk push path allows > 1 MiB (fails auth, not size) but not > 10 MiB', () async {
      final big = utf8.encode(jsonEncode({'documents': [], 'pad': 'x' * (2 * 1024 * 1024)}));
      final ok = await send('/mobile/sync/push', Stream.value(big), headers: {'content-length': '${big.length}'});
      expect(ok.statusCode, 401); // passed the size gate, stopped at authentication
      final res = await send('/mobile/sync/push', const Stream.empty(),
          headers: {'content-length': '${11 * 1024 * 1024}'});
      expect(res.statusCode, 413);
    });

    test('normal small JSON still works', () async {
      final (st, b) = await h.call('POST', '/mobile/pair', body: {'code': 'ABCDEFGH', 'deviceId': 'x'});
      expect((st, b['error']), (401, 'invalid_code'));
    });
  });

  group('S-1 employee deactivation kills live sessions', () {
    test('active session works, then is_active=false -> 401 employee_inactive on every route', () async {
      final rep = await h.repDevice(Demo.rep1Gid, Demo.rep1Pin);
      final (s1, _) = await h.call('GET', '/mobile/bootstrap', headers: rep.headers);
      expect(s1, 200);

      await h.db.query('UPDATE employees SET is_active=false WHERE global_id=@g', {'g': Demo.rep1Gid});

      for (final (m, p) in [
        ('GET', '/mobile/bootstrap'),
        ('GET', '/mobile/sync/pull'),
        ('POST', '/mobile/sync/push'),
        ('POST', '/mobile/token/rotate'),
      ]) {
        final (st, b) = await h.call(m, p, headers: rep.headers, body: m == 'POST' ? {'documents': []} : null);
        expect((st, b['error']), (401, 'employee_inactive'), reason: '$m $p');
      }

      // Re-enabling restores access with the same session (no stale cache).
      await h.db.query('UPDATE employees SET is_active=true WHERE global_id=@g', {'g': Demo.rep1Gid});
      final (s2, _) = await h.call('GET', '/mobile/bootstrap', headers: rep.headers);
      expect(s2, 200);
    });
  });

  group('S-5 ADMIN_KEY', () {
    test('config: short key rejected unless ALLOW_WEAK_ADMIN_KEY=1; empty and >= 24 ok', () {
      expect(CloudConfig({'ADMIN_KEY': 'short-key'}).adminKeyProblem, contains('at least 24'));
      expect(CloudConfig({'ADMIN_KEY': 'x' * 23}).adminKeyProblem, isNotNull);
      expect(CloudConfig({'ADMIN_KEY': 'x' * 24}).adminKeyProblem, isNull);
      expect(CloudConfig({}).adminKeyProblem, isNull);
      expect(CloudConfig({'ADMIN_KEY': 'short-key', 'ALLOW_WEAK_ADMIN_KEY': '1'}).adminKeyProblem, isNull);
      expect(CloudConfig({'ADMIN_KEY': 'short-key', 'ALLOW_WEAK_ADMIN_KEY': 'true'}).adminKeyProblem, isNotNull);
    });

    test('10 failed guesses per address then 429; successes do not count', () async {
      for (var i = 0; i < 5; i++) {
        final (st, _) = await h.call('GET', '/admin/whatsapp/outbox', headers: {'x-admin-key': Harness.adminKey});
        expect(st, 200);
      }
      for (var i = 0; i < 10; i++) {
        final (st, b) = await h.call('GET', '/admin/whatsapp/outbox', headers: {'x-admin-key': 'guess-$i'});
        expect((st, b['error']), (401, 'admin_key_required'));
      }
      final (st, b) = await h.call('GET', '/admin/whatsapp/outbox', headers: {'x-admin-key': 'guess-x'});
      expect((st, b['error']), (429, 'rate_limited'));
      expect(h.lastHeaders['retry-after'], isNotNull);
    });
  });

  group('S-12 mock WhatsApp provider log', () {
    test('log line carries no phone number and no params', () async {
      final lines = <String>[];
      final p = MockWhatsAppProvider(log: lines.add);
      final r = await p.sendTemplate(
          toPhone: '+962791234567', template: 'invoice', language: 'ar', params: ['Ahmad Khalil', '1,250.500']);
      expect(r.ok, isTrue);
      expect(lines, hasLength(1));
      final all = lines.join('\n');
      expect(all, isNot(contains('962791234567')));
      expect(all, isNot(contains('Ahmad')));
      expect(all, isNot(contains('1,250')));
      expect(all, contains(r.providerMessageId));
      expect(p.sent.single.toPhone, '+962791234567'); // in-memory record for tests is unchanged
    });
  });
}
