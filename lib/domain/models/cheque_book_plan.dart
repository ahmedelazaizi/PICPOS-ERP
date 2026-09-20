// حسابُ دفتر الشيكات — **خالصٌ**، بلا قاعدةٍ ولا ودجت.
//
// ═══ لماذا يوجد الدفترُ أصلاً ═══
//
// تفرُّدُ الشيك **الصادر** في `commercial_papers_dao.dart` مبنيٌّ على
// `(paperNumber, type, bankName)` — أي على أنّه «من دفترنا»، **بلا دفترٍ
// يضبطه**. فلا رقمَ تاليَ يُعرَف، ولا منعَ لقفزةٍ، ولا معرفةَ بما تبقّى.
//
// 🔴 **ورقمٌ مكرَّرٌ في شيكٍ صادرٍ خطأٌ يصل البنك**: الشيكُ الثاني بنفس الرقم
// يُرفَض عند التقديم أو — أسوأُ — يُصرَف أحدُهما ويُعَدُّ الآخرُ صورةً منه.
// والحارسُ الوحيدُ اليومَ يعمل **بعد** أن يُكتَب الشيكُ في المستودع، ولا
// يعمل إطلاقاً إن اختلف اسمُ البنك حرفاً («مصر» مقابل «بنك مصر»).
//
// ⇒ فالمدى هنا يُحرَس **قبل** أن يُفتَح الدفتر: دفتران متداخلان على نفس
//   الحساب البنكيّ مرفوضان، وهو الموضعُ الوحيدُ الذي يمنع التكرارَ من
//   الوقوع بدل أن يكتشفه.
//
// ═══ ⚠️ والحسابُ البنكيُّ هو المدى ═══
//
// دفتران بنفس الأرقام على **حسابَين** مختلفَين مشروعان تماماً: بنكُ مصر
// وبنكُ القاهرة كلاهما قد يسلّمك الشيكاتِ ١٠١–٢٠٠. فالتداخلُ يُقاس على
// `bankAccountId` لا على الأرقام وحدَها.

/// أكبرُ عددِ شيكاتٍ في دفترٍ واحد.
///
/// دفترٌ ورقيٌّ يحمل ٢٥ أو ٥٠ أو ١٠٠ ورقةً؛ والعشرةُ آلافٍ سقفٌ سخيٌّ
/// غرضُه مسكُ الغلطة المطبعيّة وحدَها (`to = 20000000`)، لأنّ دفتراً يبتلع
/// كلَّ الأرقام يجعل فحصَ التداخل بلا معنًى و«المتبقّي» رقماً لا يدلّ.
const int kMaxChequeBookSize = 10000;

/// صفُّ دفترٍ كما تراه الخطّة — **قيمةٌ خالصةٌ** لا صفُّ قاعدة.
typedef ChequeBookRow = ({
  int id,
  int bankAccountId,
  int fromNumber,
  int toNumber,
  int nextNumber,
  String status,
});

/// كم شيكاً بقي في الدفتر.
///
/// ⚠️ **شاملةُ الطرفين**: دفترٌ من ١٠١ إلى ٢٠٠ والتالي ١٠١ فيه **مئةُ**
/// شيكٍ لا تسعٌ وتسعون. والنقصُ بواحدٍ هنا يُظهر دفتراً منتهياً وفيه ورقة.
int chequesRemaining({required int nextNumber, required int toNumber}) {
  final n = toNumber - nextNumber + 1;
  return n < 0 ? 0 : n;
}

/// الرقمُ كما يُطبَع على الورقة: البادئةُ ثمّ الرقمُ مصفوفاً بعرض [toNumber].
///
/// ⚠️ **والعرضُ من [toNumber] لا من الرقم نفسِه**: دفترٌ ٩٨–١٠٢ يطبع
/// `098` و`099` و`100` — بعرضٍ واحدٍ كما على الورق. والصفُّ بعرض الرقم
/// وحدَه كان يعطي `98` ثمّ `100`، فيبدو رقمان من دفترَين.
String formatChequeNumber({
  String? prefix,
  required int number,
  required int toNumber,
}) {
  final width = '${toNumber < 0 ? 0 : toNumber}'.length;
  final body = '$number'.padLeft(width, '0');
  final p = prefix?.trim() ?? '';
  return p.isEmpty ? body : '$p$body';
}

