// طبقة مركزية لأخطاء API (بند الأمن 8.1 — تسريب الأخطاء).
//
// المشكلة: مئات المواضع كانت تعيد `$e` الخام (وبعضها stack trace) للعميل:
// نص SQL، مسارات ملفات، أسماء جداول/أعمدة، تفاصيل مكتبات.
//
// القرار (موثَّق):
//  * التفصيل الكامل (e + stack) يُسجَّل محليًا فقط (debugPrint + DiagnosticLogger)
//    ويُرجَع للعميل `{"error": "internal_error", "request_id": "<id>"}`.
//  * رسائل الأعمال المقصودة (`Exception('Validation Error: …')`، استثناءات
//    النطاق، `StateError('… not found on server')`) **تبقى كما هي** لأن
//    `OfflineSyncWorker` يصنّف الفشل الدائم (dead-letter) بمطابقة نصها؛ حذفها
//    يحوّل الأخطاء الدائمة إلى إعادة محاولة لا تنتهي. الذي يُحجب هو أخطاء
//    البنية التحتية (drift/sqlite/postgres/IO/TypeError…) وأي رسالة تشبه
//    SQL/مسار ملف/stack.
//  * رمز الحالة وبنية JSON (`error` نص) لا يتغيّران.

import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shelf/shelf.dart';

import '../../core/logging/diagnostic_logger.dart';

class ApiErrors {
  ApiErrors._();

  static const String internalCode = 'internal_error';

  static final Random _rng = Random.secure();

  static String newRequestId() {
    final b = List<int>.generate(6, (_) => _rng.nextInt(256));
    return b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  }

  static final RegExp _internalTypes = RegExp(
    r'sqlite|drift|postgres|^pg|servererror|socket|filesystem|oserror|http|'
    r'handshake|tls|timeout|typeerror|nosuchmethod|rangeerror|assertion|'
    r'unsupported|concurrentmodification|formatexception|casterror|'
    r'nullerror|stackoverflow|outofmemory|isolate',
    caseSensitive: false,
  );

  static final RegExp _internalText = RegExp(
    r'sqliteexception|driftwrapped|sqlstate|package:|dart:|\.dart[: ]|'
    r'select\s.+\sfrom\s|insert\s+into\s|update\s+\w+\s+set\s|delete\s+from\s|'
    r'[A-Za-z]:\\|#\d+\s+\S+\s+\(',
    caseSensitive: false,
  );

  /// هل [e] خطأ بنية تحتية/برمجي يجب ألا تصل تفاصيله للعميل؟
  static bool isInternal(Object e) {
    if (_internalTypes.hasMatch(e.runtimeType.toString())) return true;
    return _internalText.hasMatch(e.toString());
  }

  static void _log(String id, String where, Object e, StackTrace? st) {
    debugPrint('[API-ERR $id] $where: $e${st == null ? '' : '\n$st'}');
    DiagnosticLogger.log(
      'API-ERROR',
      'id=$id $where: $e${st == null ? '' : '\nstack: ${st.toString().split('\n').take(10).join(' | ')}'}',
    );
  }

  static Response _json(int status, Map<String, dynamic> body) => Response(
        status,
        body: jsonEncode(body),
        headers: {'Content-Type': 'application/json'},
      );

  /// رد عام صارم: لا يتسرّب شيء من [e] أبدًا.
  static Response internal(Object e, [StackTrace? st, int statusCode = 500]) {
    final id = newRequestId();
    _log(id, 'unhandled', e, st);
    return _json(statusCode, {'error': internalCode, 'request_id': id});
  }

  /// بديل `errorResponse('$prefix: $e')`: رسائل الأعمال تبقى (مع [prefix])،
  /// وأخطاء البنية التحتية تُحجب. الـstack لا يُرجَع أبدًا.
  static Response fail(
    Object e,
    String prefix, {
    StackTrace? st,
    int statusCode = 500,
  }) {
    if (isInternal(e)) {
      final id = newRequestId();
      _log(id, prefix, e, st);
      return _json(statusCode, {'error': internalCode, 'request_id': id});
    }
    if (st != null) debugPrint('[API] $prefix: $e\n$st');
    return _json(statusCode, {'error': '$prefix: $e'});
  }

  /// بديل `{'success': false, 'error': e.toString()}`.
  static Response failJson(Object e, [StackTrace? st, int statusCode = 500]) {
    if (isInternal(e)) {
      final id = newRequestId();
      _log(id, 'failJson', e, st);
      return _json(statusCode,
          {'success': false, 'error': internalCode, 'request_id': id});
    }
    return _json(statusCode, {'success': false, 'error': e.toString()});
  }

  /// ميدلوير: أي استثناء لم يعالجه معالج ⇒ 500 عام + معرّف طلب.
  static Middleware middleware() {
    return (Handler inner) {
      return (Request request) async {
        try {
          return await inner(request);
        } on HijackException {
          rethrow; // ترقية WebSocket تعتمد على هذا الاستثناء.
        } catch (e, st) {
          final id = newRequestId();
          _log(id, '${request.method} /${request.url.path}', e, st);
          return _json(500, {'error': internalCode, 'request_id': id});
        }
      };
    };
  }
}
