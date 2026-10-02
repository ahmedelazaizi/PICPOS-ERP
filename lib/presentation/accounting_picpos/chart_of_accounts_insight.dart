// رصيدُ الحساب وآخرُ حركاته — ما يعرضه لوحُ دليل الحسابات عند الاختيار.
//
// ═══ من أين تأتي الأرقام ═══
//
// من **`getAccountLedger` نفسِه** الذي يقرؤه دفترُ الأستاذ — لا استعلامٍ ثانٍ.
// فالرقمُ في اللوح والرقمُ في الدفتر واحدٌ بالتعريف، والرابطُ «عرض في دفتر
// الأستاذ» يفتح ما يطابق ما رآه المستخدمُ للتوّ. ولذلك:
//
//  • **الحسابُ الأبُ يشمل ذرّيّتَه** — كما في الدفتر وميزان المراجعة؛
//  • **والقيودُ المرحَّلةُ وحدَها** — المسوّداتُ لا تمسّ الرصيد؛
//  • **ونطاقُ الفروع الأمنيُّ يُمرَّر** كما يمرّره الدفتر حرفاً بحرف.
//    ⚠️ إسقاطُه يُظهر لمستخدمٍ محصورٍ حركاتِ فروعٍ لا يملكها.
//
// والمدى: السنةُ الماليّةُ الجارية، فإن لم تُعرَّف فالسنةُ الميلاديّة.
import '../../core/i18n/tr.dart';
import '../../domain/repositories/accounting_repository.dart';

/// حركةٌ واحدةٌ على الحساب — سطرُ قيدٍ مرحَّل.
class AccountMovement {
  const AccountMovement({
    required this.date,
    required this.entryNumber,
    required this.description,
    required this.debit,
    required this.credit,
  });

  final DateTime date;
  final String entryNumber;
  final String description;
  final double debit;
  final double credit;
}

/// ملخّصُ الحساب في المدى.
class AccountInsight {
  const AccountInsight({
    required this.periodLabel,
    required this.from,
    required this.to,
    required this.debit,
    required this.credit,
    required this.movementCount,
    required this.recent,
  });

  /// اسمُ السنة الماليّة — أو رقمُ السنة الميلاديّة عند غيابها.
  final String periodLabel;
  final DateTime from;
  final DateTime to;
  final double debit;
  final double credit;

  /// المدينُ ناقصَ الدائن — نفسُ إشارة الرصيد الجاري في الدفتر.
  double get net => debit - credit;

  final int movementCount;

  /// الأحدثُ أوّلاً.
  final List<AccountMovement> recent;
}

/// نطاقُ الفروع المسموح — `null` ⇒ نطاقٌ كامل. يُمرَّر دالّةً لأنّ قراءتَه
/// تحتاج `ref`، والوحدةُ هنا لا تعرف Riverpod.
typedef AllowedBranchesReader = Future<Set<int>?> Function();

/// عددُ الحركات الأخيرة المعروضة في اللوح.
const int kCoaRecentMovements = 8;

/// يقرأ رصيدَ [accountId] وآخرَ حركاته للسنة الماليّة الجارية.
Future<AccountInsight> loadAccountInsight({
  required IAccountingRepository repo,
  required AllowedBranchesReader allowedBranches,
  required int accountId,
  int recent = kCoaRecentMovements,
  DateTime? now,
}) async {
  final today = now ?? DateTime.now();
  final fy = await repo.getCurrentFiscalYear();
  final from = fy?.startDate ?? DateTime(today.year, 1, 1);
  final to = fy?.endDate ?? DateTime(today.year, 12, 31, 23, 59, 59);

  final rows = await repo.getAccountLedger(
    accountId,
    from,
    to,
    allowedBranchIds: await allowedBranches(),
  );

  final moves = <AccountMovement>[
    for (final r in rows)
      if (r['is_opening'] != true)
        AccountMovement(
          date: r['entry_date'] is DateTime
              ? r['entry_date'] as DateTime
              : from,
          entryNumber: '${r['entry_number'] ?? ''}',
          description: trData('${r['description'] ?? ''}'),
          debit: (r['debit'] as num?)?.toDouble() ?? 0,
          credit: (r['credit'] as num?)?.toDouble() ?? 0,
        ),
  ];

  return AccountInsight(
    periodLabel: (fy?.name.trim().isNotEmpty ?? false)
        ? fy!.name
        : '${from.year}',
    from: from,
    to: to,
    debit: moves.fold(0.0, (s, m) => s + m.debit),
    credit: moves.fold(0.0, (s, m) => s + m.credit),
    movementCount: moves.length,
    recent: moves.reversed.take(recent).toList(),
  );
}