/// الحالةُ **مشتقّةٌ من المدى** لا مكتوبةٌ بيد.
///
/// ⚠️ **والإلغاءُ يغلب**: دفترٌ ألغاه المستخدمُ (ضاع أو سُحب من البنك) لا
/// يعود نشطاً لأنّ فيه أرقاماً باقيةً — وإلّا سحب منه سندٌ شيكاً لا وجودَ
/// له ورقيّاً.
///
/// وما عداه: لا متبقّيَ ⇒ `exhausted`، وإلّا `active`. فتوسيعُ [toNumber]
/// على دفترٍ منتهٍ يُعيده نشطاً بلا خطوةٍ ثانية.
String resolveChequeBookStatus({
  required String current,
  required int nextNumber,
  required int toNumber,
}) {
  if (current == 'cancelled') return 'cancelled';
  return chequesRemaining(nextNumber: nextNumber, toNumber: toNumber) == 0
      ? 'exhausted'
      : 'active';
}

/// خطأُ المدى، أو `null` إن صحّ.
String? validateChequeBookRange({
  required int fromNumber,
  required int toNumber,
  required int nextNumber,
}) {
  if (fromNumber < 1) return 'رقم البداية يجب أن يكون موجباً';
  if (toNumber < fromNumber) return 'رقم النهاية قبل رقم البداية';
  if (toNumber - fromNumber + 1 > kMaxChequeBookSize) {
    return 'الدفتر أكبر من $kMaxChequeBookSize شيك — راجع رقمَي المدى';
  }
  if (nextNumber < fromNumber) return 'الرقم التالي قبل بداية الدفتر';
  // ⚠️ `toNumber + 1` مقبولٌ عمداً: هو **الدفترُ المنتهي** — آخرُ شيكٍ
  //    سُحب والتالي خارجَ المدى. ورفضُه كان يمنع إنهاءَ أيّ دفتر.
  if (nextNumber > toNumber + 1) return 'الرقم التالي خارج الدفتر';
  return null;
}

/// 🔴 أوّلُ دفترٍ يتداخل مداه مع [fromNumber]–[toNumber] على **نفس الحساب
/// البنكيّ**، أو `null`.
///
/// [editingId] يُستثنى (الدفترُ لا يتداخل مع نفسِه عند التعديل)، و`cancelled`
/// يُستثنى (أرقامُه لن تُسحَب).
ChequeBookRow? findChequeRangeOverlap({
  required List<ChequeBookRow> existing,
  required int bankAccountId,
  required int fromNumber,
  required int toNumber,
  int? editingId,
}) {
  for (final b in existing) {
    if (b.id == editingId) continue;
    if (b.status == 'cancelled') continue;
    if (b.bankAccountId != bankAccountId) continue;
    if (fromNumber <= b.toNumber && b.fromNumber <= toNumber) return b;
  }
  return null;
}

/// نتيجةُ سحبِ أرقامٍ من دفتر.
typedef ChequeAllocationPlan = ({List<int> numbers, String? error});

/// الأرقامُ التي سيسحبها سندٌ من [book] — أو سببُ الامتناع.
///
/// ⚠️ **ولا تُسحَب إلّا كاملةً**: سندٌ بثلاثة شيكاتٍ ودفترٌ فيه اثنان يُرفَض
/// كلُّه. والسحبُ الجزئيُّ كان يكتب شيكَين ويترك الثالثَ بلا رقمٍ في سندٍ
/// مُرحَّل.
ChequeAllocationPlan planChequeNumbers({
  required ChequeBookRow book,
  required int count,
}) {
  if (count <= 0) {
    return (numbers: const <int>[], error: 'لا شيكات في السند');
  }
  if (book.status == 'cancelled') {
    return (numbers: const <int>[], error: 'الدفتر ملغى — لا يُسحَب منه');
  }
  final left =
      chequesRemaining(nextNumber: book.nextNumber, toNumber: book.toNumber);
  if (left < count) {
    return (
      numbers: const <int>[],
      error: left == 0
          ? 'الدفتر انتهى — لم يبقَ فيه شيك'
          : 'لم يبقَ في الدفتر إلا $left شيكاً وطُلب $count',
    );
  }
  return (
    numbers: [for (var i = 0; i < count; i++) book.nextNumber + i],
    error: null,
  );
}
