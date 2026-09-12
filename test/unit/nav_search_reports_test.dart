// بحثُ الشريط يجب أن يبلغ **ما داخلَ** الشاشات — بلاغُ المالك 2026-09-12:
// «خانة البحث فى القائمة لا تظهر البحث عن الشاشات الداخلية مثل شاشات
// التقارير».
//
// ⚠️ **والحقلُ يَعِد بهذا في نصّه**: «ابحث عن شاشة أو ما بداخلها…». وما كان
// «بداخلها» إلّا `kNavSearchKeywords` — كلماتٍ مكتوبةً بيدي، أربعُ كلماتٍ
// لشاشة التقارير كلِّها. وتحتها **ثلاثةَ عشرَ فئةً وستّةٌ وأربعون تقريراً**
// لها عناوينُ حقيقيّةٌ في كتالوجٍ قائم — لا أحدَ يبحث عنها بكلمةِ «تقرير»
// المجرّدة، بل باسم التقرير الذي يريده.
//
// ═══ ولماذا لا يكفي «أضِف كلماتٍ» ═══
//
// لأن الكلماتَ اليدويّةَ مصدرٌ ثانٍ يتخلّف: تقريرٌ يُضاف إلى الكتالوج ولا
// أحدَ يذكر أن يضيف كلمتَه هنا، فيصير غيرَ قابلٍ للبحث بلا أن يُبلَّغ. فهذا
// الملفُّ يشترط أن تُشتَقَّ المداخلُ من **الكتالوج نفسِه**.

import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/core/navigation/screen_id.dart';
import 'package:ural_erp/domain/models/nav_search.dart';
import 'package:ural_erp/presentation/reports_picpos/screens/reports_picpos_screen.dart';
import 'package:ural_erp/presentation/shell/report_category_nav.dart';

final _reportsIndex = ScreenId.reports.navigationIndex;

List<PicposReportCategory> _cats() => buildPicposReportCatalog(
      actions: PicposReportActions.inert,
      eInvoicePlatform: null,
    );

List<NavSearchEntry> _entries() => reportSearchEntries(
      reportsScreenIndex: _reportsIndex,
      categories: _cats(),
    );

void main() {
  test('مرساةٌ — الكتالوجُ يُقرأ غيرَ فارغ', () {
    final cats = _cats();
    expect(cats.length, greaterThanOrEqualTo(10));
    final reports = cats.expand((c) => c.mainReports).length;
    expect(reports, greaterThanOrEqualTo(30),
        reason: 'قُرئ أقلَّ من ٣٠ تقريراً — الفحوصُ تحته تقرأ لا شيء');
  });

  test('وكلُّ فئةٍ وكلُّ تقريرٍ يصير مدخلاً قابلاً للبحث', () {
    final cats = _cats();
    final entries = _entries();
    final labels = entries.map((e) => e.label).toSet();

    for (final c in cats) {
      expect(labels, contains(c.title), reason: 'فئةٌ غيرُ قابلةٍ للبحث: ${c.title}');
      for (final r in c.mainReports) {
        expect(labels, contains(r.title),
            reason: 'تقريرٌ غيرُ قابلٍ للبحث: ${r.title}');
      }
    }
  });

  test('وكلُّها تحمل فهرسَ شاشة التقارير — فالنقرةُ لها وجهة', () {
    for (final e in _entries()) {
      expect(e.index, _reportsIndex, reason: e.label);
    }
  });

  test('ومدخلُ التقرير يحمل معرّفَ فئته ومعرّفَه', () {
    final cats = _cats();
    final cat = cats.first;
    final rep = cat.mainReports.first;

    final hit = _entries().firstWhere((e) => e.label == rep.title);
    expect(hit.reportCategoryId, cat.id);
    expect(hit.reportId, rep.id);
    expect(hit.parentLabel, cat.title,
        reason: 'بلا اسمِ الفئة يظهر «تقرير المبيعات» بلا سياقٍ يميّزه');
  });

  test('ومدخلُ الفئة يحمل معرّفَها بلا معرّفِ تقرير', () {
    final cat = _cats().first;
    final hit = _entries().firstWhere((e) => e.label == cat.title);
    expect(hit.reportCategoryId, cat.id);
    expect(hit.reportId, isNull,
        reason: 'فئةٌ تحمل معرّفَ تقريرٍ تفتح تقريراً لم يُطلَب');
  });

  test('والبحثُ باسم تقريرٍ داخليٍّ يجده — عينُ ما بلّغ عنه المالك', () {
    final cats = _cats();
    final rep = cats.first.mainReports.first;

    // قبل الإصلاح: مداخلُ التنقّل وحدَها، فالاستعلامُ لا يطابق شيئاً.
    final screensOnly = <NavSearchEntry>[
      NavSearchEntry(
        index: _reportsIndex,
        label: 'التقارير',
        group: 'reports',
        keywords: const ['تقرير', 'ارباح', 'مبيعات', 'احصائية'],
      ),
    ];
    expect(searchNavEntries(rep.title, screensOnly), isEmpty,
        reason: 'مرساةٌ: هذا هو السلوكُ المُبلَّغُ عنه');

    final hits = searchNavEntries(rep.title, [...screensOnly, ..._entries()]);
    expect(hits.map((h) => h.label), contains(rep.title));
  });

  test('والترتيبُ يضع الشاشةَ ثمّ الفئةَ ثمّ التقرير', () {
    // «مبيعات» تطابق الشاشةَ (كلمةً) والفئةَ «تقارير المبيعات» (اسماً)
    // وتقاريرَ عدّة. ومن يكتبها يريد الشاشةَ أو الفئةَ قبل تقريرٍ بعينه.
    final entries = [
      const NavSearchEntry(
        index: 17,
        label: 'فواتير المبيعات',
        group: 'sales',
      ),
      ..._entries(),
    ];
    final hits = searchNavEntries('المبيعات', entries);
    expect(hits, isNotEmpty);
    expect(hits.first.kind, NavSearchKind.screen,
        reason: 'تقريرٌ سبق شاشةً تطابق اسمُها');

    final firstCat = hits.indexWhere((h) => h.kind == NavSearchKind.reportCategory);
    final firstRep = hits.indexWhere((h) => h.kind == NavSearchKind.report);
    expect(firstCat, greaterThan(-1));
    expect(firstRep, greaterThan(-1));
    expect(firstCat, lessThan(firstRep),
        reason: 'التقاريرُ سبقت فئاتَها فغرقت الفئةُ في تقاريرها');
  });

  test('ووصفُ التقرير يُبحَث فيه لا عنوانُه وحدَه', () {
    final cats = _cats();
    final rep = cats
        .expand((c) => c.mainReports)
        .firstWhere((r) => r.subtitle.trim().length > 8);
    final word = rep.subtitle.trim().split(RegExp(r'\s+')).first;

    final hits = searchNavEntries(word, _entries());
    expect(hits.map((h) => h.label), contains(rep.title),
        reason: 'الوصفُ «${rep.subtitle}» غيرُ مفهرسٍ — وهو «ما بداخلها»');
  });

  test('ومدخلُ التقرير مطابقةُ اسمٍ لا مطابقةُ كلمة', () {
    final rep = _cats().first.mainReports.first;
    final hits = searchNavEntries(rep.title, _entries());
    final hit = hits.firstWhere((h) => h.label == rep.title);
    expect(hit.matchedInLabel, isTrue);
  });
}
