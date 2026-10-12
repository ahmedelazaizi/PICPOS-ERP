part of 'drift_accounting_repository.dart';

extension DriftAccountingRepositoryManualEntry on DriftAccountingRepository {
  /// سجلُّ النشاط للقيد اليدويّ — قرارُ المالك 2026-09-18.
  ///
  /// ═══ 🔴 ولماذا هنا لا في الحوار ═══
  ///
  /// `logJournalEntry` كانت مكتوبةً في `log_financial.dart` **بلا منادٍ
  /// واحد**، فسجلُّ النشاط فارغٌ تماماً من القيود — وقرارُ المالك يجعله
  /// مصدرَ «المنشئ».
  ///
  /// ووصلُها في حوارِ الإنشاء كان يترك **كلَّ منادٍ آخر** بلا سجلّ، ويجعل
  /// وصلَها غيرَ قابلٍ للقياس إلّا بشجرةِ ودجت. وهنا تُقاس بصفٍّ في جدول.
  ///
  /// ⚠️ **و`createdBy == null` لا يُسجَّل**: الترحيلُ الآليُّ يمرّ من هنا
  /// أيضاً (فواتيرُ وسنداتٌ وإهلاك)، ولا منشئَ بشريّاً له — وتسجيلُه باسمٍ
  /// مخترَعٍ يملأ السجلَّ بضجيجٍ يُخفي ما يفعله البشر.
  ///
  /// ⚠️ **والإخفاقُ مبتلَعٌ عمداً**: القيدُ رُحِّل فعلاً وحُرِّكت الأرصدة.
  /// ورميٌ بعده يُظهر خطأً على عمليّةٍ نجحت، فيعيدها المستخدمُ — ويُنشئ
  /// قيداً ثانياً. فالسجلُّ أثرٌ لا شرط.
  Future<void> _logManualEntry(
    int entryId,
    int? createdBy,
    List<JournalLine> lines,
    String description,
  ) async {
    if (createdBy == null) return;
    try {
      final user = await _db.getUserById(createdBy);
      if (user == null) return;
      final totalDebit = lines.fold<double>(0, (s, l) => s + l.debit);
      await ActivityLogger(_db).logJournalEntry(
        createdBy,
        user.user.displayName,
        entryId,
        totalDebit,
        description,
      );
    } catch (e) {
      debugPrint('[DriftAccountingRepository] activity log failed '
          '(non-fatal): $e');
    }
  }

  /// Read the branch this client/mirror is bound to, written by the setup
  /// wizard at `client_branch_id`. Returns null if missing (fresh install
  /// or not yet configured) so the DAO's `branchId ?? 1` fallback still
  /// applies — never throws, never blocks the JE write.
  Future<int?> _resolveClientBranchId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getInt('client_branch_id');
    } catch (e) {
      debugPrint('[DriftAccountingRepository] '
          'client_branch_id lookup failed (non-fatal): $e');
      return null;
    }
  }


}
