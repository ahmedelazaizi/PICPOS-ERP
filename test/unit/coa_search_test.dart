// بحثُ دليل الحسابات — الوحدةُ الخالصة (`chart_of_accounts_search.dart`).
import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/core/i18n/tr.dart';
import 'package:picpos_erp/presentation/accounting_picpos/chart_of_accounts_search.dart';

void main() {
  const rows = <CoaSearchRow>[
    (id: 1, parentId: null, code: '1000', name: 'الأصول'),
    (id: 2, parentId: 1, code: '1100', name: 'النقدية'),
    (id: 3, parentId: 2, code: '1101', name: 'الصندوق الرئيسي'),
    (id: 4, parentId: null, code: '4100', name: 'المبيعات'),
  ];

  tearDown(() => I18nCatalog.setLocale(const Locale('ar', 'EG')));

  test('المطابقُ وأسلافُه ظاهرون، والأسلافُ وحدَهم يُوسَّعون', () {
    final r = coaSearch(rows, '1101');
    expect(r.matchIds, {3});
    expect(r.ancestorIds, {1, 2});
    expect(r.visibleIds, {1, 2, 3});
    expect(r.bestMatchId, 3);
  });

  test('أقربُ مطابقة: الرمزُ التامّ يسبق ما يبدأ به', () {
    // «1100» يطابق 1100 تماماً، و«110» يبدأ به 1100 و1101.
    expect(coaSearch(rows, '1100').bestMatchId, 2);
    expect(coaSearch(rows, '110').bestMatchId, 2);
  });

  test('الاسمُ المخزَّنُ واسمُ العرض (trData) كلاهما يطابق', () {
    expect(coaSearch(rows, 'الصندوق').matchIds, {3});
    I18nCatalog.setCatalog({'الصندوق الرئيسي': 'Main Cash'});
    I18nCatalog.setLocale(const Locale('en'));
    expect(coaSearch(rows, 'main CASH').matchIds, {3});
  });

  test('نصٌّ فارغٌ يُطابق الكلَّ ولا يختار', () {
    final r = coaSearch(rows, '  ');
    expect(r.matchIds, {1, 2, 3, 4});
    expect(r.bestMatchId, isNull);
  });

  test('🔴 بياناتٌ تالفةٌ بحلقة آباء لا تُجمّد البحث', () {
    const cyclic = <CoaSearchRow>[
      (id: 1, parentId: 2, code: '1', name: 'a'),
      (id: 2, parentId: 1, code: '2', name: 'b'),
    ];
    final r = coaSearch(cyclic, '1');
    expect(r.matchIds, {1});
    expect(r.ancestorIds, {2});
  });
}
