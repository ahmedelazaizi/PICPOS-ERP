// بوّابةُ فتح الوردية — وردياتٌ متزامنةٌ لنفس المستخدم.
//
// طلبُ المالك 2026-08-14: «إذا فُتحت ورديةٌ من جهاز، وأردتُ فتحَ وردية من
// جهازٍ آخر بنفس المستخدم — النظامُ ينبّه ولا يقبل، إلا بعد إغلاق المفتوحة.»
//
// القرارُ هنا خالص؛ القراءةُ والحوارُ في نقطة الاستدعاء.

/// ما يجب أن يفعله مسارُ فتحِ الوردية.
enum ShiftOpenGate {
  /// لا مانع — افتح ورديةً جديدة.
  mayOpen,

  /// له ورديةٌ مفتوحةٌ **على هذا الجهاز** — يكمّلها بلا سؤال.
  ///
  /// هذه هي حالةُ إعادة تشغيل التطبيق، وكانت تعمل صحيحةً قبل هذا العمل
  /// فيجب ألّا تتغيّر.
  alreadyOpenHere,

  /// له ورديةٌ مفتوحةٌ جاءت من طرفٍ آخر ⇒ نبّه وامنع.
  openOnAnotherTerminal,
}

/// أيَّ الحالات نحن فيها.
///
/// [hasLocalOpenShift] نتيجةُ `getCurrentOpenShift(userId)` **قبل** أيّ سحب.
///
/// [hasOpenShiftAfterPull] نتيجتُها **بعد** `pullTable('shifts')`. لا معنى
/// لها خارج وضع العميل.
///
/// [isClient] وضعُ العميل. التنصيبةُ المستقلّةُ لا سيرفرَ لها فلا سحبَ ولا
/// طرفَ آخر — ولا تُمنع أبداً.
///
/// ── لماذا «قبل/بعد السحب» لا عمودُ طرفيّة ────────────────────────────────
/// `posTerminalId` يبقى `null` متى لم تكن الطرفيّةُ مسجَّلةً محلياً، و
/// `originClientId` لا يُكتب في مسار الفتح. فالمميِّزُ الوحيدُ الأمينُ هو
/// **متى ظهر الصفّ**: كان محلياً ⇒ لي على هذا الجهاز؛ ظهر بالسحب ⇒ من طرفٍ
/// آخر.
ShiftOpenGate decideShiftOpenGate({
  required bool hasLocalOpenShift,
  required bool hasOpenShiftAfterPull,
  required bool isClient,
}) {
  if (hasLocalOpenShift) return ShiftOpenGate.alreadyOpenHere;
  if (!isClient) return ShiftOpenGate.mayOpen;
  if (hasOpenShiftAfterPull) return ShiftOpenGate.openOnAnotherTerminal;
  return ShiftOpenGate.mayOpen;
}
