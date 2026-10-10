// عنوان العميل الفعلي لطلب shelf (بند الأمن 1/د).
//
// القاعدة: **عنوان الاتصال الفعلي** (`shelf.io.connection_info`) هو المرجع.
// ترويسات `X-Forwarded-For` / `X-Real-IP` / `Host` يتحكّم بها العميل، فلا
// تُصدَّق إلا إن كان الاتصال نفسه قادماً من وكيلٍ موثوقٍ مضبوطٍ صراحةً في
// [ClientAddress.trustedProxies] (الافتراضي فارغ = لا وكيل موثوق).

import 'dart:io' show HttpConnectionInfo;

import 'package:shelf/shelf.dart';

class ClientAddress {
  ClientAddress._();

  /// عناوين الوكلاء العكسيين الموثوقين (عنوان الاتصال المباشر بالخادم).
  static Set<String> _trustedProxies = <String>{};

  static Set<String> get trustedProxies => Set.unmodifiable(_trustedProxies);

  static void configureTrustedProxies(Iterable<String> addresses) {
    _trustedProxies = {
      for (final a in addresses)
        if (a.trim().isNotEmpty) a.trim().toLowerCase(),
    };
  }

  /// عنوان الاتصال المباشر، أو `unknown` إن غابت معلومات الاتصال.
  static String remoteOf(Request request) =>
      (request.context['shelf.io.connection_info'] as HttpConnectionInfo?)
          ?.remoteAddress
          .address ??
      'unknown';

  /// العنوان الذي يُنسَب إليه الطلب (للمحدِّد والسجلات).
  static String of(Request request) {
    final remote = remoteOf(request);
    if (!_trustedProxies.contains(remote.toLowerCase())) return remote;
    // الاتصال من وكيل موثوق: نأخذ أقرب عنوانٍ غير موثوقٍ من يمين XFF (ما
    // أضافه الوكيل لا ما كتبه العميل)، ثم X-Real-IP.
    final xff = request.headers['x-forwarded-for'];
    if (xff != null && xff.isNotEmpty) {
      final hops = xff.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty);
      for (final hop in hops.toList().reversed) {
        if (!_trustedProxies.contains(hop.toLowerCase())) return hop;
      }
    }
    final realIp = request.headers['x-real-ip']?.trim();
    if (realIp != null && realIp.isNotEmpty) return realIp;
    return remote;
  }
}
