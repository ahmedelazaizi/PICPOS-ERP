// حالة جلسة الويب (م3-6): عنوان الخادم + الرمز + الصلاحيات، وعميل الدخول.
//
// بلا أي استيراد من dart:io أو حزم الأجهزة — يعمل في المتصفح وفي اختبارات VM.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:http/http.dart' as http;

/// جلسة ويب مصادَق عليها.
class WebSession {
  const WebSession({
    required this.baseUrl,
    required this.token,
    required this.userId,
    required this.username,
    required this.displayName,
    required this.roleId,
    required this.roleName,
    required this.roleIsSystem,
    required this.permissionCodes,
    required this.isPostgres,
    required this.expiresAt,
  });

  /// أصل الخادم بلا `/` أخيرة (مثل `https://erp.example.com`).
  final String baseUrl;
  final String token;
  final int userId;
  final String username;
  final String displayName;
  final int? roleId;
  final String? roleName;
  final bool roleIsSystem;
  final List<String> permissionCodes;

  /// محرّك المضيف — يحدّد نمط SQL في العميل.
  final bool isPostgres;
  final DateTime expiresAt;

  /// الأصل الافتراضي: أصل الصفحة نفسها (الأصل موحَّد، لا CORS). خارج المتصفح
  /// (`file:`) يرجع نصاً فارغاً فيلزم إدخال العنوان.
  static String defaultBaseUrl([Uri? base]) {
    final b = base ?? Uri.base;
    if (b.scheme == 'http' || b.scheme == 'https') return b.origin;
    return '';
  }

  /// يُطبِّع ما كتبه المستخدم: فارغ → [defaultBaseUrl]؛ بلا مخطّط → `https://`.
  static String normalizeBaseUrl(String input, {Uri? base}) {
    var s = input.trim();
    if (s.isEmpty) return defaultBaseUrl(base);
    if (!s.startsWith('http://') && !s.startsWith('https://')) {
      s = 'https://$s';
    }
    while (s.endsWith('/')) {
      s = s.substring(0, s.length - 1);
    }
    return s;
  }

  /// عنوان القناة: `ws(s)://host/webdb?ticket=…`.
  Uri webSocketUri(String ticket) {
    final u = Uri.parse(baseUrl);
    return u.replace(
      scheme: u.scheme == 'https' ? 'wss' : 'ws',
      path: '/webdb',
      queryParameters: {'ticket': ticket},
    );
  }

  bool get isExpired => !DateTime.now().isBefore(expiresAt);

  /// الجلسة النشطة حالياً (يضبطها `WebSessionNotifier`). مصدرٌ ساكن لطبقة
  /// الخدمات (`WriteRouter` / `ServerProxy`) التي لا تصل إلى Riverpod.
  static WebSession? active;

  /// للاختبارات على VM: تعامَل الجلسة النشطة كأنها على متصفّح (`kIsWeb`).
  @visibleForTesting
  static bool treatAsWebForTesting = false;

  /// الجلسة النشطة إن كنّا فعلاً عميل ويب (متصفّح)، وإلا null.
  static WebSession? get activeWebClient =>
      (kIsWeb || treatAsWebForTesting) ? active : null;
}

enum WebAuthFailure { invalidCredentials, locked, network, server, badInput }

class WebAuthException implements Exception {
  WebAuthException(this.failure, this.message);
  final WebAuthFailure failure;

  /// رسالة عربية للمستخدم.
  final String message;

  @override
  String toString() => 'WebAuthException($failure): $message';
}

