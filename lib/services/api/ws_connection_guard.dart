// حارس اتصالات `/ws` (بند الأمن 5.3).
//
// القرار (موثَّق):
//  * مستهلك `/ws` الشرعي (`WebSocketSyncClient`) عميلٌ أصيل لا يرسل رمزًا ولا
//    `Origin`، ولا يمكن تعديل تطبيقات mobile* من هنا؛ لذا المصادقة **اختيارية
//    لكنها صارمة حين تُقدَّم**: إن وصل `Authorization: Bearer` أو `?token=`
//    وجب أن يكون صحيحًا (جهاز مقترن أو الرمز الحالي)، وإلا 401.
//  * `Origin` (يرسله المتصفح فقط): يُرفض ما ليس نفس الأصل/المسموح
//    (`WebOriginPolicy`) ⇒ يمنع Cross-Site WebSocket Hijacking.
//  * حدّ أقصى للاتصالات المتزامنة [maxTotal] ولكل عنوان [maxPerIp].
//    الاتصالات المغلقة تُقلَّم كسولًا (لا اعتماد على onDone وحده).

import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'api_auth_middleware.dart';
import 'api_web_session_handler.dart';
import 'client_address.dart';

class WsConnectionGuard {
  WsConnectionGuard._();

  static int maxTotal = 50;
  static int maxPerIp = 10;

  static final Map<WebSocketChannel, String> _conns = {};

  static void _prune() =>
      _conns.removeWhere((ch, _) => ch.closeCode != null);

  static int get activeCount {
    _prune();
    return _conns.length;
  }

  /// يعيد رفضًا (401/403/429) أو `null` إن جاز قبول الترقية.
  static Future<Response?> check(Request request) async {
    if (!WebOriginPolicy.isAllowed(request)) {
      return _deny(403, 'Origin not allowed');
    }

    final header = request.headers['authorization'];
    final q = request.requestedUri.queryParameters['token'];
    final token = (header != null && header.startsWith('Bearer '))
        ? header.substring(7)
        : (q != null && q.isNotEmpty ? q : null);
    if (token != null) {
      final deviceId = request.headers['x-device-id'] ??
          request.requestedUri.queryParameters['device_id'] ??
          '';
      if (!await ApiAuthMiddleware.verifyCredential(token, deviceId)) {
        return _deny(401, 'Invalid API token');
      }
    }

    _prune();
    if (_conns.length >= maxTotal) {
      return _deny(429, 'Too many WebSocket connections');
    }
    final ip = ClientAddress.of(request);
    if (_conns.values.where((v) => v == ip).length >= maxPerIp) {
      return _deny(429, 'Too many WebSocket connections from this address');
    }
    return null;
  }

  static void register(WebSocketChannel ws, Request request) =>
      _conns[ws] = ClientAddress.of(request);

  static void unregister(WebSocketChannel ws) => _conns.remove(ws);

  static void resetForTest() => _conns.clear();

  static Response _deny(int status, String error) => Response(
        status,
        body: jsonEncode({'error': error}),
        headers: {'content-type': 'application/json'},
      );
}
