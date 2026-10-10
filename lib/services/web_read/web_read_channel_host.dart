// مضيف قناة قراءة الويب (م3-5): `GET /webdb?ticket=...` فوق WebSocket.
//
// لكلّ اتصال:
//   1. تُستهلك التذكرة (مرة واحدة، 30 ثانية — `WebWsTicketStore`)؛ فاشلة → 401
//      قبل الترقية إلى WebSocket.
//   2. تُحسب الجداول المسموحة من أكواد المستخدم الحالية
//      (`getUserPermissionCodes` → `WebTablePolicy.allowedTables`).
//   3. يُنشأ `DriftServer` **مستقلٌّ** عبر `createWebReadDriftServer` ملفوفاً
//      حول `db.executor` المشترَك (قراءة فقط + اعتراض السياسة)، ويخدم القناة
//      عبر `driftJsonChannel`.
//   4. تُغلق القناة (رمز 4401) عند: تعطيل/قفل/حذف المستخدم، تغيّر دوره أو
//      أكواده، إلغاء `sid`، أو انتهاء الجلسة (12 ساعة) — فحصٌ دوري كل
//      [checkInterval] + مؤقّتٌ عند انتهاء الجلسة.
//   5. تُوجَّه تغييرات الجداول إلى العميل (`ApiHandlerBase.onDataChanged`
//      و`db.tableUpdates()`) مرشَّحةً بالجداول المسموحة فقط، كي يعيد `watch()`
//      في الويب قراءته دون أن يتسرّب اسمُ جدولٍ ممنوع.
//
// ⚠️ الجلسة المفتوحة تحمل لقطة الأكواد وقتَ الفتح؛ التغيير يُغلقها فيعيد
// العميل الدخول — لا نعيد حساب الجداول داخل اتصال حيّ.

import 'dart:async';

import 'package:drift/drift.dart';
// ‏`NotifyTablesUpdated` غير مُصدَّر من `package:drift/remote.dart`؛ هو حمولة
// البروتوكول التي يقبلها `DriftServer.dispatchTableUpdateNotification` علناً،
// فنستورده من `src` (مثبَّتٌ على 2.32.1 — أعد فحصه عند أيّ ترقية لـdrift).
// ignore: implementation_imports
import 'package:drift/src/remote/protocol.dart' show NotifyTablesUpdated;
import 'package:flutter/foundation.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../core/permissions/web_table_policy.dart';
import '../../data/database/database.dart';
import '../api/api_handler_base.dart' show ApiHandlerBase;
import '../api/api_session_token.dart';
import '../api/api_web_session_handler.dart';
import 'drift_json_channel.dart';
import 'web_read_policy_interceptor.dart';

/// رمز الإغلاق (مجال التطبيق 4000-4999): الجلسة انتهت/أُبطلت — أعد الدخول.
const int kWebChannelSessionEnded = 4401;

class WebReadChannelHost {
  WebReadChannelHost(
    this._db, {
    this.checkInterval = const Duration(seconds: 15),
    int Function()? nowMs,
  }) : _nowMs = nowMs ?? (() => DateTime.now().millisecondsSinceEpoch);

  final AppDatabase _db;

  /// دورية فحص المستخدم/الدور (تُقصَّر في الاختبارات).
  final Duration checkInterval;
  final int Function() _nowMs;

  /// معالج shelf لـ`GET /webdb`.
  Future<Response> handle(Request request) async {
    final ticket = WebWsTicketStore.consume(
      request.url.queryParameters['ticket'],
      nowMs: _nowMs(),
    );
    if (ticket == null) {
      return Response(401, body: 'Invalid or expired ticket');
    }
    final snapshot = await _snapshot(ticket.userId);
    if (snapshot == null) {
      return Response(403, body: 'User not allowed');
    }
    final allowed = WebTablePolicy.allowedTables(snapshot.codes);
    return webSocketHandler(
      (WebSocketChannel ws, String? _) =>
          _serve(ws, ticket, snapshot, allowed),
      pingInterval: const Duration(seconds: 30),
    )(request);
  }

