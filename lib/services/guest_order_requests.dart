import 'package:flutter/foundation.dart';

/// بندٌ في طلبِ ضيف — **معرِّفُ صنفٍ وكمّيّةٌ لا سعر**.
///
/// ⚠️ **ولا سعرَ عمداً.** المصدرُ هاتفٌ غيرُ مصادَق، وسعرٌ يأتي منه هو سعرٌ
/// يكتبه الزبون. التسعيرُ يقع عند الاعتماد من `Products.salePrice` ولقطةِ
/// الضريبة، تماماً كما لو أدخله النادلُ بيده.
@immutable
class GuestOrderLine {
  final int productId;
  final double quantity;

  /// «بلا بصل» — تصل المطبخ وتُطبع.
  final String? note;

  const GuestOrderLine({
    required this.productId,
    required this.quantity,
    this.note,
  });
}

/// طلبُ ضيفٍ معلَّقٌ ينتظر اعتمادَ النادل.
@immutable
class GuestOrderRequest {
  final int id;
  final int tableId;
  final int orderId;
  final String tableName;
  final List<GuestOrderLine> lines;
  final DateTime at;

  const GuestOrderRequest({
    required this.id,
    required this.tableId,
    required this.orderId,
    required this.tableName,
    required this.lines,
    required this.at,
  });
}

/// طابورُ طلباتِ الضيوف — في ذاكرة **الخادم** وحدَه.
///
/// ═══ لماذا الاعتمادُ شرط ═══
///
/// المصدرُ هاتفٌ غيرُ مصادَق. وإدخالُ بنودٍ منه مباشرةً في الطلب يعني أنّ من
/// مسح رمزَ طاولةٍ مشغولةٍ وهو يمرّ بجانبها يستطيع إرسالَ أصنافٍ إلى **مطبخٍ
/// يطبخها** على حساب من يجلس عليها. فالاعتمادُ ليس تشدّداً إداريّاً: هو ما
/// يمنع طعاماً يُهدَر وحساباً يُنفَخ.
///
/// ═══ ولماذا الذاكرةُ لا جدول ═══
///
/// الطلبُ **ليس مستنداً ماليّاً** حتى يُعتمَد؛ وعند الاعتماد يمرّ بمسار
/// `addOrUpdateTableOrderItem` فيُكتَب صفّاً حقيقيّاً بلقطة ضريبته. فصفٌّ
/// يعيش دقائقَ ثمّ يُستهلَك لا يستحقّ جدولاً ولا هجرةً ولا ثمانيَ قوائمِ
/// مزامنة، وفقدانُه بإعادة تشغيلٍ يعادل نقرةً يعيدها الضيف.
///
/// ⚠️ **وسقوفُه حراسةٌ لا تجميل**: المُدخِلُ غيرُ مصادَقٍ، فبلا سقفٍ يملؤه من
/// يكرّر الضغط حتى تختنق ذاكرةُ الخادم — أرخصُ هجومٍ على الإطلاق.
class GuestOrderRequests extends ChangeNotifier {
  GuestOrderRequests._();

  static final GuestOrderRequests instance = GuestOrderRequests._();

  /// نسخةٌ معزولةٌ للاختبارات — الحالةُ ساكنةٌ فلا تتسرّب بين الاختبارات.
  @visibleForTesting
  factory GuestOrderRequests.forTesting() => GuestOrderRequests._();

  /// أقصى ما يُعلَّق على طلبِ طاولةٍ واحدٍ في وقتٍ واحد.
  static const int maxPerOrder = 5;

  /// أقصى عددِ بنودٍ في الطلب الواحد.
  static const int maxLinesPerRequest = 20;

  final List<GuestOrderRequest> _pending = [];
  int _seq = 0;

  /// المعلَّقُ الآن — بترتيب وصوله.
  List<GuestOrderRequest> get pending => List.unmodifiable(_pending);

  /// المعلَّقُ على طلبٍ بعينه.
  List<GuestOrderRequest> forOrder(int orderId) =>
      [for (final r in _pending) if (r.orderId == orderId) r];

  /// يُدرج الطلبَ ويعود بمعرّفه، أو `null` إن رُفض.
  ///
  /// والرفضُ **لا يوقظ** المستمعين: لا شيءَ تغيّر، وإيقاظُ شاشةِ النادل على
  /// محاولةٍ مرفوضةٍ يجعلها ترتجف بلا سبب.
  int? enqueue({
    required int tableId,
    required int orderId,
    required String tableName,
    required List<GuestOrderLine> lines,
  }) {
    if (lines.isEmpty || lines.length > maxLinesPerRequest) return null;
    for (final line in lines) {
      // كمّيّةٌ سالبةٌ تُنقص حسابَ الضيف من هاتفه، وصفرٌ بندٌ بلا معنى.
      if (line.quantity <= 0) return null;
      if (line.productId <= 0) return null;
    }
    if (forOrder(orderId).length >= maxPerOrder) return null;

    final request = GuestOrderRequest(
      id: ++_seq,
      tableId: tableId,
      orderId: orderId,
      tableName: tableName,
      lines: List.unmodifiable(lines),
      at: DateTime.now(),
    );
    _pending.add(request);
    notifyListeners();
    return request.id;
  }

  /// يأخذ الطلبَ ليُعتمَد — ويُسقطه من الطابور.
  ///
  /// ⚠️ **استهلاكٌ لا قراءة**: نقرتان على «اعتماد» — وهما واردتان على شاشةِ
  /// لمسٍ في مطعمٍ مزدحم — كانتا تُضاعفان الطلبَ على حساب الضيف.
  GuestOrderRequest? take(int id) {
    final at = _pending.indexWhere((r) => r.id == id);
    if (at < 0) return null;
    final out = _pending.removeAt(at);
    notifyListeners();
    return out;
  }

  /// يرفض الطلبَ — نفسُ الإسقاط بلا اعتماد.
  bool reject(int id) => take(id) != null;

  /// يُسقط كلَّ ما عُلِّق على طلبٍ أُغلق أو أُلغي.
  ///
  /// ⚠️ ولا يُترَك ليذبل: طلبٌ معلَّقٌ على طاولةٍ أُغلقت ثمّ اعتُمد يُضيف
  /// أصنافاً إلى **حساب الضيف التالي** الذي جلس عليها.
  void dropForOrder(int orderId) {
    final before = _pending.length;
    _pending.removeWhere((r) => r.orderId == orderId);
    if (_pending.length != before) notifyListeners();
  }

  /// تفريغٌ كامل — عند إيقاف الخادم.
  void clear() {
    if (_pending.isEmpty) return;
    _pending.clear();
    notifyListeners();
  }
}
