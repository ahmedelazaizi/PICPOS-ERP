// عميل HTTP للمتصفّح: BrowserClient (XHR/fetch). التحقق من الشهادة يتولّاه
// المتصفّح نفسه، فلا تثبيتَ بصمة هنا. يُختار شرطياً من tls_trust.dart.
import 'package:http/browser_client.dart';
import 'package:http/http.dart' as http;

http.Client createPlatformHttpClient(
  bool Function(List<int> der, String host, int port) accept, {
  Duration? connectionTimeout,
}) =>
    BrowserClient();
