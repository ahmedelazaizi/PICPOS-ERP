// lib/core/navigation/default_screen_resolver.dart
//
// «الشاشة الافتراضية» للمستخدم عند الدخول — محلِّلٌ خالصٌ بلا Flutter.
//
// المخزَّن في `users.default_screen` نصٌّ. الصيغةُ الجديدة `ScreenId.name`
// (مثل `salesInvoices`). والقيمُ القديمةُ تُفهم كلُّها:
//   • المفاتيحُ الخمسة القديمة `pos|dashboard|tables|products|inventory`
//     — وهي أسماءُ `ScreenId` نفسِها بنفس الفهارس (1·0·3·4·8)، فلا جدولَ
//     ترجمةٍ ثانٍ يتباعد؛ يقيسه `default_screen_resolver_test`.
//   • فهرسٌ رقميٌّ (`'0'` · `'12'`) كما كتبه إعدادُ `default_home_screen`.
//   • أيُّ شيءٍ آخر ⇒ يُتجاهل (لا استثناء، ولا شاشةٌ عشوائية).
import 'screen_id.dart';

/// فهرسُ التنقّل الذي يقصده [stored]، أو `null` إن لم يُفهم.
int? parseStoredScreen(String? stored) {
  final v = stored?.trim();
  if (v == null || v.isEmpty) return null;
  for (final id in ScreenId.values) {
    if (id.name == v) return id.navigationIndex;
  }
  return int.tryParse(v);
}

/// الفهرسُ الذي يُفتح عند الدخول.
///
/// الترتيب: قيمةُ المستخدم (أو [globalDefault] — إعدادُ `default_home_screen`
/// — حين لا قيمةَ للمستخدم) ← البيعُ السريع ← أولُ شاشةٍ مسموحة ← 0.
/// والنتيجةُ **ضمن [allowed] دائماً**؛ و`null` إن كانت [allowed] فارغةً
/// (مستخدمٌ لا يفتح أيَّ شاشة ⇒ تعرض الشاشةُ الرئيسيةُ حالةَ «لا شاشات»، لا
/// لوحةَ تحكّمٍ غيرَ مسموحة) — B-7.
int? resolveDefaultScreenIndex(
  String? stored,
  List<int> allowed, {
  String? globalDefault,
}) {
  // قيمةٌ مخزَّنةٌ غيرُ مفهومة ⇒ البيعُ السريع (كالسلوك القديم)، لا الإعدادُ
  // العامّ: هذا الأخيرُ لمن لم يختر شيئاً أصلاً.
  final hasStored = stored != null && stored.trim().isNotEmpty;
  final target =
      hasStored ? parseStoredScreen(stored) : parseStoredScreen(globalDefault);
  if (target != null && allowed.contains(target)) return target;
  if (allowed.contains(ScreenId.pos.navigationIndex)) {
    return ScreenId.pos.navigationIndex;
  }
  return allowed.isNotEmpty ? allowed.first : null;
}
