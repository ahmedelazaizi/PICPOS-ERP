import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:picpos_api_client/picpos_api_client.dart' show UrlPolicy;
import 'package:picpos_van/data/cloud_api.dart';

/// M-1: HttpCloudApi vets every URL with UrlPolicy before any request.
void main() {
  DeviceCredentials creds(String base) => DeviceCredentials(baseUrl: base, deviceId: 'd', deviceToken: 't');

  MockClient okClient(List<Uri> seen) => MockClient((http.Request r) async {
        seen.add(r.url);
        return http.Response('{"sessionToken":"s"}', 200);
      });

  test('release policy: http:// is refused before any network call; https works', () async {
    final seen = <Uri>[];
    final api = HttpCloudApi(okClient(seen), UrlPolicy.release);
    for (final bad in ['http://cloud.example.com', 'http://10.0.2.2:18080', 'http://192.168.1.5:18080']) {
      await expectLater(
          api.login(creds(bad), '1234'),
          throwsA(isA<CloudApiException>().having((e) => e.code, 'code', 'url_not_allowed')),
          reason: bad);
      await expectLater(api.pair(bad, 'ABCDEFGH', 'd', 'n'), throwsA(isA<CloudApiException>()), reason: bad);
    }
    expect(seen, isEmpty);
    expect(await api.login(creds('https://cloud.example.com'), '1234'), 's');
    expect(seen.single.scheme, 'https');
  });

  test('development policy: http only to emulator host / loopback / 192.168; other hosts refused', () async {
    final seen = <Uri>[];
    final api = HttpCloudApi(okClient(seen), UrlPolicy.development);
    for (final ok in ['http://10.0.2.2:18080', 'http://127.0.0.1:18080', 'http://localhost:18080', 'http://192.168.1.5:18080']) {
      expect(await api.login(creds(ok), '1234'), 's', reason: ok);
    }
    await expectLater(api.login(creds('http://evil.example.com'), '1234'), throwsA(isA<CloudApiException>()));
    await expectLater(api.login(creds('ftp://10.0.2.2'), '1234'), throwsA(isA<CloudApiException>()));
    expect(seen, hasLength(4));
  });

  test('default policy under flutter test (not release) allows the loopback test stack', () async {
    final seen = <Uri>[];
    final api = HttpCloudApi(okClient(seen));
    expect(await api.login(creds('http://127.0.0.1:18080'), '1234'), 's');
    await expectLater(api.login(creds('http://cloud.example.com'), '1234'), throwsA(isA<CloudApiException>()));
  });
}
