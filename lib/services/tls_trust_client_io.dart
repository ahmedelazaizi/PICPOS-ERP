// عميل HTTP لمنصّات dart:io (سطح المكتب/الجوّال/اختبارات VM): IOClient مضبوطٌ
// على تثبيت البصمة. يُختار شرطياً من tls_trust.dart.
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart' as http_io;

/// [accept] يقرّر قبول شهادة بحسب بصمتها (DER) والمضيف/المنفذ.
http.Client createPlatformHttpClient(
  bool Function(List<int> der, String host, int port) accept, {
  Duration? connectionTimeout,
}) {
  final client = HttpClient();
  if (connectionTimeout != null) client.connectionTimeout = connectionTimeout;
  client.badCertificateCallback =
      (X509Certificate cert, String host, int port) =>
          accept(cert.der, host, port);
  return http_io.IOClient(client);
}
