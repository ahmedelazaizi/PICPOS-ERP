import '../../../core/theme/table_status_palette.dart';

/// منطقُ عرض الشبكة الخالص — بلا ودجت ولا مزوّد، ليُختبَر مباشرةً ويُعاد
/// استعمالُه في لوحة P5.
///
/// 🔴 **اختيارُ حالةٍ يُميِّز ولا يُخفي.** المرشِّحُ كان يحذف الطاولاتِ غيرَ
/// المطابقةِ من الشبكة والخريطة، فلا يرى النادلُ الصالةَ كلَّها وحالةَ كلِّ
/// طاولةٍ فيها في آنٍ واحد. الآن القائمةُ المعروضةُ هي القائمةُ كاملةً دائماً،
/// وتُعتَّم غيرُ المطابقة.
abstract final class TablesGridModel {
  /// قيمةُ «لا تمييز» — تطابق `TablesUIState.statusFilter` الافتراضيّة.
  static const String all = 'all';

  /// هل يوجد تمييزٌ فعّال؟ (`null` و`all` يعنيان «لا»).
  static bool hasHighlight(String? statusFilter) =>
      statusFilter != null && statusFilter != all;

  /// الطاولاتُ المعروضة — **كلُّها دائماً**، أيّاً كان [statusFilter].
  static List<T> visibleTables<T>(List<T> tables, String? statusFilter) =>
      tables;

  /// هل تُميَّز هذه الطاولة (حالتُها هي المختارة)؟
  static bool isHighlighted(String tableStatus, String? statusFilter) =>
      hasHighlight(statusFilter) && tableStatus == statusFilter;

  /// هل تُعتَّم هذه الطاولة (يوجد تمييزٌ وهي لا تطابقه)؟
  static bool isDimmed(String tableStatus, String? statusFilter) =>
      hasHighlight(statusFilter) && tableStatus != statusFilter;

  /// شفافيّةُ الطاولة المعتَّمة.
  static const double dimmedOpacity = TableStatusPalette.dimmedOpacity;
}