/// عميل مساري `/api/web/session` و`/api/web/ws-ticket`.
class WebAuthClient {
  WebAuthClient({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  static const _timeout = Duration(seconds: 20);

  Future<WebSession> login({
    required String baseUrl,
    required String username,
    required String password,
  }) async {
    if (baseUrl.isEmpty) {
      throw WebAuthException(
        WebAuthFailure.badInput,
        'أدخل عنوان السيرفر (مثل https://erp.example.com).',
      );
    }
    final http.Response r;
    try {
      r = await _client
          .post(
            Uri.parse('$baseUrl/api/web/session'),
            headers: {'content-type': 'application/json'},
            body: jsonEncode({'username': username, 'password': password}),
          )
          .timeout(_timeout);
    } on Object {
      throw WebAuthException(
        WebAuthFailure.network,
        'تعذّر الاتصال بالسيرفر. تحقّق من العنوان ومن أن السيرفر يعمل.',
      );
    }
    switch (r.statusCode) {
      case 200:
        break;
      case 400:
        throw WebAuthException(
          WebAuthFailure.badInput,
          'أدخل اسم المستخدم وكلمة المرور.',
        );
      case 401:
        throw WebAuthException(
          WebAuthFailure.invalidCredentials,
          'اسم المستخدم أو كلمة المرور غير صحيحة.',
        );
      case 403:
        throw WebAuthException(
          WebAuthFailure.server,
          'السيرفر رفض الطلب (الأصل غير مسموح).',
        );
      case 429:
        throw WebAuthException(
          WebAuthFailure.locked,
          'محاولات كثيرة خاطئة. انتظر قليلاً ثم حاول مجدداً.',
        );
      default:
        throw WebAuthException(
          WebAuthFailure.server,
          'خطأ من السيرفر (${r.statusCode}).',
        );
    }
    try {
      final m = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
      return WebSession(
        baseUrl: baseUrl,
        token: m['token'] as String,
        userId: m['userId'] as int,
        username: (m['username'] as String?) ?? username,
        displayName: (m['displayName'] as String?) ?? username,
        roleId: m['roleId'] as int?,
        roleName: m['roleName'] as String?,
        roleIsSystem: (m['roleIsSystem'] as bool?) ?? false,
        permissionCodes: [
          for (final c in (m['permissionCodes'] as List? ?? const []))
            c as String,
        ],
        isPostgres: (m['isPostgres'] as bool?) ?? false,
        expiresAt: DateTime.now().add(
          Duration(milliseconds: (m['expiresInMs'] as num).toInt()),
        ),
      );
    } catch (_) {
      throw WebAuthException(
        WebAuthFailure.server,
        'ردّ غير متوقّع من السيرفر. تأكد أنه يدعم نسخة الويب.',
      );
    }
  }

  /// تذكرة قناة لمرة واحدة (30 ثانية).
  Future<String> requestTicket(WebSession s) async {
    final http.Response r;
    try {
      r = await _client
          .post(
            Uri.parse('${s.baseUrl}/api/web/ws-ticket'),
            headers: {'x-session-token': s.token},
          )
          .timeout(_timeout);
    } on Object {
      throw WebAuthException(
        WebAuthFailure.network,
        'انقطع الاتصال بالسيرفر.',
      );
    }
    if (r.statusCode == 401) {
      throw WebAuthException(
        WebAuthFailure.invalidCredentials,
        'انتهت الجلسة. سجّل الدخول من جديد.',
      );
    }
    if (r.statusCode != 200) {
      throw WebAuthException(
        WebAuthFailure.server,
        'خطأ من السيرفر (${r.statusCode}).',
      );
    }
    return (jsonDecode(r.body) as Map<String, dynamic>)['ticket'] as String;
  }

  /// تسجيل خروج على الخادم: يُبطل sid الجلسة (`POST /api/web/logout`).
  /// أفضل جهد: فشل الشبكة لا يمنع الخروج المحلي (الرمز يموت بانتهائه).
  Future<void> logout(WebSession s) async {
    try {
      await _client
          .post(
            Uri.parse('${s.baseUrl}/api/web/logout'),
            headers: {'x-session-token': s.token},
          )
          .timeout(_timeout);
    } on Object {
      // متجاهَل عمداً.
    }
  }
}
