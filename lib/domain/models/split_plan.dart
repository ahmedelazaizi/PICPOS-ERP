import 'dart:math' as math;

import '../../core/constants/app_constants.dart';

/// خطأُ خطّةِ تقسيمٍ غيرِ صالحة. رسالتُه تُعرَض للمستخدم كما هي.
class SplitPlanException implements Exception {
  const SplitPlanException(this.message);
  final String message;
  @override
  String toString() => message;
}

enum SplitMode { equal, byAmounts, byItems }

/// تسميةُ حصّةٍ من فهرسها (٠-based).
///
/// موضعٌ واحدٌ للصياغة: `TableOrderPayments.splitLabel` يحفظ هذه السلسلةَ
/// نصّاً، فأيُّ شاشةٍ تريد أن تعرف ما سُوِّي من حصص لا بدّ أن تشتقّ التسميةَ
/// بنفس الطريقة تماماً. نسخُها حرفيّاً في الشاشة كان يعني أن تغييرَ الصياغة
/// هنا يقطع المطابقةَ هناك بلا خطأ ترجمة.
String splitPartLabel(int index) => 'ضيف ${index + 1}';

/// بندُ طلبٍ كما يراه الحساب — بلا أيّ ارتباطٍ بـDrift.
class SplitItem {
  const SplitItem({
    required this.itemId,
    required this.quantity,
    required this.lineTotal,
  });

  final int itemId;
  final double quantity;
  final double lineTotal;
}

/// حصّةُ دافعٍ واحد.
class SplitPart {
  const SplitPart({
    required this.amount,
    required this.label,
    this.itemQuantities = const {},
  });

  final double amount;
  final String label;

  /// `itemId → quantity`. فارغةٌ في التقسيم بالتساوي وبمبلغ، إذ لا حدودَ
  /// صنفيّةً هناك.
  final Map<int, double> itemQuantities;
}

/// خطّةُ تقسيمِ حسابٍ على عدّة دافعين.
///
/// ثابتٌ لا يُستثنى: مجموعُ حصص أيّ خطّةٍ يساوي الإجماليَّ بالضبط بدقّة
/// [AppConstants.decimalPlaces]. الحسابُ كلُّه يجري بوحداتٍ صحيحةٍ مقيسة
/// (×١٠٠٠) لأن جمع `double` يُنتج ٩٩٫٩٩٩٩٩٩٩٩٩٩٩ في القسمة على ٣.
class SplitPlan {
  const SplitPlan._(this.mode, this.parts);

  final SplitMode mode;
  final List<SplitPart> parts;

  static int get _factor =>
      math.pow(10, AppConstants.decimalPlaces).toInt();

  static int _units(double value) => (value * _factor).round();

  /// التقسيمُ بالتساوي — والفرقُ الكسريُّ يُحمَّل على الحصّة الأخيرة.
  factory SplitPlan.equal({required double total, required int ways}) {
    if (ways < 2) {
      throw const SplitPlanException('التقسيم يحتاج دافعَين على الأقل');
    }
    if (total <= 0) {
      throw const SplitPlanException('لا يمكن تقسيمُ إجماليٍّ غيرِ موجب');
    }
    final totalUnits = _units(total);
    final base = totalUnits ~/ ways;
    final remainder = totalUnits - base * ways;
    final parts = <SplitPart>[
      for (var i = 0; i < ways; i++)
        SplitPart(
          amount: (i == ways - 1 ? base + remainder : base) / _factor,
          label: splitPartLabel(i),
        ),
    ];
    return SplitPlan._(SplitMode.equal, parts);
  }

  /// التقسيمُ بمبالغَ يحدّدها الكاشير — يجب أن تجمع الإجماليَّ بالضبط.
  factory SplitPlan.byAmounts({
    required double total,
    required List<double> amounts,
  }) {
    if (amounts.length < 2) {
      throw const SplitPlanException('التقسيم يحتاج دافعَين على الأقل');
    }
    if (amounts.any((a) => a <= 0)) {
      throw const SplitPlanException('كلُّ حصّةٍ يجب أن تكون موجبة');
    }
    final sum = amounts.fold<int>(0, (s, a) => s + _units(a));
    if (sum != _units(total)) {
      throw SplitPlanException(
          'مجموعُ الحصص ${sum / _factor} لا يساوي الإجماليَّ $total');
    }
    final parts = <SplitPart>[
      for (var i = 0; i < amounts.length; i++)
        SplitPart(amount: amounts[i], label: splitPartLabel(i)),
    ];
    return SplitPlan._(SplitMode.byAmounts, parts);
  }

  /// التقسيمُ بالأصناف — كلُّ بندٍ يُسنَد إلى دافع، ولا يُترك بندٌ بلا صاحب.
  factory SplitPlan.byItems({
    required List<SplitItem> items,
    required Map<int, int> assignment,
    required int ways,
  }) {
    if (ways < 2) {
      throw const SplitPlanException('التقسيم يحتاج دافعَين على الأقل');
    }
    final amounts = List<int>.filled(ways, 0);
    final quantities = List<Map<int, double>>.generate(ways, (_) => {});
    for (final item in items) {
      final owner = assignment[item.itemId];
      if (owner == null) {
        throw SplitPlanException('البندُ ${item.itemId} بلا صاحب');
      }
      if (owner < 0 || owner >= ways) {
        throw SplitPlanException('صاحبُ البند ${item.itemId} خارج النطاق');
      }
      amounts[owner] += _units(item.lineTotal);
      quantities[owner][item.itemId] = item.quantity;
    }
    final parts = <SplitPart>[
      for (var i = 0; i < ways; i++)
        SplitPart(
          amount: amounts[i] / _factor,
          label: splitPartLabel(i),
          itemQuantities: quantities[i],
        ),
    ];
    return SplitPlan._(SplitMode.byItems, parts);
  }

  /// هل تُصدر هذه الخطّةُ فاتورةً لكلّ دافع؟
  ///
  /// نعم في التقسيم بالأصناف وحده — هناك حدودٌ صنفيّةٌ فلكلّ فاتورةٍ أصنافُها.
  /// أمّا بالتساوي وبمبلغ فلا حدودَ صنفيّة، وإصدارُ فواتيرَ منفصلةٍ يعني
  /// كميّاتٍ كسريّةً على إيصال الزبون («٠٫٢٥ بطاطا») تبدو عطلاً — فالمبيعةُ
  /// واحدةٌ والدافعون عدّة.
  bool get producesSeparateInvoices => mode == SplitMode.byItems;
}
