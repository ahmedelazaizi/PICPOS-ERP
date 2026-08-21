/// حمولةُ مزامنة الاستبدال — واحدةٌ يفكّها الخادمُ إلى مستندَين.
///
/// **قرارُ المالك ٥:** لا حمولتان مرتبطتان. حمولتان تفتحان نافذةَ انفصالٍ
/// طرفاً لطرف: تصل حمولةُ المردود ويسقط البيعُ (أو العكس) فيبقى العميلُ
/// دائناً ببضاعةٍ أخذها، أو مديناً ببضاعةٍ أعادها. والحمولةُ الواحدةُ تجعل
/// الفشلَ كلَّه أو لا شيء — وهي نفسُ الضمانة التي يعطيها `_db.transaction`
/// محلّياً، ممدودةً إلى الطرف الآخر.
///
/// **ولماذا [returnLegs] قائمةٌ لا مستندٌ واحد:** `processSalesReturn` يقبل
/// `isDamaged` **للنداء كلِّه لا للسطر**. فوسمٌ مختلط — بعضُ المرتجَع معيبٌ
/// وبعضُه سليم — يُقسَم داخل معاملة الاستبدال إلى نداءَين، أيْ **سندَي**
/// مردودٍ لا سنداً واحداً. وحمولةٌ تحمل حقلَ مردودٍ مفرداً كانت ستُسقط الشقَّ
/// الثاني صامتاً: المعيبُ يبقى في مخزن الخادم سليماً، أو السليمُ يُتلَف.
library;

/// الوسمُ المشتركُ بين طرفَي الاستبدال.
///
/// يُكتب على **الشكلَين** كليهما — الفاتورةُ الأصليةُ المقلوبة (الشكل «أ»)
/// ومستندُ المردود المنفصل (الشكل «ب») — كي لا يتوقّف الربطُ على أيِّ شكلٍ
/// اختاره الطرفُ الذي كتب. اقرأ `SalesReturnHistoryEntry` لوصف الشكلَين.
String exchangeLinkTag(String exchangeKey) => '|exch:$exchangeKey';

/// إشارةُ الأصليةِ إلى فاتورة البيع البديلة.
String exchangeSaleTag(int saleInvoiceId) => '|exsale:$saleInvoiceId';

/// إشارةُ فاتورةِ البيع إلى مستند المردود.
String exchangeReturnTag(int returnDocumentId) => '|exret:$returnDocumentId';

/// يبني الحمولةَ الموحَّدة.
///
/// [exchangeKey] يخدم غرضين معاً: مفتاحُ الربط بين المستندات، ومفتاحُ
/// الـidempotency للحمولة كلِّها — فإعادةُ إرسالها من الطابور لا تُنشئ
/// استبدالاً ثانياً.
///
/// ويُحقن في كلِّ شقٍّ على حدة كذلك، فلا يتوقّف ربطُ الخادم على ترتيب
/// القائمة ولا على نجاح الشقّ الذي قبله.
Map<String, dynamic> buildExchangeSyncPayload({
  required String exchangeKey,
  required int originalInvoiceId,
  required List<Map<String, dynamic>> returnLegs,
  required Map<String, dynamic> sale,
  String? originalInvoiceGlobalId,
  String? originalInvoiceNumber,
}) {
  if (exchangeKey.isEmpty) {
    throw ArgumentError.value(
        exchangeKey, 'exchangeKey', 'مفتاحُ الاستبدال لا يكون فارغاً');
  }
  // الرفضُ هنا لا عند الخادم: حمولةٌ ناقصةُ شقٍّ تصل فتُنشئ نصفَ استبدال،
  // وهو بالضبط ما تمنعه هذه الحمولةُ الواحدة.
  if (returnLegs.isEmpty) {
    throw ArgumentError.value(returnLegs, 'returnLegs',
        'استبدالٌ بلا شقِّ مردودٍ ليس استبدالاً — أرسِله بيعاً عاديّاً');
  }
  if (sale.isEmpty) {
    throw ArgumentError.value(sale, 'sale',
        'استبدالٌ بلا شقِّ بيعٍ ليس استبدالاً — أرسِله مردوداً عاديّاً');
  }

  return <String, dynamic>{
    // `globalId` هو ما تقرأه بوّابةُ الـidempotency في الخادم، و`exchangeKey`
    // هو ما يُكتب في `notes`. قيمةٌ واحدةٌ باسمين كي لا ينزلق أحدُهما عن
    // الآخر في إعادة إرسال.
    'globalId': exchangeKey,
    'exchangeKey': exchangeKey,
    'originalInvoiceId': originalInvoiceId,
    if (originalInvoiceGlobalId != null && originalInvoiceGlobalId.isNotEmpty)
      'originalInvoiceGlobalId': originalInvoiceGlobalId,
    if (originalInvoiceNumber != null && originalInvoiceNumber.isNotEmpty)
      'originalInvoiceNumber': originalInvoiceNumber,
    'returnLegs': <Map<String, dynamic>>[
      for (final leg in returnLegs)
        <String, dynamic>{...leg, 'exchangeKey': exchangeKey},
    ],
    'sale': <String, dynamic>{...sale, 'exchangeKey': exchangeKey},
  };
}

