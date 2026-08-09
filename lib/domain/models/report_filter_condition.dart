import 'dart:convert';

/// مُسترجِعُ عوامل الفلتر لنوعِ حقل — `getFilterOperators` في المستودع.
///
/// مُمرَّرٌ دالةً لا واجهةً كي يبقى النموذجُ بلا تبعيةٍ لطبقة البيانات، ويظلّ
/// مع ذلك مربوطاً بالقائمة **الوحيدة** التي يفرضها المحرِّك.
typedef FilterOperatorLookup = List<Map<String, String>> Function(
    String fieldType);

/// شرطُ تصفيةٍ واحدٌ في حوار منشئ التقارير.
///
/// يُرمَّز إلى الصيغة التي توثّقها السكيما ويقرؤها المحرِّك:
/// `{"field":"price","op":">","value":100}`.
///
/// و[value] نصٌّ دائماً لأن حقولَ الإدخال تعطي نصّاً؛ والتحويلُ إلى النوع
/// الصحيح يقع في [encodeReportFilters] لا في الواجهة — فلو رُمّز `"50"` نصّاً
/// لحقلٍ رقميّ لصارت مقارنةَ نصٍّ برقمٍ في SQLite ولم تطابق شيئاً.
class ReportFilterCondition {
  const ReportFilterCondition({
    required this.field,
    required this.type,
    required this.op,
    this.value = '',
  });

  /// مفتاحُ الحقل من `getAvailableFields` — قائمةٌ مغلقة.
  final String field;

  /// `text` · `number` · `date` · `boolean`.
  final String type;

  /// العاملُ من `getFilterOperators(type)` — قائمةٌ مغلقة.
  final String op;

  /// القيمةُ كما كتبها المستخدم. للتاريخ `yyyy-MM-dd`، وللمنطقيّ
  /// `'true'`/`'false'`.
  final String value;

  /// شرطٌ ابتدائيّ لحقلٍ ما: أوّلُ عاملٍ **معروض** لنوعه.
  ///
  /// أخذُ العامل من القائمة المعروضة لا من ثابتٍ مكتوب هنا يمنع منسدلةً
  /// قيمتُها الابتدائية خارجَ عناصرها (‏`DropdownButtonFormField` يرمي عندها).
  factory ReportFilterCondition.forField(
      Map<String, String> field, FilterOperatorLookup operators) {
    final type = field['type'] ?? 'text';
    final ops = operators(type);
    return ReportFilterCondition(
      field: field['key']!,
      type: type,
      op: ops.isEmpty ? '=' : ops.first['op']!,
      // المنطقيُّ لا حقلَ نصٍّ له بل مفتاح، فله قيمةٌ ابتدائيةٌ صريحة.
      value: type == 'boolean' ? 'false' : '',
    );
  }

  ReportFilterCondition copyWith({String? op, String? value}) =>
      ReportFilterCondition(
        field: field,
        type: type,
        op: op ?? this.op,
        value: value ?? this.value,
      );

  /// هل الشرطُ صالحٌ للحفظ؟
  ///
  /// المحرِّك يرفض التقريرَ **كلَّه** لشرطٍ واحدٍ لا تليق قيمتُه بنوعه، فيُحفظ
  /// تقريرٌ لا يُنتج صفاً واحداً أبداً ولا يقول لماذا. فالمنعُ عند الحفظ.
  bool get isComplete {
    switch (type) {
      case 'boolean':
        return true; // «لا» قيمةٌ صحيحةٌ لا قيمةٌ ناقصة
      case 'number':
        return num.tryParse(value.trim()) != null;
      case 'date':
        return DateTime.tryParse(value.trim()) != null;
      default:
        return value.trim().isNotEmpty;
    }
  }

  /// القيمةُ بنوعها الذي ينتظره المحرِّك.
  Object? get typedValue {
    final v = value.trim();
    switch (type) {
      case 'boolean':
        return v == 'true';
      case 'number':
        return num.tryParse(v);
      default:
        return v; // التاريخُ يمرّ نصّاً ISO — والمحرِّك يقرؤه يوماً
    }
  }

  Map<String, Object?> toJson() =>
      {'field': field, 'op': op, 'value': typedValue};
}

/// يرمّز شروطَ الحوار إلى العمود `filters`.
///
/// `null` لا `'[]'` عند غياب الشروط: العمودُ nullable، وقيمةٌ غيرُ فارغةٍ بلا
/// شرطٍ تُوهم من يقرأ التقريرَ لاحقاً أن له فلتراً.
String? encodeReportFilters(List<ReportFilterCondition> conditions) {
  if (conditions.isEmpty) return null;
  return jsonEncode(conditions.map((c) => c.toJson()).toList());
}
