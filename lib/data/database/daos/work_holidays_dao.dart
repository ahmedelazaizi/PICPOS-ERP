part of '../database.dart';

// ═══════════════════════════════════════════════════════════════════════════
// WORK HOLIDAYS — تقويمُ العطلات وأيامُ العمل
// ═══════════════════════════════════════════════════════════════════════════

/// H6 — شرطُ حصر عطلات العمل بالفرع، مطابقٌ لـ`_employeeBranchScope` في
/// `hr_extensions.dart` بالحرف: عطلةٌ بلا فرع (`branch_id IS NULL`) عامّةٌ
/// وتبقى مرئيةً لكل نطاق، ومجموعةٌ فارغة تعني صفرَ صفوف لا «بلا حصر».
Expression<bool> _workHolidayBranchScope(
        $WorkHolidaysTable h, Set<int> ids) =>
    ids.isEmpty
        ? const Constant(false)
        : h.branchId.isIn(ids.toList()) | h.branchId.isNull();

extension WorkHolidaysDao on AppDatabase {
  /// كلُّ عطلات العمل المعرَّفة — محصورةٌ بفروع المستخدم (H6).
  Future<List<WorkHoliday>> getWorkHolidays({
    required Set<int>? allowedBranchIds,
  }) {
    final q = select(workHolidays)
      ..orderBy([(h) => OrderingTerm.asc(h.name)]);
    if (allowedBranchIds != null) {
      q.where((h) => _workHolidayBranchScope(h, allowedBranchIds));
    }
    return q.get();
  }

  /// يحذف عطلةً بمعرّفها.
  Future<void> deleteWorkHoliday(int id) =>
      (delete(workHolidays)..where((h) => h.id.equals(id))).go();

  /// أيامُ العطلة في شهرٍ لفرعٍ ما — تواريخُ بلا وقت.
  ///
  /// **مجموعةٌ لا قائمة**: عيدٌ يقع على عطلةٍ أسبوعية يجب أن يُعدّ يوماً
  /// واحداً، وإلا نقص من المقام يومٌ غيرُ موجودٍ فارتفع أجرُ الساعة زوراً.
  ///
  /// والدمجُ تراكميّ: صفوفُ الفرع **مضافةً إلى** صفوف `branchId` المعدوم.
  Future<Set<DateTime>> holidaysInMonth(
    int year,
    int month, {
    required int? branchId,
  }) async {
    final rows = await (select(workHolidays)
          ..where((h) => branchId == null
              ? h.branchId.isNull()
              : h.branchId.isNull() | h.branchId.equals(branchId)))
        .get();

    final last = DateTime(year, month + 1, 0).day;
    final out = <DateTime>{};
    for (final r in rows) {
      if (r.weekday != null) {
        for (var d = 1; d <= last; d++) {
          final day = DateTime(year, month, d);
          if (day.weekday == r.weekday) out.add(day);
        }
      } else if (r.date != null) {
        final d = r.date!;
        if (d.year == year && d.month == month) {
          out.add(DateTime(d.year, d.month, d.day));
        }
      }
    }
    return out;
  }

  /// أيامُ العمل = أيامُ الشهر التقويمية − العطلات.
  Future<int> workingDaysInMonth(
    int year,
    int month, {
    required int? branchId,
  }) async {
    final last = DateTime(year, month + 1, 0).day;
    final holidays = await holidaysInMonth(year, month, branchId: branchId);
    return last - holidays.length;
  }

  /// يضيف عطلةً بعد **تحقّقٍ في الكود** لا في السكيما وحدها.
  ///
  /// قيدُ `CHECK` موجودٌ على SQLite، لكنه **غائبٌ عن تنصيبات PostgreSQL
  /// القائمة**: `onUpgrade` متجاوَزٌ هناك، و`_ensurePostgresSchemaParity` —
  /// الآليةُ الوحيدة لإيصال جدولٍ جديد لخادمٍ قائم — لا تكتب
  /// `customConstraints`. فصفٌّ يحمل الشكلين يمرّ بصمت. والتحقّقُ هنا يحمي
  /// المحرّكَين معاً.
  Future<int> addWorkHoliday({
    required String name,
    required int? weekday,
    required DateTime? date,
    required int? branchId,
  }) async {
    if ((weekday == null) == (date == null)) {
      throw ArgumentError(
          'العطلةُ إمّا يومٌ أسبوعيٌّ متكرّر وإمّا تاريخٌ بعينه — لا الاثنان '
          'ولا لا شيء');
    }
    if (weekday != null && (weekday < 1 || weekday > 7)) {
      throw ArgumentError(
          'يومُ الأسبوع خارج المدى ١–٧ (اصطلاحُ DateTime.weekday): $weekday');
    }
    if (name.trim().isEmpty) {
      throw ArgumentError('اسمُ العطلة مطلوب');
    }
    return into(workHolidays).insert(WorkHolidaysCompanion.insert(
      name: name.trim(),
      weekday: Value(weekday),
      date: Value(date),
      branchId: Value(branchId),
    ));
  }
}
