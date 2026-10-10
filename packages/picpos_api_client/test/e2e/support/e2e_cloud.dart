// مساعد E2E (dart:io فقط، بلا اعتماديات) يشغّل `e2e_server.dart` كعملية
// فرعية ويتحدث معه عبر HTTP حقيقي.
//
// نسخة مطابقة منه موجودة في:
//   packages/picpos_api_client/test/e2e/support/e2e_cloud.dart
//   mobile/test/e2e/support/e2e_cloud.dart
//   mobile_admin/test/e2e/support/e2e_cloud.dart
//   test/e2e/support/e2e_cloud.dart
// (الحزم لا تعتمد بعضها على اختبارات بعض). عدّل هنا ثم انسخ بـ `tool/run_e2e.ps1 -SyncHelpers`.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

class E2eResponse {
  E2eResponse(this.status, this.json, this.headers);
  final int status;
  final Map<String, dynamic> json;
  final Map<String, String> headers;
  String? get error => json['error'] as String?;
  @override
  String toString() => 'E2eResponse($status, $json)';
}

class E2eCloud {
  E2eCloud._(this._proc, this.url, this.adminKey, this.companyA, this.companyB, this._stderr);

  final Process _proc;
  final String url;
  final String adminKey;
  final String companyA;
  final String companyB;
  final StringBuffer _stderr;
  final HttpClient _http = HttpClient()..connectionTimeout = const Duration(seconds: 10);

  static const demoRep1 = '00000000-0000-4000-8000-0000000000a1';
  static const demoRep2 = '00000000-0000-4000-8000-0000000000a2';
  static const rep1Pin = '1234';
  static const rep2Pin = '5678';
  static const cust1 = '00000000-0000-4000-8000-0000000000c1';
  static const cust2 = '00000000-0000-4000-8000-0000000000c2';
  static const cust3 = '00000000-0000-4000-8000-0000000000c3';
  static const water = '00000000-0000-4000-8000-0000000000b1';
  static const bread = '00000000-0000-4000-8000-0000000000b2';

  /// يشغّل الخادم ويعيد بعد أن يطبع E2E_READY.
  /// [pairLimit]: يرفع حدّ الاقتران لكل نسخة خادم (انظر e2e_server.dart).
  static Future<E2eCloud> start({int? pairLimit}) async {
    final serverDir = _findServerDir();
    final proc = await Process.start(
      Platform.environment['E2E_DART'] ?? 'dart',
      ['run', 'test/e2e/support/e2e_server.dart', if (pairLimit != null) '--pair-limit=$pairLimit'],
      workingDirectory: serverDir,
      runInShell: Platform.isWindows,
    );
    final stderrBuf = StringBuffer();
    proc.stderr.transform(utf8.decoder).listen(stderrBuf.write);
    final ready = Completer<Map<String, dynamic>>();
    final out = StringBuffer();
    proc.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
      out.writeln(line);
      if (line.startsWith('E2E_READY ') && !ready.isCompleted) {
        ready.complete((jsonDecode(line.substring(10)) as Map).cast<String, dynamic>());
      }
    });
    unawaited(proc.exitCode.then((code) {
      if (!ready.isCompleted) ready.completeError(StateError('e2e server exited $code\n$out\n$stderrBuf'));
    }));
    final cfg = await ready.future.timeout(const Duration(seconds: 120), onTimeout: () {
      proc.kill();
      throw StateError('e2e server did not start in 120 s\n$out\n$stderrBuf');
    });
    return E2eCloud._(proc, cfg['url'] as String, cfg['adminKey'] as String, cfg['companyA'] as String,
        cfg['companyB'] as String, stderrBuf);
  }

  static String _findServerDir() {
    var d = Directory.current.absolute;
    for (var i = 0; i < 6; i++) {
      final f = File('${d.path}${Platform.pathSeparator}server${Platform.pathSeparator}test${Platform.pathSeparator}e2e'
          '${Platform.pathSeparator}support${Platform.pathSeparator}e2e_server.dart');
      if (f.existsSync()) return '${d.path}${Platform.pathSeparator}server';
      d = d.parent;
    }
    throw StateError('server/test/e2e/support/e2e_server.dart not found above ${Directory.current.path}');
  }

  /// يُسقط مخطط قاعدة البيانات وينهي العملية.
  Future<void> stop() async {
    _http.close(force: true);
    try {
      _proc.stdin.writeln('stop');
      await _proc.stdin.close();
    } on Object {
      // already gone
    }
    await _proc.exitCode.timeout(const Duration(seconds: 30), onTimeout: () {
      _proc.kill();
      return -1;
    });
  }

  String get serverStderr => _stderr.toString();

  Future<E2eResponse> call(String method, String path,
      {Object? body, Map<String, String> headers = const {}}) async {
    final req = await _http.openUrl(method, Uri.parse('$url$path'));
    req.headers.contentType = ContentType.json;
    headers.forEach(req.headers.set);
    if (body != null) req.write(jsonEncode(body));
    final res = await req.close();
    final text = await res.transform(utf8.decoder).join();
    final h = <String, String>{};
    res.headers.forEach((k, v) => h[k] = v.join(','));
    final json = text.isEmpty ? <String, dynamic>{} : (jsonDecode(text) as Map).cast<String, dynamic>();
    return E2eResponse(res.statusCode, json, h);
  }

  Map<String, String> get adminHeaders => {'x-admin-key': adminKey};

  /// بيانات اعتماد ربط المكتب (desktop link) لشركة.
  Future<Map<String, String>> desktopLink(String companyGid, {String name = 'HQ'}) async {
    final r = await call('POST', '/admin/desktop-links',
        headers: adminHeaders, body: {'companyGlobalId': companyGid, 'name': name});
    if (r.status != 201) throw StateError('desktop link: $r');
    return {'authorization': 'Bearer ${r.json['linkSecret']}', 'x-desktop-link': r.json['linkId'] as String};
  }

  /// رمز اقتران مندوب (عبر مفتاح الإدارة).
  Future<String> repPairingCode(String employeeGid, {String? company}) async {
    final r = await call('POST', '/admin/pairing-codes',
        headers: adminHeaders, body: {'companyGlobalId': company ?? companyA, 'employeeGlobalId': employeeGid});
    if (r.status != 201) throw StateError('pairing code: $r');
    return r.json['code'] as String;
  }
}
