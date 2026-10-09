// اتصال drift remote لعميل الويب (م3-6).
//
// القرار — تهيئة بلا ترحيلات: `AppDatabase` يشغّل عند الفتح ترحيلات وPRAGMA
// وبذرة بيانات، وكلُّها كتابة/PRAGMA يرفضها اعتراضُ السياسة على المضيف (ولا
// يجوز أصلاً أن يعبث متصفّحٌ بمخطّط المضيف). لذلك تُنشأ القاعدة عبر
// `AppDatabase.forWebRemote` التي تتخطّى كلَّ ما يعمل عند الفتح، ويُضبط
// `isPostgres` (والـdialect) من استجابة الخادم عند الدخول لا من اتصال محلي.
// القاعدةُ على المضيف مفتوحةٌ أصلاً، فلا يصل إلى العميل طلبُ `beforeOpen`.
import 'dart:async';

// ignore: experimental_member_use -- البروتوكول تجريبيّ ومثبَّتٌ على drift 2.32.1.
import 'package:drift/remote.dart';
import 'package:drift/drift.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../data/database/database.dart';
import '../services/web_read/drift_json_channel.dart';
import 'web_session.dart';
import 'web_sql_comment_stripper.dart';

/// يُستدعى عند إغلاق القناة؛ [closeCode] = 4401 تعني انتهاء الجلسة/تغيّر الصلاحيات.
typedef WebChannelClosed = void Function(int? closeCode, String? reason);

/// اتصال كسول: يطلب تذكرة، يفتح WebSocket، ثم `connectToRemoteAndInitialize`.
DatabaseConnection openWebRemoteConnection(
  WebSession session, {
  WebAuthClient? auth,
  WebChannelClosed? onClosed,
}) {
  Future<DatabaseConnection> connect() async {
    final ticket = await (auth ?? WebAuthClient()).requestTicket(session);
    final ws = WebSocketChannel.connect(session.webSocketUri(ticket));
    await ws.ready;
    unawaited(
      ws.sink.done.then((_) => onClosed?.call(ws.closeCode, ws.closeReason)),
    );
    return connectToRemoteAndInitialize(driftJsonChannel(ws));
  }

  final connection = DatabaseConnection.delayed(
    connect(),
    dialect: session.isPostgres ? SqlDialect.postgres : SqlDialect.sqlite,
  );
  // تعليقات SQL في استعلامات التقارير ترفضها سياسة المضيف — تُزال هنا.
  // ‏withExecutor يُبقي مخزن الاستعلامات (إشعارات تغيّر الجداول من المضيف).
  return connection.withExecutor(
    connection.executor.interceptWith(StripCommentsInterceptor()),
  );
}

/// قاعدة الويب (قراءة فقط) فوق [openWebRemoteConnection].
AppDatabase createWebDatabase(
  WebSession session, {
  WebAuthClient? auth,
  WebChannelClosed? onClosed,
}) {
  return AppDatabase.forWebRemote(
    openWebRemoteConnection(session, auth: auth, onClosed: onClosed),
    isPostgres: session.isPostgres,
  );
}
