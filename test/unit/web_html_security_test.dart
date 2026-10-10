// بند الأمن 1/هـ و/و — قوالب HTML بلا إدراج خام، ورؤوس الأمان للملفات الثابتة
// وصفحتي /menu و/cfd.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shelf/shelf.dart';
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/services/api/api_display_handler.dart';
import 'package:ural_erp/services/api/api_html_templates.dart';
import 'package:ural_erp/services/api/web_static_handler.dart';

void main() {
  group('XSS: القوالب لا تُدرج نصّاً خاماً في innerHTML', () {
    final templates = {'menu': menuHtmlTemplate, 'cfd': cfdHtmlTemplate};

    test('كلّ قالب يعرّف esc() ويستعملها للحقول القادمة من قاعدة البيانات', () {
      for (final e in templates.entries) {
        expect(e.value, contains('function esc('), reason: e.key);
      }
      expect(menuHtmlTemplate, contains('esc(c.name)'));
      expect(menuHtmlTemplate, contains('esc(p.name)'));
      expect(menuHtmlTemplate, contains('esc(p.description'));
      expect(cfdHtmlTemplate, contains('esc(i.name)'));
      expect(cfdHtmlTemplate, contains('esc(data.customer)'));
    });

    test('لا يوجد تركيب نصّي خام (+ field) لأيّ حقل نصّي من الخادم', () {
      final raw = RegExp(
        r'\+\s*(c\.name|p\.name|p\.description|i\.name|data\.customer)\b',
      );
      for (final e in templates.entries) {
        expect(raw.hasMatch(e.value), isFalse,
            reason: '${e.key}: ${raw.firstMatch(e.value)?.group(0)}');
      }
      // معرّف التصنيف في onclick رقمٌ مُجبَر لا نصّ.
      expect(menuHtmlTemplate, contains('Number(c.id)'));
    });

    test('esc يرمّز & < > " \' (الدالة في القالب مطابقة لهذا السلوك)', () {
      expect(menuHtmlTemplate,
          contains(r"""/[&<>"']/g"""));
      for (final ch in ['&amp;', '&lt;', '&gt;', '&quot;', '&#39;']) {
        expect(menuHtmlTemplate, contains(ch));
        expect(cfdHtmlTemplate, contains(ch));
      }
    });
  });

  group('رؤوس الأمان', () {
    late Directory dir;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('static_hdr_');
      File('${dir.path}/index.html').writeAsStringSync('<html></html>');
      File('${dir.path}/main.dart.js').writeAsStringSync('//js');
    });

    tearDown(() => dir.deleteSync(recursive: true));

    void expectCommon(Map<String, String> h) {
      expect(h['x-frame-options'], 'DENY');
      expect(h['referrer-policy'], 'no-referrer');
      expect(h['permissions-policy'], contains('camera=()'));
    }

    test('الملفات الثابتة وindex.html: DENY/no-referrer/Permissions + CSP', () async {
      final handler = WebStaticHandler(dir.path);
      for (final path in ['/', '/main.dart.js', '/reports/sales']) {
        final r = await handler.call(
            Request('GET', Uri.parse('http://localhost$path')));
        expect(r.statusCode, 200, reason: path);
        expectCommon(r.headers);
        final csp = r.headers['content-security-policy-report-only'];
        expect(csp, isNotNull, reason: path);
        expect(csp, contains("default-src 'self'"));
        expect(csp, contains("'wasm-unsafe-eval'"));
        expect(csp, contains('connect-src'));
        expect(csp, contains('ws:'));
        expect(r.headers['x-content-type-options'], 'nosniff');
      }
    });

    test('HEAD يحمل الرؤوس أيضاً', () async {
      final r = await WebStaticHandler(dir.path)
          .call(Request('HEAD', Uri.parse('http://localhost/')));
      expectCommon(r.headers);
    });

    test('/menu و/cfd: CSP مفروضة + بقية الرؤوس', () async {
      final db = AppDatabase.forTesting();
      addTearDown(db.close);
      final display = ApiDisplayHandler(db);
      final req = Request('GET', Uri.parse('http://localhost/menu'));
      for (final r in [
        await display.getMenuDisplay(req),
        await display.getCfdDisplay(req),
      ]) {
        expectCommon(r.headers);
        final csp = r.headers['content-security-policy'];
        expect(csp, contains("default-src 'self'"));
        expect(csp, contains("object-src 'none'"));
        expect(r.headers['content-type'], contains('text/html'));
      }
    });
  });
}
