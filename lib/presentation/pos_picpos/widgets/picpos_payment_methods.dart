// أيُّ طرقِ دفعٍ تُعرَض في شاشة بيع PicPos — قرارٌ خالص.
//
// ── لماذا خرج من `_allowedPaymentMethods` ─────────────────────────────────
// كان القرارُ يعيش داخل دالّةٍ خاصّةٍ في `State`، فذيلُها الفاشلُ مفتوحاً
// (`catch (_) { return codeFor.keys.toSet(); }`) لم يكن قابلاً للقياس أصلاً:
// لا اختبارَ يبلغ `catch` في `State` بلا شجرةِ ودجتاتٍ كاملة. فخرج القرارُ
// إلى هنا، وبقيت القراءةُ (الصلاحياتُ والإعداد) في الشاشة.
//
// ── قاعدةُ التقاطع ────────────────────────────────────────────────────────
// المُظهَرُ = ما أذنت به الصلاحيةُ **و** أشّر عليه الإعداد. الصلاحيةُ لكلّ
// دور، والإعدادُ للتنصيبة كلِّها — ولا يتخطّى المديرُ الإعدادَ: «نقديٌّ فقط»
// قرارُ تشغيلٍ للفرع، لا قيدُ ثقةٍ بالمستخدم.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/permissions/permission_codes.dart';
import '../../../data/providers/providers.dart';

/// طرقُ الدفع المؤشَّرةُ في إعدادات نقطة البيع — `null` = بلا تضييق.
///
/// ⚠️ **موضعُه هنا مقصود**، لا في `data/providers/settings_providers.dart`:
/// حارسُ التكافؤ (`picpos_permission_parity_test`) يبذر مسحَه بملفّات
/// `lib/presentation/pos_picpos/` ثم يتبع الاستيراداتِ **بشرط** أن تُذكر
/// أنواعٌ معرَّفةٌ في المستورَد (`_declaredTypes`). وهذا الملفُّ دوالُّ
/// وثوابتُ بلا أيّ `class` — فلو عاش خارج مجلد التوأم لانقطعت الحافةُ
/// ولاختفت أكوادُ `pos_payment_*` الخمسةُ عن الحارس، فأبلغ عن خمس فجواتٍ
/// وهميةٍ (مقيسٌ 2026-08-14). ونظيرُه `picpos_cart_permissions.dart` ينجو
/// للسبب نفسِه: لأنه داخلَ المجلد.
final posEnabledPaymentMethodsProvider =
    FutureProvider<Set<String>?>((ref) async {
  final db = ref.watch(databaseProvider);
  final value = await db.getSettingValue(enabledPaymentMethodsSettingKey);
  return parseEnabledPaymentMethods(value);
});

/// طرقُ الدفع الخمسُ وكودُ صلاحية كلٍّ منها.
///
/// المفاتيحُ هي القيمُ التي تُكتب على `cart.paymentMethod` وتقرؤها شاشةُ
/// العميل (CFD) وشيبُ الصندوق ومسارُ الترحيل — فتغييرُ مفتاحٍ هنا يغيّر
/// بياناتٍ مرحَّلة، لا عرضاً.
const Map<String, String> paymentMethodPermissionCodes = <String, String>{
  'cash': PermissionCodes.posPaymentCash,
  'card': PermissionCodes.posPaymentCard,
  'click': PermissionCodes.posPaymentTransfer,
  'credit': PermissionCodes.posPaymentCredit,
  'multiple': PermissionCodes.posPaymentMultiple,
};

/// ما يبقى معروضاً حين تتعذّر قراءةُ الصلاحيات.
///
/// النقديُّ وحدَه: التِلُّ يظلّ قادراً على البيع (فلا يتوقّف المحلُّ لعطبِ
/// قراءة)، والآجلُ والبطاقةُ والتحويلُ والمتعدّدُ تُقفَل — وهي التي يقع
/// عليها الضررُ حين تُفتح بلا إذن.
const Set<String> paymentMethodsOnPermissionReadFailure = <String>{'cash'};

