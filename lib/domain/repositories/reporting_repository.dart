import '../../data/database/database.dart';
import 'sales_reporting_repository.dart';
import 'purchase_reporting_repository.dart';
import 'treasury_reporting_repository.dart';
import 'inventory_reporting_repository.dart';

export 'sales_reporting_repository.dart';
export 'purchase_reporting_repository.dart';
export 'treasury_reporting_repository.dart';
export 'inventory_reporting_repository.dart';

/// Unified reporting repository — composes all domain-specific reporting interfaces.
///
/// Consumers can depend on the full [IReportingRepository] or narrow to
/// [ISalesReportingRepository], [IPurchaseReportingRepository], etc. for
/// better separation of concerns.
abstract class IReportingRepository
    implements
        ISalesReportingRepository,
        IPurchaseReportingRepository,
        ITreasuryReportingRepository,
        IInventoryReportingRepository {
  /// Watch all system users (admin utility)
  Stream<List<UserWithRole>> watchAllUsers();

  /// لقطةُ المستخدمين للتقارير — بلا مجرى.
  Future<List<UserWithRole>> getAllUsersWithRoles();

  // ── Custom Reports ────────────────────────────────────────────────────

  /// Get all custom reports
  Future<List<CustomReportData>> getCustomReports();

  /// Create a new custom report
  ///
  /// [filters] — شروطُ التصفية بالصيغة المهيكلة التي توثّقها السكيما:
  /// `[{"field":"price","op":">","value":100}]`. اسمُ الحقل من
  /// [getAvailableFields] والعاملُ من [getFilterOperators] — قائمتان مغلقتان،
  /// والقيمةُ تُربَط معاملاً داخل المحرِّك فلا تصل الاستعلامَ نصّاً.
  Future<int> createCustomReport({
    required String name,
    required String sourceEntity,
    required String columns,
    String? filters,
  });

  /// Delete a custom report
  Future<void> deleteCustomReport(int id);

  /// Execute a custom report and get results
  /// [allowedBranchIds] — null = وصول كامل. كيان مالوش فلتر حصر مدعوم
  /// بيرجّع فاضي لمستخدم محصور بدل ما يتساب يسرّب.
  /// [onRowLimitReached] يُنادى إذا كانت البيانات أكثر من السقف ⇒ الناتجُ
  /// **مقتطع**. تمريرُه ليس تحسيناً: بلا إبلاغٍ يقرأ المستخدم تقريراً ناقصاً
  /// كأنه كامل ويجمع أعمدته.
  Future<List<Map<String, dynamic>>> executeReport(int reportId,
      {Set<int>? allowedBranchIds, void Function(int limit)? onRowLimitReached});

  /// Get fields available for a custom report entity
  List<Map<String, String>> getAvailableFields(String entity);

  /// عواملُ الفلتر المتاحة لنوعِ حقل (`text`/`number`/`date`/`boolean`).
  /// تبني الواجهةُ المنسدلةَ منها كي لا تعرض عاملاً يرفضه المحرِّك.
  List<Map<String, String>> getFilterOperators(String fieldType);
}