/// يلتقط شقوقَ الاستبدال بدل إرسال كلِّ شقٍّ منفرداً.
///
/// **لماذا مُجمِّعٌ لا معاملاتٌ إضافيّةٌ على المستودعات:** شقُّ المردود يرسل
/// من `ReturnsRepositoryImpl` وشقُّ البيع من `SalesTransactionOrchestrator`،
/// وكلاهما ملفٌّ تعمل عليه جلساتٌ أخرى. وكلتا نقطتَي الإرسال تمرّان بـ
/// `ClientWriteInterceptor` — فالالتقاطُ هناك يقمع الحمولتَين المنفردتَين
/// بلا لمسِ أيٍّ من المستودعَين.
///
/// والمُجمِّعُ **لا يرسل شيئاً بنفسه**: يجمع، ثم يقرأ مالكُه [hasBothLegs]
/// ويبني. فشقُّ مردودٍ بلا بيعٍ لا يُرسَل نصفَ استبدالٍ إلى الخادم — يُمتنع.
class ExchangeLegCollector {
  final List<Map<String, dynamic>> _returnLegs = <Map<String, dynamic>>[];
  Map<String, dynamic>? _sale;

  /// لم يُلتقط شيءٌ أصلاً — الحالةُ الطبيعيّةُ في الوضع المستقلّ، إذ تخرج
  /// دوالُّ المزامنة عند `isClientMode == false` قبل أن تصل الالتقاط.
  bool get isEmpty => _returnLegs.isEmpty && _sale == null;

  /// الشقّان معاً حاضران — الشرطُ الوحيدُ لإرسال حمولةٍ صالحة.
  bool get hasBothLegs => _returnLegs.isNotEmpty && _sale != null;

  List<Map<String, dynamic>> get returnLegs =>
      List<Map<String, dynamic>>.unmodifiable(_returnLegs);

  Map<String, dynamic>? get sale => _sale;

  /// يُنادى مرّةً لكلِّ شقٍّ — مرّتين عند الوسم المختلط (سليمٌ ومعيب).
  void addReturnLeg(Map<String, dynamic> payload) => _returnLegs.add(payload);

  /// شقُّ البيع واحدٌ بالضرورة. وصولُ ثانٍ يعني أن نطاقَ التجميع التقط بيعاً
  /// لا يخصّ هذا الاستبدال — يُرفَع لا يُبتلَع، فابتلاعُه يرسل حمولةً تصف
  /// استبدالاً لم يقع.
  void setSale(Map<String, dynamic> payload) {
    if (_sale != null) {
      throw StateError(
        'استبدالٌ واحدٌ له شقُّ بيعٍ واحد — ووصل شقُّ بيعٍ ثانٍ داخل نفس '
        'نطاق التجميع.',
      );
    }
    _sale = payload;
  }

  Map<String, dynamic> build({
    required String exchangeKey,
    required int originalInvoiceId,
    String? originalInvoiceGlobalId,
    String? originalInvoiceNumber,
  }) =>
      buildExchangeSyncPayload(
        exchangeKey: exchangeKey,
        originalInvoiceId: originalInvoiceId,
        originalInvoiceGlobalId: originalInvoiceGlobalId,
        originalInvoiceNumber: originalInvoiceNumber,
        returnLegs: _returnLegs,
        sale: _sale ?? const <String, dynamic>{},
      );
}
