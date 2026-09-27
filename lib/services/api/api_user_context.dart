// 060 (D1-001) — Per-user authentication for the embedded HTTP server.
//
// The transport auth is a shared Bearer token; once a client holds it,
// the token alone says nothing about WHICH user is acting. This helper
// reads the identity that `ApiAuthMiddleware` derived from the **signed**
// `X-Session-Token` and gates individual handlers on a permission code.
//
// ⚠️ **الترويسةُ `X-User-Id` لم تعد تُقرأ.** كانت هويّةً يدّعيها العميلُ
// بنفسه، فاستُبدلت بتوكن جلسةٍ موقَّعٍ يمنحه الخادم بعد التحقّق من
// الاعتماد. ويحرس ذلك `test/unit/client_user_id_header_test.dart`.
//
// ⚠️ **ولا مفتاحَ تشغيلٍ بعد اليوم.** كانت الطبقةُ كلُّها مسيَّجةً بالإعداد
// `server_per_user_perms_enabled` بافتراضِ **إطفاء** — والإعدادُ لا يُزرع
// في أيِّ تنصيبةٍ (‏لا بذرةَ SQLite ولا بذرةَ PostgreSQL ولا هجرةَ ولا
// خريطةَ افتراضات)، وكاتبُه الوحيد زرٌّ في الإعدادات. فالنتيجةُ المقيسة أنّ
// **١٠٤ بوّاباتِ صلاحيّة** على مسارات POST/PUT/DELETE كانت تمرّ تلقائيّاً
// على كلِّ تنصيبة. الفحصُ الآن بلا شرط.

import 'package:shelf/shelf.dart';

import '../../core/logging/diagnostic_logger.dart';
import '../../data/database/database.dart';

/// Shelf request-context keys.
class ApiUserCtx {
  ApiUserCtx._();

  /// Stored in `request.context[userIdKey]` after the middleware verifies
  /// the signed `X-Session-Token`. Null when no valid token was presented.
  static const String userIdKey = 'urs.userId';

  /// Read the verified userId from the request context. Returns null when
  /// the middleware didn't populate it — no session token, or one that
  /// failed signature/expiry verification.
  static int? userIdOf(Request request) {
    final v = request.context[userIdKey];
    if (v is int) return v;
    return null;
  }

  /// Permission gate. Reads the userId from request.context, looks up
  /// `userHasPermission(userId, code)`, returns null when allowed and
  /// a Response(403) when denied.
  ///
  /// When per-user perms are disabled (setting off OR no userId stored),
  /// auto-passes — preserves pre-060 behavior.
  static Future<Response?> requirePermission(
    Request request,
    AppDatabase db,
    String code,
  ) async {
    // ── لماذا لا شرطَ هنا بعد اليوم ──────────────────────────────────────
    // كان السطرُ الأوّل `if (!await isPerUserPermsEnabled(db)) return null;`
    // والمفتاحُ `server_per_user_perms_enabled` **لا يُزرع في أيِّ تنصيب**:
    // لا في `database_seeder`، ولا في بذرة PostgreSQL، ولا في هجرة، ولا في
    // خريطة افتراضات. كاتبُه الوحيد زرُّ إعداداتٍ لا أحدَ يضغطه. فالنتيجةُ
    // المقيسة أنّ **كلَّ** بوّاباتِ الصلاحيّة الـ١٠٤ على مسارات
    // POST/PUT/DELETE كانت تمرّ تلقائيّاً على كلِّ تنصيبةٍ جديدة: توكنُ LAN
    // واحدٌ يفتح `POST /api/users/<id>/password` و
    // `POST /api/roles/<id>/permissions` و`POST /api/settings`.
    // البوّابةُ الآن تُنفَّذ بلا شرط. و`role_grant_preflight_service` يبقى
    // تقريراً يُشغَّل **قبل** الطرح ليكشف الأدوارَ الناقصةَ منحاً.
    final userId = userIdOf(request);
    if (userId == null) {
      return Response(
        401,
        // ⚠️ الرسالةُ كانت تقول `X-User-Id` وهو ترويسةٌ **لم تعد تُقرأ**
        // (‏استُبدلت بـ`X-Session-Token` الموقَّع، ويحرسها
        // `test/unit/client_user_id_header_test.dart`). فمشغِّلٌ يقرأ السجلَّ
        // كان يُرسَل إلى ترويسةٍ لا وجودَ لها.
        body: '{"error":"Missing or invalid X-Session-Token"}',
        headers: const {'content-type': 'application/json'},
      );
    }
    // Bootstrap admins use the same permission path as every other user;
    // critical financial codes remain explicit for segregation of duties.
    final ok = await db.userHasPermission(userId, code);
    if (!ok) {
      return Response(
        403,
        body: '{"error":"User #$userId lacks permission: $code"}',
        headers: const {'content-type': 'application/json'},
      );
    }
    return null;
  }

  /// يحسم **من يفعل** الطلبَ: هويّةُ الجلسة هي المرجع، وادّعاءُ الجسم
  /// (`data['userId']`) لا يُقبل إلّا إن طابقها.
  ///
  /// ── لماذا هذا حارسٌ لا تجميل ──────────────────────────────────────────
  /// بعضُ الدوالّ تجعل الفاعلَ **موضوعَ** فحصِ صلاحيّةٍ لا مجرَّدَ وسمِ
  /// نسبة — `voidSalesInvoice` و`voidPurchaseInvoice` تمرّرانه إلى فحص
  /// `voidPaidInvoice`، و`createSalesInvoice` تمرّره إلى
  /// `overrideCreditLimit`. وكلاهما من العمليّات الماليّة الحرجة المستثناة
  /// عمداً من تجاوز المدير. فحين يُقرأ الفاعلُ من جسم الطلب يصير المستدعي
  /// هو من يختار **من تُفحَص صلاحيّتُه**: كاشيرٌ يرسل رقمَ مديرٍ فيمرّ.
  ///
  /// يُرجع `(actor, null)` عند القبول، و`(null, Response(403))` عند التعارض.
  /// وحين لا توجد جلسةٌ يُرجع `(null, null)` — ولا يُعوَّض بادّعاء الجسم:
  /// المسارُ محميٌّ سلفاً بـ[requirePermission] التي ترفض بلا جلسة، والفحصُ
  /// الحرجُ يفشل مغلقاً على `null`.
  static (int?, Response?) resolveActor(
    Request request,
    int? claimedUserId, {
    String logTag = 'API-ACTOR',
    String? context,
  }) {
    final sessionUserId = userIdOf(request);
    if (claimedUserId != null &&
        sessionUserId != null &&
        claimedUserId != sessionUserId) {
      // ignore: discarded_futures — أثرٌ تدقيقيٌّ لا ننتظره.
      DiagnosticLogger.log(
        logTag,
        '⛔ رفض تعارضِ هويّة: الجسم يدّعي #$claimedUserId '
        'والجلسة #$sessionUserId${context == null ? '' : ' — $context'}',
      );
      return (
        null,
        Response(
          403,
          body: '{"error":"هويّةُ الجسم تخالف هويّةَ الجلسة — الطلب مرفوض"}',
          headers: const {'content-type': 'application/json'},
        )
      );
    }
    return (sessionUserId, null);
  }
}
