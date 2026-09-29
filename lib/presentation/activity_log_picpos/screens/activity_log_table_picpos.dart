// جدولُ سجل العمليات على التصميم — ستُّ خلايا: أيقونةٌ ملوّنة، الإجراءُ فوق
// الفرع، المستندُ فوق مرجعه، التفاصيل، المستخدمُ فوق دوره، الوقتُ فوق التاريخ.
//
// ⚠️ **يحلّ محلَّ `Card` + `ListTile` في عرض «القائمة» وحدَه.** العرضُ
// الزمنيُّ (`ActivityTimeline`) ودّجتٌ مشتركةٌ مع UralCash — لا تُلمس.
// و`buildLogItem` يبقى: `ActivityTimeline` لا يستعمله، لكنّ حذفَ دالّةٍ لأنّ
// عرضاً واحداً استغنى عنها كان يوسّع الفرقَ عن الأصل بلا داعٍ.
//
// ولا يعرف هذا الملفُّ القاعدةَ: يستقبل [PicPosActivityRow] الخالص +
// أيقونةً ولوناً محسوبَين في المستدعي عبر `actionVisual`.
part of 'activity_log_picpos_screen.dart';

/// أعمدةُ الجدول — نفسُ نِسَبِ التصميم
/// (`38px 1.35fr 1.3fr 2.1fr 1.15fr 116px`).
///
/// تُنفَّذ بـ`Row` وأوزانٍ لا بـ`DataTable`: `DataTable` في هذا المستودع محكومٌ
/// بـ`dataTableTheme` الذي يقرن نصّاً **أبيضَ** بخلفيّةِ `primaryDark` في
/// الوضعَين معاً — وهو ما جعل خمسةَ عشرَ موضعَ `headingRowColor` معطوباً في
/// جلسةٍ سابقة. فبناءُ الرأس يدويّاً يتجنّب العقدَ الخفيَّ من أصله.
class _ActivityCellWidths {
  const _ActivityCellWidths();

  static const double icon = 38;
  static const double time = 116;
  static const int action = 135; // 1.35fr
  static const int entity = 130; // 1.30fr
  static const int detail = 210; // 2.10fr
  static const int user = 115; // 1.15fr
}

/// صفٌّ واحد.
class PicPosActivityTableRow extends StatelessWidget {
  const PicPosActivityTableRow({
    super.key,
    required this.row,
    required this.icon,
    required this.tint,
    required this.onTap,
  });

  final PicPosActivityRow row;
  final IconData icon;
  final Color tint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = picposMuted(context);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: theme.dividerColor)),
          ),
          child: Row(
            children: [
              SizedBox(
                width: _ActivityCellWidths.icon,
                child: Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: tint.withValues(alpha: 31 / 255),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(icon, size: 15, color: tint),
                ),
              ),
              const SizedBox(width: 12),
              _twoLine(
                flex: _ActivityCellWidths.action,
                top: row.actionLabel,
                bottom: row.branchLabel,
                topColor: tint,
                muted: muted,
              ),
              const SizedBox(width: 12),
              _twoLine(
                flex: _ActivityCellWidths.entity,
                top: row.entityLabel,
                bottom: row.refLabel,
                topColor: theme.textTheme.bodyLarge?.color,
                bottomColor: AppColors.primary,
                bottomTabular: true,
                muted: muted,
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: _ActivityCellWidths.detail,
                child: Text(
                  row.detailLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: theme.textTheme.bodyMedium?.color,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              _twoLine(
                flex: _ActivityCellWidths.user,
                top: row.userName,
                bottom: row.roleLabel,
                topColor: theme.textTheme.bodyLarge?.color,
                muted: muted,
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: _ActivityCellWidths.time,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      row.timeLabel,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: muted,
                        fontFeatures: const [ui.FontFeature.tabularFigures()],
                      ),
                    ),
                    Text(
                      row.dateLabel,
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        color: muted,
                        fontFeatures: const [ui.FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// خليّةٌ بسطرَين — والسطرُ السفليُّ **يختفي تماماً حين يكون فارغاً** بدل
  /// أن يترك فراغاً يوحي بقيمةٍ محذوفة.
  Widget _twoLine({
    required int flex,
    required String top,
    required String bottom,
    required Color muted,
    Color? topColor,
    Color? bottomColor,
    bool bottomTabular = false,
  }) {
    return Expanded(
      flex: flex,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            top,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              color: topColor,
            ),
          ),
          if (bottom.isNotEmpty)
            Text(
              bottom,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                color: bottomColor ?? muted,
                fontFeatures: bottomTabular
                    ? const [ui.FontFeature.tabularFigures()]
                    : null,
              ),
            ),
        ],
      ),
    );
  }
}

/// رأسُ الجدول.
class PicPosActivityTableHeader extends StatelessWidget {
  const PicPosActivityTableHeader({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = picposMuted(context);
    Widget cell(String text, int flex) => Expanded(
          flex: flex,
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: muted,
            ),
          ),
        );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        border: Border(bottom: BorderSide(color: theme.dividerColor)),
      ),
      child: Row(
        children: [
          const SizedBox(width: _ActivityCellWidths.icon),
          const SizedBox(width: 12),
          cell(tr('الإجراء'), _ActivityCellWidths.action),
          const SizedBox(width: 12),
          cell(tr('المستند / النوع'), _ActivityCellWidths.entity),
          const SizedBox(width: 12),
          cell(tr('التفاصيل'), _ActivityCellWidths.detail),
          const SizedBox(width: 12),
          cell(tr('المستخدم'), _ActivityCellWidths.user),
          const SizedBox(width: 12),
          SizedBox(
            width: _ActivityCellWidths.time,
            child: Text(
              tr('الوقت'),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: muted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// الجدولُ كاملاً داخل بطاقةٍ واحدة.
class PicPosActivityTable extends StatelessWidget {
  const PicPosActivityTable({
    super.key,
    required this.rows,
    required this.visualFor,
    required this.onRowTap,
  });

  final List<PicPosActivityRow> rows;

  /// الأيقونةُ واللونُ لكلّ صفّ — يُمرَّران لأن خريطتَهما تعيش في mixin
  /// الشاشة (‏`actionVisual`)، وهذا الملفُّ عرضٌ لا يعرف أكوادَ الإجراءات.
  final ({IconData icon, Color color}) Function(PicPosActivityRow) visualFor;
  final void Function(PicPosActivityRow) onRowTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.cardColor,
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(14),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          const PicPosActivityTableHeader(),
          Expanded(
            child: rows.isEmpty
                ?  PicPosEmptyState(
                    icon: PhosphorIconsBold.clipboardText,
                    title: tr('لا توجد عمليات مسجلة'),
                    hint: tr('جرّب توسيع المدى أو مسح الفلاتر.'),
                  )
                : ListView.builder(
                    itemCount: rows.length,
                    itemBuilder: (context, i) {
                      final v = visualFor(rows[i]);
                      return PicPosActivityTableRow(
                        key: ValueKey(rows[i].id),
                        row: rows[i],
                        icon: v.icon,
                        tint: v.color,
                        onTap: () => onRowTap(rows[i]),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
