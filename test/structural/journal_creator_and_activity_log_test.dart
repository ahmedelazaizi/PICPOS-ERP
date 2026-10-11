// حارسُ العقد: «المنشئ» يُعرَض، و**سجلُّ النشاط يُكتَب فعلاً**.
//
// ═══ قرارُ المالك 2026-09-18 وما قاسته الشيفرة ═══
//
// القرار: «المنشئ» يُشتقُّ من **سجلّ النشاط**. وقياسُ الشيفرة كشف أنّ
// المصدرَ المفترضَ **فارغ**:
//
// 🔴 **`logJournalEntry` مكتوبةٌ في `log_financial.dart` بلا منادٍ واحد.**
// فالسجلُّ لا يحوي قيداً واحداً، والاشتقاقُ منه كان سيعطي «—» أبداً — ميزةٌ
// تُبنى وتُعرَض ولا تعمل يوماً.
//
// وقرارُ المالك 2026-09-19: **الاثنان معاً** — يُعرَض «المنشئ» من
// `journal_entries.created_by` (وهو الحقيقةُ المخزَّنةُ على الصفّ نفسِه
// ويقرؤها ضابطُ «لا يعتمد القيدَ منشئُه»)، **ويُوصَل كاتبُ السجلّ** فيصير
// للقرار مصدرُه.
//
// ⚠️ **والسجلُّ أثرٌ لا شرط**: إخفاقُه لا يُفشِل الحفظ. القيدُ رُحِّل فعلاً
// وحُرِّكت الأرصدة؛ ورميٌ بعده يُظهر خطأً على عمليّةٍ نجحت فيعيدها
// المستخدمُ — ويُنشئ قيداً ثانياً.

import 'package:flutter_test/flutter_test.dart';

import '../helpers/database_source.dart';

/// نصُّ الملفّ بلا أسطر التعليق وبلا `\r` — أغلبُ الملفّات هنا CRLF.
String _code(String path) => [
      for (final line in readSourceMerged(path).split('\n'))
        if (!line.trimLeft().startsWith('//')) line.replaceAll('\r', ''),
    ].join('\n');

const _dialogPath =
    'lib/presentation/accounting_picpos/journal_entries_picpos_create_dialog.dart';
const _screenPath =
    'lib/presentation/accounting_picpos/journal_entries_picpos_screen.dart';
const _loggerPath = 'lib/services/logging/log_financial.dart';
const _dbPath = 'lib/data/database/database.dart';
const _repoIfacePath = 'lib/domain/repositories/accounting_repository.dart';
const _repoImplPath =
    'lib/data/repositories/drift_accounting_repository.dart';

String _body(String code, String start, String end) {
  final at = code.indexOf(start);
  expect(at, greaterThan(0), reason: 'لم أجد `$start`');
  final to = code.indexOf(end, at);
  expect(to, greaterThan(at), reason: 'لم أجد نهايةَ `$start`');
  return code.substring(at, to);
}