  Future<void> _serve(
    WebSocketChannel ws,
    WebWsTicket ticket,
    _UserSnapshot opened,
    Set<String> allowed,
  ) async {
    final lowered = {for (final t in allowed) t.toLowerCase()};
    final server = createWebReadDriftServer(
      _db.executor,
      allowedTables: allowed,
    );
    // ‏driftJsonChannel(ws) مباشرةً يربط ws.sink بـddStream طيلة الاتصال،
    // فيرفض ws.sink.close(code, reason) ("Cannot close sink while adding
    // stream"). نصل القناة يدوياً (listen/add) كي نغلق برمز التطبيق 4401.
    final bridge = StreamChannelController<dynamic>(allowForeignErrors: false);
    bridge.local.stream.listen(
      ws.sink.add,
      onError: (Object _) {},
      cancelOnError: false,
    );
    var closing = false;
    ws.stream.listen(
      // بعد قرار الإغلاق (إبطال/تعطيل) لا يُمرَّر أيُّ استعلامٍ وارد.
      (Object? m) {
        if (!closing) bridge.local.sink.add(m);
      },
      onError: (Object _) {},
      onDone: () => bridge.local.sink.close(),
    );
    final served = server.serve(driftJsonChannel(bridge.foreign));

    void push(Iterable<String> tables) {
      final visible = {
        for (final t in tables)
          if (lowered.contains(t.toLowerCase())) t,
      };
      if (visible.isEmpty) return;
      server.dispatchTableUpdateNotification(
        NotifyTablesUpdated([for (final t in visible) TableUpdate(t)]),
      );
    }

    final subs = <StreamSubscription<Object?>>[
      ApiHandlerBase.onDataChanged.listen((t) => push([t])),
      _db.tableUpdates().listen((s) => push(s.map((u) => u.table))),
    ];

    Future<void> end(String reason) async {
      if (closing) return;
      closing = true;
      debugPrint('[WebDB] closing channel (user ${ticket.userId}): $reason');
      try {
        await ws.sink.close(kWebChannelSessionEnded, reason);
      } catch (e) {
        debugPrint('[WebDB] close failed: $e');
      }
    }

    Future<void> check() async {
      if (_nowMs() >= ticket.sessionExpiresAtMs) {
        return end('session expired');
      }
      if (ApiSessionToken.isSidRevoked(ticket.sid)) {
        return end('session revoked');
      }
      final now = await _snapshot(ticket.userId);
      if (now == null) return end('user disabled');
      if (now.roleId != opened.roleId || !_sameCodes(now.codes, opened.codes)) {
        return end('role changed');
      }
    }

    final periodic = Timer.periodic(checkInterval, (_) {
      // خطأ عابر في القراءة لا يُغلق القناة؛ التالي يعيد المحاولة.
      check().catchError((Object e) => debugPrint('[WebDB] check failed: $e'));
    });
    final untilExpiry = ticket.sessionExpiresAtMs - _nowMs();
    final expiry = Timer(
      Duration(milliseconds: untilExpiry < 0 ? 0 : untilExpiry),
      () => end('session expired'),
    );

    try {
      await served;
    } finally {
      periodic.cancel();
      expiry.cancel();
      for (final s in subs) {
        await s.cancel();
      }
      await server.shutdown();
    }
  }

  /// لقطة المستخدم الفعّال، أو null إن عُطِّل/قُفل/حُذف.
  Future<_UserSnapshot?> _snapshot(int userId) async {
    final user = await (_db.select(_db.users)
          ..where((u) => u.id.equals(userId)))
        .getSingleOrNull();
    if (user == null ||
        !user.isActive ||
        user.isLocked ||
        user.deletedAt != null) {
      return null;
    }
    final codes = await _db.getUserPermissionCodes(userId);
    return _UserSnapshot(user.roleId, codes);
  }

  static bool _sameCodes(List<String> a, List<String> b) {
    final sa = a.toSet(), sb = b.toSet();
    return sa.length == sb.length && sa.containsAll(sb);
  }
}

class _UserSnapshot {
  _UserSnapshot(this.roleId, this.codes);
  final int? roleId;
  final List<String> codes;
}
