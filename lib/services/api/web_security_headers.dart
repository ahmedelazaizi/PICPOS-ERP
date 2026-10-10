// رؤوس أمان لصفحات HTML والملفات الثابتة التي يقدّمها المضيف (بند الأمن 1/و).
//
// * [common]: X-Frame-Options / Referrer-Policy / Permissions-Policy — تُطبَّق
//   دائماً (لا تؤثّر على عمل Flutter web).
// * [flutterWebCsp]: سياسة تطبيق Flutter web. **Report-Only عمداً**: لم يُتحقَّق
//   منها في متصفّح فعلي مع بناء Flutter web (CanvasKit قد يُجلب من
//   www.gstatic.com، والمحمِّل يستعمل سكربتاً مضمَّناً وworkers من blob:)،
//   فتفرضها لاحقاً بتغيير [flutterWebCspHeaderName] بعد اختبارها.
// * [inlinePageCsp]: صفحات /menu و/cfd (سكربت وأنماط مضمَّنة، نفس الأصل فقط،
//   بلا موارد خارجية) — مفروضة.

class WebSecurityHeaders {
  WebSecurityHeaders._();

  static const Map<String, String> common = {
    'x-frame-options': 'DENY',
    'referrer-policy': 'no-referrer',
    'permissions-policy':
        'camera=(), microphone=(), geolocation=(), payment=(), usb=()',
  };

  /// اسم الرأس: Report-Only حتى يُثبَت عدم كسر تطبيق Flutter web.
  static const String flutterWebCspHeaderName =
      'content-security-policy-report-only';

  static const String flutterWebCsp = "default-src 'self'; "
      "script-src 'self' 'unsafe-inline' 'wasm-unsafe-eval' "
      'https://www.gstatic.com; '
      "style-src 'self' 'unsafe-inline' https://fonts.googleapis.com; "
      "img-src 'self' data: blob:; "
      "font-src 'self' data: https://fonts.gstatic.com; "
      "connect-src 'self' ws: wss: https://www.gstatic.com "
      'https://fonts.gstatic.com; '
      "worker-src 'self' blob:; "
      "object-src 'none'; base-uri 'self'; frame-ancestors 'none'";

  static const String inlinePageCsp = "default-src 'self'; "
      "script-src 'self' 'unsafe-inline'; "
      "style-src 'self' 'unsafe-inline'; "
      "img-src 'self' data:; connect-src 'self'; "
      "object-src 'none'; base-uri 'none'; frame-ancestors 'none'";

  /// رؤوس الملفات الثابتة وصفحة Flutter web.
  static Map<String, String> forFlutterWeb() => {
        ...common,
        flutterWebCspHeaderName: flutterWebCsp,
      };

  /// رؤوس صفحات /menu و/cfd.
  static Map<String, String> forInlinePage() => {
        ...common,
        'content-security-policy': inlinePageCsp,
      };
}
