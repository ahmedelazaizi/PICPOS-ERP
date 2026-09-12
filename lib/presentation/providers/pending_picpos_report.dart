import 'package:flutter/foundation.dart';

/// طلبُ فتحِ تقريرٍ بعينه — من الشريط الجانبيّ إلى شاشة التقارير.
@immutable
class PicposReportRequest {
  /// معرّفُ فئة التقارير (‏`sales` · `profit` …) كما في `buildPicposReportCatalog`.
  final String categoryId;

  /// معرّفُ التقرير داخلَها، أو `null` لفتح الفئة وحدَها.
  final String? reportId;

  const PicposReportRequest({required this.categoryId, this.reportId});
}

/// وسيطُ التسليم بين الشريط والشاشة.
///
/// ⚠️ **ولماذا مُبلِّغٌ ثابتٌ لا مزوِّدُ Riverpod**: مزوّداتُ هذا المستودع
/// `autoDispose` افتراضاً. والطلبُ يُكتَب في الشريط **ثمّ** تُبنى الشاشة —
/// وبين الكتابة والقراءة لا مشترِكَ يُبقيه حيّاً، فيسقط المزوّدُ إلى حالته
/// الأولى ويصل الطلبُ فارغاً. وهو عطبٌ لا يظهر في اختبارٍ يُبقي المزوّدَ
/// مشترَكاً فيه طوال الاختبار.
///
/// ⚠️ **و`ChangeNotifier` لا `ValueNotifier`**: الأخيرُ يقارن بالمساواة قبل
/// الإبلاغ، فنقرةٌ ثانيةٌ على **نفس** التقرير بعد الرجوع منه تُبتلَع صامتةً.
/// وهي أكثرُ نقرةٍ يتوقّعها المستخدم: فتح، رجوع، فتحٌ ثانٍ.
class PendingPicposReport extends ChangeNotifier {
  PicposReportRequest? _pending;

  /// اطلب فتحَ [reportId] داخلَ [categoryId] — ويُبلَّغ المستمعون دوماً.
  void request({required String categoryId, String? reportId}) {
    _pending = PicposReportRequest(categoryId: categoryId, reportId: reportId);
    notifyListeners();
  }

  /// خُذ الطلبَ المعلَّق وامحُه.
  ///
  /// ⚠️ **استهلاكٌ لا قراءة**: الشاشةُ تُبنى مرّاتٍ (تدويرٌ، إعادةُ بناءِ أب،
  /// عودةٌ من تقرير). وطلبٌ يبقى مكتوباً يُعيد فتحَ نفس التقرير في كلّ بناءٍ
  /// فيُحبَس المستخدمُ فيه ولا يرى مركزَ التقارير.
  PicposReportRequest? take() {
    final out = _pending;
    _pending = null;
    return out;
  }

  /// تصفيرٌ بلا استهلاك — للاختبارات ولتبديل المستخدم.
  void clear() => _pending = null;
}

/// النسخةُ الوحيدة.
final pendingPicposReport = PendingPicposReport();
