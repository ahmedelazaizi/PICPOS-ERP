// إعادةُ ترقيم عناصر القالب لا تنفي ما لا تعرفه.
//
// ── فئةُ العطب ────────────────────────────────────────────────────────────
// `_recalcSortOrder` في محرّر الأقسام يرقّم العناصرَ بمطابقة
// `e.content == field.variableContent`. وعناصرُ القالب المبذور فيها ما لا
// يطابق أيَّ حقل:
//   • الفواصلُ `{'type':'line'}` تُبذر بمحتوىً فارغ، ولا حقلَ لها أصلاً.
//   • نصُّ التذييل يُبذر بمحتواه العربيّ «شكراً لتعاملكم معنا»، بينما حقلُ
//     المحرّر `variableContent: 'footer_text'` — فلا يتطابقان.
// فهذه تبقى على `sortOrder` المبذور بينما يُعاد ترقيمُ جيرانها.
//
// وما كان يمرّ صامتاً صار قاتلاً بعد قرار الخيار (ب): `sortOrder` هو الحَكَم.
// فالقالبُ الحراريُّ المبذور — فواصلُه على 4 · 11 · 18 ونصُّ الشكر على 20 —
// ينقلب عند **أوّل حفظٍ** من المحرّر: الشكرُ يطفو فوق جدول الأصناف، والفواصلُ
// تتناثر داخل كتلة العميل.
//
// والعلاجُ ليس حذفَها ولا دفعَها للذيل، بل **إبقاؤها ملتصقةً بما تسبقه اليوم**:
// الفاصلُ الذي يلي «هاتف الشركة» يظلّ يليه مهما تحرّكت الأقسام.

import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/domain/models/invoice_template_layout.dart';

typedef _El = ({int id, String? content, int sortOrder});

List<int> orderedIds(Map<int, int> ranks) {
  final ids = ranks.keys.toList()
    ..sort((a, b) => ranks[a]!.compareTo(ranks[b]!));
  return ids;
}

void main() {
  test('الحقولُ المعروفةُ تأخذ ترتيبَ الشاشة', () {
    final ranks = resequenceTemplateElements(
      elements: const <_El>[
        (id: 10, content: 'total_amount', sortOrder: 0),
        (id: 11, content: 'company_name', sortOrder: 1),
      ],
      // الشاشةُ: اسمُ الشركة أوّلاً ثم الإجمالي
      screenRank: const {'company_name': 0, 'total_amount': 1},
    );

    expect(orderedIds(ranks), [11, 10]);
  });

  test('الفاصلُ اليتيمُ يظلّ ملتصقاً بما يسبقه', () {
    // البذرة: company_phone(3) ← line(4) ← invoice_number(5)
    // والشاشةُ تُبقيها على ترتيبها.
    final ranks = resequenceTemplateElements(
      elements: const <_El>[
        (id: 1, content: 'company_phone', sortOrder: 3),
        (id: 2, content: null, sortOrder: 4), // فاصل
        (id: 3, content: 'invoice_number', sortOrder: 5),
      ],
      screenRank: const {'company_phone': 0, 'invoice_number': 1},
    );

    expect(orderedIds(ranks), [1, 2, 3]);
  });

  test('نصُّ التذييل اليتيمُ لا يطفو فوق ما بعده', () {
    // العطبُ الحيّ: الشكرُ (20) بينما الحقولُ المعروفةُ تُرقَّم 0..N،
    // فكان يهبط إلى وسط الإيصال. موضعُه: بعد qr_code كما بُذر.
    final ranks = resequenceTemplateElements(
      elements: const <_El>[
        (id: 1, content: 'total_amount', sortOrder: 15),
        (id: 2, content: 'qr_code', sortOrder: 19),
        (id: 3, content: 'شكراً لتعاملكم معنا', sortOrder: 20),
      ],
      screenRank: const {'total_amount': 30, 'qr_code': 55},
    );

    expect(orderedIds(ranks), [1, 2, 3]);
  });

  test('يتيمٌ يسبق كلَّ معروفٍ يبقى في الرأس', () {
    final ranks = resequenceTemplateElements(
      elements: const <_El>[
        (id: 1, content: null, sortOrder: 0), // فاصلٌ في الرأس
        (id: 2, content: 'company_name', sortOrder: 1),
      ],
      screenRank: const {'company_name': 0},
    );

    expect(orderedIds(ranks), [1, 2]);
  });

  test('يتامى متتالياتٌ تحفظ ترتيبَها بينها', () {
    final ranks = resequenceTemplateElements(
      elements: const <_El>[
        (id: 1, content: 'company_name', sortOrder: 0),
        (id: 2, content: null, sortOrder: 1),
        (id: 3, content: 'نصٌّ حرّ', sortOrder: 2),
        (id: 4, content: 'total_amount', sortOrder: 3),
      ],
      screenRank: const {'company_name': 0, 'total_amount': 1},
    );

    expect(orderedIds(ranks), [1, 2, 3, 4]);
  });

  test('الناتجُ متسلسلٌ من الصفر بلا فجوات', () {
    final ranks = resequenceTemplateElements(
      elements: const <_El>[
        (id: 1, content: 'company_name', sortOrder: 0),
        (id: 2, content: null, sortOrder: 4),
        (id: 3, content: 'total_amount', sortOrder: 12),
      ],
      screenRank: const {'company_name': 0, 'total_amount': 9},
    );

    expect(ranks.values.toList()..sort(), [0, 1, 2]);
  });

  test('عنصرٌ محتواه معروفٌ لكنّ الشاشةَ لا تعرضه يُعامَل يتيماً', () {
    // حقلٌ حُذف من المحرّر ولم يُحذف عنصرُه — لا يُنفى للذيل.
    final ranks = resequenceTemplateElements(
      elements: const <_El>[
        (id: 1, content: 'company_name', sortOrder: 0),
        (id: 2, content: 'waiter_name', sortOrder: 1),
        (id: 3, content: 'total_amount', sortOrder: 2),
      ],
      screenRank: const {'company_name': 0, 'total_amount': 1},
    );

    expect(orderedIds(ranks), [1, 2, 3]);
  });
}
