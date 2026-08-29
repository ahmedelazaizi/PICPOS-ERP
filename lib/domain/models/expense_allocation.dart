// توزيعُ مصروفٍ على أوامر التصنيع — حسابٌ خالصٌ يُقاس وحدَه.
//
// ═══ الأساسان، ولماذا كلاهما مطلوب ═══
//
// `DLGS.allocate` في `PicPos Operating Expenses.dc.html` يعطي أساسَين:
//
// • **بالمعدل × الكمية** — كلُّ أمرٍ يأخذ `المعدل × كمّيّتَه`. أمينٌ لمعدّل
//   الفئة، لكنّه قد يترك جزءاً من المصروف **غيرَ محمَّل** (‏أو يتجاوزه).
// • **توزيع كامل المبلغ** — المصروفُ كلُّه يُوزَّع نسبةً للكمّيّات. لا يترك
//   باقياً، لكنّه يجعل أوامرَ الدفعة تحمل نصيبَ أوامرَ أخرى.
//
// والاختيارُ بينهما قرارُ محاسبة تكاليفٍ لا تفصيلُ واجهة، فيُحسَب الأثرُ
// ويُعرَض قبل الحفظ.
//
// ═══ 🔴 وفرقُ التقريب يُحمَّل فعلاً لا في النصّ وحدَه ═══
//
// قسمةُ مبلغٍ على كمّيّاتٍ تُنتج كسوراً. وتقريبُ كلِّ سطرٍ على حدة يجعل
// **مجموعَ الأسطر يخالف المبلغ** بقروشٍ — وهي تظهر في الأستاذ فرقاً لا يُفسَّر.
// فالفرقُ يُحمَّل على **أكبر سطر** (‏أقلُّ أثرٍ نسبيٍّ عليه)، ويُثبَّت أنّ
// المجموعَ يساوي المبلغَ بالضبط.
library;

/// أساسُ التوزيع.
enum AllocationBasis {
  /// المعدل × كمّيّة الأمر — قد يترك باقياً.
  byRate,

  /// المبلغُ كلُّه نسبةً للكمّيّات — بلا باقٍ.
  fullAmount,
}

/// نصيبُ أمرٍ واحدٍ من المصروف.
class AllocationLine {
  const AllocationLine({
    required this.orderId,
    required this.quantity,
    required this.amount,
  });

  final int orderId;
  final double quantity;
  final double amount;
}

/// حصيلةُ الحساب.
class AllocationPlan {
  const AllocationPlan({required this.lines, required this.expenseAmount});

  final List<AllocationLine> lines;
  final double expenseAmount;

  double get allocated =>
      lines.fold<double>(0, (s, l) => s + l.amount);

  /// ما بقي غيرَ محمَّل — **سالبٌ يعني تجاوزاً**، لا صفراً.
  ///
  /// ⚠️ التصميمُ يسمّيه «غير محمَّل» ويفترضه موجباً. والمعدّلُ الأعلى من
  /// الواقع يُنتج تحميلاً يفوق المصروف، وابتلاعُ السالب يُخفي ذلك.
  double get unallocated => expenseAmount - allocated;

  bool get isExact => unallocated.abs() < 0.005;
}

/// يوزّع [expenseAmount] على [quantities] (‏مفتاحُها معرِّفُ الأمر).
///
/// [rate] يُقرأ في [AllocationBasis.byRate] وحدَه.
///
/// ⚠️ **الأوامرُ بكمّيّةٍ صفريّةٍ تأخذ صفراً** في الأساسَين: القسمةُ على
/// مجموعٍ صفريٍّ تُنتج `NaN`، وأمرٌ لم يُنتج شيئاً لا يحمل تكلفةَ وحدة.
AllocationPlan allocateExpense({
  required double expenseAmount,
  required Map<int, double> quantities,
  required AllocationBasis basis,
  double rate = 0,
}) {
  final ids = quantities.keys.toList();
  if (ids.isEmpty) {
    return AllocationPlan(lines: const [], expenseAmount: expenseAmount);
  }

  double round2(double v) => (v * 100).roundToDouble() / 100;

  if (basis == AllocationBasis.byRate) {
    return AllocationPlan(
      lines: [
        for (final id in ids)
          AllocationLine(
            orderId: id,
            quantity: quantities[id]!,
            amount: round2(rate * quantities[id]!),
          ),
      ],
      expenseAmount: expenseAmount,
    );
  }

  final totalQty = quantities.values.fold<double>(0, (s, q) => s + q);
  if (totalQty <= 0) {
    // كلُّ الأوامر بلا كمّيّة ⇒ لا أساسَ للنسبة، فلا تحميل.
    return AllocationPlan(
      lines: [
        for (final id in ids)
          AllocationLine(orderId: id, quantity: quantities[id]!, amount: 0),
      ],
      expenseAmount: expenseAmount,
    );
  }

  final lines = <AllocationLine>[
    for (final id in ids)
      AllocationLine(
        orderId: id,
        quantity: quantities[id]!,
        amount: round2(expenseAmount * quantities[id]! / totalQty),
      ),
  ];

  // 🔴 فرقُ التقريب — يُحمَّل على أكبر سطرٍ فعلاً. راجع تعليقَ الرأس.
  final drift = round2(expenseAmount - lines.fold<double>(0, (s, l) => s + l.amount));
  if (drift != 0) {
    var biggest = 0;
    for (var i = 1; i < lines.length; i++) {
      if (lines[i].amount > lines[biggest].amount) biggest = i;
    }
    lines[biggest] = AllocationLine(
      orderId: lines[biggest].orderId,
      quantity: lines[biggest].quantity,
      amount: round2(lines[biggest].amount + drift),
    );
  }

  return AllocationPlan(lines: lines, expenseAmount: expenseAmount);
}