void main() {
  test('‏١ — «المنشئ» يُقرأ من `created_by` لا يُخمَّن', () {
    final code = _code(_dbPath);
    expect(code.contains('Future<String?> getJournalEntryCreator('), isTrue,
        reason: 'قراءةُ المنشئ اختفت');
    final fn = _body(code, 'Future<String?> getJournalEntryCreator(',
        'return (name == null');
    expect(fn.contains('e.created_by'), isTrue,
        reason: 'المنشئُ يُقرأ من مصدرٍ آخر');
    expect(fn.contains('JOIN users'), isTrue,
        reason: 'الاسمُ لا يُربَط بالمستخدم — فيُعرَض رقمٌ بلا اسم');
    expect(_code(_repoIfacePath).contains('getJournalEntryCreator'), isTrue,
        reason: 'المستودعُ لا يكشفها — فلا تصل الشاشةَ');
  });

  test('‏٢ — و«لا يُعرَف» تُعرَض «—» لا اسماً مخمَّناً', () {
    // 🔴 كتابةُ «النظام» مكانَ المجهول تُخفي الفرقَ بين «آليٌّ» و«لا نعرف».
    final footer = _body(
      _code(_screenPath),
      'class _EntryFooter extends StatelessWidget {',
      '\nclass _Badge',
    );
    expect(footer.contains('repo.getJournalEntryCreator(entry.id)'), isTrue,
        reason: 'التذييلُ لا يقرأ المنشئَ أصلاً');
    expect(footer.contains("entry.isAutoPosted ? tr('ترحيل آلي') : '—'"), isTrue,
        reason: 'المجهولُ والآليُّ يُعرضان سواءً — فيضيع الفرق');
  });

  test('‏٣ — و«ملاحظات» لا تُبنى', () {
    // قرارُ المالك: تُسقَط. والحقلُ لا وجودَ له على القيد أصلاً، فالتصميمُ
    // يرسمه صفّاً فارغاً بشَرطة — وصفٌّ لا يحمل شيئاً أبداً ضجيجٌ.
    final footer = _body(
      _code(_screenPath),
      'class _EntryFooter extends StatelessWidget {',
      '\nclass _Badge',
    );
    expect(footer.contains("'ملاحظات'"), isFalse,
        reason: 'صفُّ ملاحظاتٍ بُني — وهو فارغٌ أبداً');
    // والمرجعُ يبقى: عمودٌ حقيقيٌّ يكتبه المستخدم (v174).
    expect(footer.contains("'المرجع'"), isTrue,
        reason: 'المرجعُ سقط مع الملاحظات — وهو عمودٌ له كاتب');
  });

  test('‏٤ — وكاتبُ سجلّ النشاط في **المستودع** لا في الحوار', () {
    // 🔴 **والقياسُ الحقيقيُّ في `journal_entry_activity_log_test`** — على
    // صفٍّ في الجدول لا على وجود نداءٍ في نصّ. وهذا الحارسُ يثبّت **موضعَه**
    // وحدَه: فحصٌ نصّيٌّ لا يفرّق بين شيفرةٍ تعمل وأخرى معطَّلةٍ بشرطٍ كاذب
    // (قِيس: `if (false)` يمرّ من الحارس ومن `flutter analyze` معاً).
    expect(_code(_loggerPath).contains('logJournalEntry('), isTrue,
        reason: 'الدالّةُ اختفت من السجلّ');

    final repo = _code(_repoImplPath);
    expect(repo.contains('logJournalEntry('), isTrue,
        reason: 'الكاتبُ بلا منادٍ — فالسجلُّ فارغٌ من القيود والقرارُ '
            'بلا مصدر');
    expect(_code(_dialogPath).contains('logJournalEntry('), isFalse,
        reason: 'التسجيلُ في الحوار يترك كلَّ منادٍ آخرَ بلا سجلّ');
  });

  test('‏٥ — والسجلُّ أثرٌ لا شرط — إخفاقُه لا يُفشِل الحفظ', () {
    // 🔴 القيدُ رُحِّل وحُرِّكت الأرصدة؛ ورميٌ بعده يُظهر خطأً على عمليّةٍ
    // نجحت فيعيدها المستخدمُ — ويُنشئ قيداً ثانياً.
    final fn = _body(
      _code(_repoImplPath),
      'Future<void> _logManualEntry(',
      "debugPrint('[DriftAccountingRepository] activity log failed",
    );
    expect(fn.contains('if (createdBy == null) return;'), isTrue,
        reason: 'الترحيلُ الآليُّ يُسجَّل — فيملأ السجلَّ ضجيجاً يُخفي ما '
            'يفعله البشر');
    expect(fn.contains('} catch (e) {'), isTrue,
        reason: 'إخفاقُ السجلّ يُفشِل الحفظَ — فيعيد المستخدمُ قيداً وقع');
  });

  test('ومرساةٌ — الترتيبُ: يُنشأ القيدُ ثمّ يُسجَّل', () {
    final code = _code(_repoImplPath);
    expect(code.indexOf('_db.createJournalEntry('),
        lessThan(code.indexOf('_logManualEntry(')),
        reason: 'السجلُّ يسبق الإنشاءَ — فيُسجَّل رقمُ قيدٍ لم يوجد');
  });
}