/// الطرقُ التي تُعرَض للكاشير.
///
/// [permissions] أكوادُ صلاحيات المستخدم، و`null` تعني **تعذّرت القراءة** —
/// وهي الحالةُ التي كانت تفشل مفتوحةً.
///
/// [enabledBySetting] الطرقُ المؤشَّرةُ في إعدادات نقطة البيع، و`null` تعني
/// إعداداً غيرَ مضبوطٍ بعد ⇒ لا تضييق.
///
/// [isPlatformCustomer] عميلُ منصّةٍ يبيع آجلاً حصراً — قيدٌ على مستوى
/// العميل يعلو على الاثنين معاً، ولذلك يُحسم أوّلاً.
Set<String> resolveAllowedPaymentMethods({
  required List<String>? permissions,
  required Set<String>? enabledBySetting,
  bool isPlatformCustomer = false,
}) {
  if (isPlatformCustomer) return const <String>{'credit'};

  if (permissions == null) return paymentMethodsOnPermissionReadFailure;

  final permitted = _permittedByPermissions(permissions);
  if (enabledBySetting == null) return permitted;
  return permitted.intersection(enabledBySetting);
}

/// الطرقُ التي **لا** يصحّ تخطّي حوارِ الدفع فيها ولو كانت الوحيدةَ المؤشَّرة.
///
/// لأن الحوارَ يلتقط فيها بياناً لا مصدرَ له سواه: `credit` يلتقط العميل
/// (وبلا عميلٍ تصير الفاتورةُ ديناً بلا مدين)، و`multiple` يلتقط التقسيم.
const Set<String> paymentMethodsRequiringDialog = <String>{'credit', 'multiple'};

/// الطريقةُ التي يُحفَظ بها مباشرةً بلا حوارِ دفع، أو `null` إن لزم الحوار.
///
/// طلبُ المالك 2026-08-14: «عند النقديّ مع البطاقة يظهر إتمامُ الدفع بالطرق
/// المؤشَّرة بطريقةٍ أسهل وأسرع» — وأسرعُها ألّا يُسأل الكاشيرُ أصلاً حين لا
/// بديلَ أمامه.
String? singlePaymentMethodFastPath(Set<String> allowed) {
  if (allowed.length != 1) return null;
  final only = allowed.first;
  if (paymentMethodsRequiringDialog.contains(only)) return null;
  return only;
}

/// مفتاحُ الإعداد الذي يحمل الطرقَ المؤشَّرة.
const String enabledPaymentMethodsSettingKey = 'pos_payment_methods_enabled';

/// يقرأ قيمةَ [enabledPaymentMethodsSettingKey] المخزَّنةَ نصّاً مفصولاً
/// بفواصل، ويرجع `null` حين لا تضييقَ.
///
/// ⚠️ القيمةُ التالفةُ (لا مفتاحَ معروفاً فيها) تُقرأ **غيرَ مضبوطة** لا
/// «صفرَ طرق»: صفرُ طرقٍ يعني تِلّاً لا يبيع، وإعدادٌ مشوَّهٌ لا يصحّ أن
/// يُوقف المحلّ.
Set<String>? parseEnabledPaymentMethods(String? raw) {
  if (raw == null || raw.trim().isEmpty) return null;
  final parsed = raw
      .split(',')
      .map((s) => s.trim())
      .where(paymentMethodPermissionCodes.containsKey)
      .toSet();
  return parsed.isEmpty ? null : parsed;
}

Set<String> _permittedByPermissions(List<String> permissions) {
  if (permissions.contains('system_admin') || permissions.contains('*')) {
    return paymentMethodPermissionCodes.keys.toSet();
  }
  return paymentMethodPermissionCodes.entries
      .where((e) => permissions.contains(e.value))
      .map((e) => e.key)
      .toSet();
}
