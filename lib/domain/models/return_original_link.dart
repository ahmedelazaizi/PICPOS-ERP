/// رابطُ مرتجعِ المبيعات بفاتورته الأصليّة — دوالٌّ خالصة.
///
/// `SalesInvoices` **لا يحمل عموداً** لهذا الرابط: يُكتب نصّاً في `notes`
/// بالصيغة `Return for invoice #<id>|gid:<uuid>`.
///
/// ⚠️ **والقراءةُ تحلّ بالمعرّف العالميّ أوّلاً**: المعرّفُ الرقميُّ لا معنى له
/// إلّا في المخزن الذي كتبه، والسحبُ يستبدل صفَّ العميل بصفِّ الخادم
/// (`serverWins`) — فالقراءةُ بالرقم وحدَه تُقاصّ الاستردادَ على فاتورةٍ خاطئة
/// أو على لا شيء. والرقمُ احتياطٌ لصفوفٍ كُتبت قبل هذه الصيغة.
///
/// ⚠️ **واستُخرجت إلى هنا لتُشارَك**: كانت خاصّةً داخلَ `SalesDao`، ومِكنسةُ
/// إشعارات الائتمان تحتاجها. ونسخةٌ ثانيةٌ كانت ستتخلّف عن الأولى فيُقاصّ
/// الاستردادُ في شاشةٍ على فاتورةٍ ويُقدَّم إشعارُ الائتمان على أخرى.
library;

const _prefix = 'Return for invoice #';
const _gidTag = '|gid:';

/// يبني ملاحظةَ الربط.
String buildReturnOriginalLinkNote(int originalInvoiceId,
    {String? originalGlobalId}) {
  final base = '$_prefix$originalInvoiceId';
  if (originalGlobalId == null || originalGlobalId.isEmpty) return base;
  return '$base$_gidTag$originalGlobalId';
}

/// `'Return for invoice #12|gid:<uuid>'` ← `<uuid>`؛ و`null` عند الغياب.
String? returnOriginalGidFromNote(String? notes) {
  if (notes == null) return null;
  final i = notes.indexOf(_gidTag);
  if (i < 0) return null;
  var gid = notes.substring(i + _gidTag.length).trim();
  // وسمٌ ثالثٌ في نفس الحقل (‏مسارُ الاستبدال يُلحق `|exch:`) لا يُبتلَع.
  final bar = gid.indexOf('|');
  if (bar >= 0) gid = gid.substring(0, bar).trim();
  return gid.isEmpty ? null : gid;
}

/// `'Return for invoice #12|gid:…'` ← `12`؛ و`null` حين لا تتبع الملاحظةُ
/// الصيغةَ أصلاً (‏مرتجعُ نقطةِ بيعٍ سريعٌ بلا أصل).
int? returnOriginalIdFromNote(String? notes) {
  if (notes == null || !notes.startsWith(_prefix)) return null;
  var tail = notes.substring(_prefix.length);
  final bar = tail.indexOf('|');
  if (bar >= 0) tail = tail.substring(0, bar);
  return int.tryParse(tail.trim());
}

/// رسالة رفض إلغاء مستند مرتجع (`saleType == 'return'`) بوصفه فاتورة.
const kSalesVoidReturnDocMessage =
    'هذا مستند مرتجع — استخدم «إلغاء المرتجع» من سجل مرتجعات المبيعات بدل إلغاء الفاتورة.';

/// رسالة رفض إلغاء فاتورة لها مرتجع حيّ.
const kSalesVoidHasReturnMessage =
    'لا يمكن إلغاء فاتورة لها مرتجع. ألغِ المرتجع أولاً من «سجل مرتجعات المبيعات» ثم أعد المحاولة.';

/// رفضُ إلغاءِ فاتورة بيع لأن لها مرتجعاً حيّاً (أو لأنها مستند مرتجع أصلاً).
///
/// استثناءُ أعمالٍ لا خطأُ بنية: يحمل الرسالةَ العربية وحدها في `toString()`
/// (كـ`PermissionDeniedException`) فتعرضها `AppErrorHandler` كما هي، ويحوّله
/// `ApiSalesHandler` إلى 409، ويصنّفه `OfflineSyncWorker` فشلاً دائماً.
class SalesVoidBlockedException implements Exception {
  const SalesVoidBlockedException(this.message);
  final String message;
  @override
  String toString() => message;
}