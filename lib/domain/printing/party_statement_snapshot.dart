// لقطةُ كشف حساب طرفٍ — **بياناتٌ خالصةٌ** يقرؤها القالبُ والراسم.
//
// ── لماذا لقطةٌ لا استعلام ───────────────────────────────────────────────
// نفسُ عقد [ShiftClosingSnapshot]: الأرقامُ تُحسب مرّةً في الشاشة التي تعرضها
// على المستخدم، ثمّ تُمرَّر كما هي إلى الورق. وحسابٌ ثانٍ عند الطباعة يعني
// ورقةً قد تخالف ما رآه المستخدمُ على الشاشة — وهي أسوأُ صور «المعاينة ≠
// الورق»، لأنّها تقع في الأرقام لا في الشكل.
//
// نقيّ: لا `package:pdf` ولا `package:flutter` ولا قاعدةَ بيانات.
library;

/// سطرٌ واحدٌ في الحركة.
class PartyStatementLine {
  final DateTime date;

  /// `INV-2026-1040` — عمودٌ مستقلٌّ لا مُلحَقٌ بالبيان.
  final String documentNumber;

  final String description;
  final double debit;
  final double credit;

  /// الرصيدُ **التراكميُّ** بعد هذا السطر.
  ///
  /// ⚠️ **ولا يُجمع في التذييل**: مجموعُ الأرصدة التراكميّة رقمٌ بلا معنى.
  /// والتذييلُ يأخذ قيمةَ آخر سطرٍ — وهو [PartyStatementSnapshot.closingBalance].
  final double runningBalance;

  const PartyStatementLine({
    required this.date,
    required this.documentNumber,
    required this.description,
    required this.debit,
    required this.credit,
    required this.runningBalance,
  });
}

class PartyStatementSnapshot {
  final String partyName;
  final String partyCode;
  final String? partyTaxNumber;

  /// يقلب تسمياتِ المطبوع: «عميل» ⇄ «مورد»، ويقرّر أيُّ الحقلين يظهر —
  /// المتأخّراتُ للعميل، والأوراقُ القائمةُ للمورد.
  final bool isSupplier;

  final DateTime periodFrom;
  final DateTime periodTo;

  final double creditLimit;
  final double openingBalance;
  final double closingBalance;
  final double totalDebit;
  final double totalCredit;

  /// عميلٌ: ما تجاوز أجلَه.
  final double overdueAmount;

  /// موردٌ: شيكاتٌ صادرةٌ قائمة.
  final double outstandingPapers;

  /// «٠-٣٠» ⇒ مبلغ — تُنسَّق سطراً واحداً في المطبوع.
  final Map<String, double> ageingBuckets;

  final List<PartyStatementLine> lines;

  const PartyStatementSnapshot({
    required this.partyName,
    required this.partyCode,
    required this.periodFrom,
    required this.periodTo,
    required this.openingBalance,
    required this.closingBalance,
    required this.totalDebit,
    required this.totalCredit,
    this.partyTaxNumber,
    this.isSupplier = false,
    this.creditLimit = 0,
    this.overdueAmount = 0,
    this.outstandingPapers = 0,
    this.ageingBuckets = const {},
    this.lines = const [],
  });

  /// صفوفُ الحركة بالمفاتيح التي تسمّيها أعمدةُ الجدول.
  ///
  /// ⚠️ **والمفاتيحُ هي عينُها في `ledgerColumnKeys`**: مفتاحٌ هنا لا يقابله
  /// عمودٌ هناك يعني عموداً يخرج فارغاً على الورقة بلا شكوى.
  List<Map<String, dynamic>> get rowMaps => [
        for (final l in lines)
          {
            'date': '${l.date.day}/${l.date.month}/${l.date.year}',
            'document': l.documentNumber,
            'description': l.description,
            'debit': l.debit,
            'credit': l.credit,
            'balance': l.runningBalance,
          },
      ];
}
