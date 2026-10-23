// حارس الكتابة غير المدعومة على الويب (م3-9).
//
// على الويب تمرّ الكتابات المدعومة (المُعترَضة في ClientWriteInterceptor) عبر
// HTTP إلى المضيف؛ أما دوالّ `AppDatabase` التي تكتب مباشرةً (دفاتر السندات،
// مواقع المستودع، توزيع المناديب…) فتُرفض من قناة القراءة (`WebReadPolicyInterceptor`)
// بخطأٍ تقنيٍّ إنجليزي. هذا الحارس يمنعها قبل الوصول ويُظهر رسالةً عربيةً واضحة
// بدل الفشل الصامت. على الديسكتوب لا أثر له إطلاقاً (`isWeb` خاطئة).
//
// الاستعمال:
//   onPressed: WebWriteGuard.wrap(context, () => save(), feature: 'دفتر السندات')
//   if (!WebWriteGuard.allow(context, feature: '...')) return;
//
// التصنيف الكامل للكتابات: docs/superpowers/specs/2026-web-write-audit.md
import 'package:flutter/material.dart';
import 'package:picpos_erp/core/i18n/tr.dart';

import 'web_session.dart';

class WebWriteGuard {
  WebWriteGuard._();

  /// هل نعمل كعميل ويب بجلسة نشطة؟ (على الديسكتوب دائماً false.)
  static bool get isWeb => WebSession.activeWebClient != null;

  /// الرسالة العربية الموحّدة.
  static String message([String? feature]) {
    final base =
        tr('هذه العملية غير مدعومة في نسخة الويب بعد — استخدم تطبيق سطح المكتب.');
    if (feature == null || feature.trim().isEmpty) return base;
    return '${feature.trim()}: $base';
  }

  /// يعيد true إن كانت الكتابة مسموحة (ديسكتوب)؛ وإلا يعرض الرسالة ويعيد false.
  static bool allow(BuildContext context, {String? feature}) {
    if (!isWeb) return true;
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(SnackBar(content: Text(message(feature))));
    return false;
  }

  /// يلفّ معالج زرٍّ: على الديسكتوب يعيد [action] كما هو، وعلى الويب يعرض الرسالة.
  /// يمرّر null كما هو (زرٌّ معطَّلٌ أصلاً يبقى معطَّلاً).
  static VoidCallback? wrap(
    BuildContext context,
    VoidCallback? action, {
    String? feature,
  }) {
    if (action == null || !isWeb) return action;
    return () => allow(context, feature: feature);
  }

  /// نسخة غير متزامنة لمعالجات `async`.
  static Future<void> Function()? wrapAsync(
    BuildContext context,
    Future<void> Function()? action, {
    String? feature,
  }) {
    if (action == null || !isWeb) return action;
    return () async => allow(context, feature: feature);
  }
}
