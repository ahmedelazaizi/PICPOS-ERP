// حارسٌ بنيويّ — إصلاحاتُ الدفاتر موصولةٌ بالإقلاع لا بزرٍّ يعرفه واحد.
//
// ── فئةُ العطب ────────────────────────────────────────────────────────────
// دالّةُ إصلاحٍ **موجودةٌ ومختبَرةٌ وصحيحة**، ولا شيءَ يناديها.
//
// `repairAllMissingInvoiceJEs` تمسح كلَّ فاتورةِ بيعٍ أو شراءٍ بلا قيدٍ
// آليّ وتُنشئه. وكان منادِيها الوحيدُ زرّاً في
// `branch_scope_admin_dialog.dart` — حوارُ إعداداتٍ للمشرف. فمن لا يعرف
// الزرَّ (أي كلُّ مستخدمٍ عاديّ) تبقى دفاترُه ناقصةً بلا أن ينطق شيء:
// الفاتورةُ في الجدول، والقيدُ غائبٌ من الأستاذ، والميزانيةُ لا تتزن —
// ولا رسالةَ خطأٍ واحدة تدلّ على السبب.
//
// وهي **متعادلة** (`hasAutoPostEntry` يقصّر الطريق لأيّ فاتورةٍ لها قيد)،
// فتشغيلُها كلَّ إقلاعٍ آمن. ومكانُها الطورُ المؤجَّل بعد ظهور الواجهة كي
// لا تؤخّر الإقلاع — تماماً كـ`repairFailedDeliveryAutoposts` المجاورة،
// التي تغطّي مسارَ التسليم وحدَه.
//
// حارسٌ بنيويٌّ لا سلوكيّ: المقيسُ هنا **الوصلُ** لا صحّةُ الإصلاح (ذاك
// مقيسٌ في اختبارات الإصلاح نفسِها). وطورُ الإقلاع المؤجَّل خاصٌّ لا
// يُنادى من اختبار.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _startupPath = 'lib/data/database/database_startup.dart';

/// سطرُ نداءٍ فعليّ لا ذكرٌ في تعليق.
bool _isCall(String line, String name) {
  final t = line.trimLeft();
  if (t.startsWith('//') || t.startsWith('///') || t.startsWith('*')) {
    return false;
  }
  return line.contains('$name(');
}

void main() {
  final startup = File(_startupPath);

  test('الإقلاعُ ينادي `repairAllMissingInvoiceJEs`', () {
    expect(startup.existsSync(), isTrue, reason: 'مسارُ ملفّ الإقلاع تغيّر');

    final called = startup
        .readAsLinesSync()
        .any((l) => _isCall(l, 'repairAllMissingInvoiceJEs'));

    expect(
      called,
      isTrue,
      reason: 'الدالّةُ موجودةٌ ومتعادلة، ومنادِيها الوحيدُ زرٌّ في حوار '
          'إعدادات المشرف. بلا وصلٍ بالإقلاع تبقى الفواتيرُ بلا قيودٍ في '
          'أيّ تجهيزةٍ لم يضغط أحدٌ فيها ذلك الزرّ — والميزانيةُ لا تتزن '
          'بلا سببٍ ظاهر.',
    );
  });

  test('الإقلاعُ ينادي `repairTemplateCategories`', () {
    final called = startup
        .readAsLinesSync()
        .any((l) => _isCall(l, 'repairTemplateCategories'));

    expect(
      called,
      isTrue,
      reason: 'بلاغُ المالك: «تصميمي مش بيوصل للورقة». البذرةُ القديمةُ تركت '
          'فئةَ قالب A4 على الافتراضيّ `receipt` بينما المنادي يسأل '
          '`invoice` — فيسقط التنفيذُ صامتاً إلى المولّد المكتوب في الكود. '
          'والبذرةُ لا تصلح ما هو موجود.',
    );
  });

  test('الإقلاعُ ينادي `backfillItemsTableElements`', () {
    final called = startup
        .readAsLinesSync()
        .any((l) => _isCall(l, 'backfillItemsTableElements'));

    expect(
      called,
      isTrue,
      reason: 'نفسُ فئة العطب مرّةً ثالثة. وبعد الخيار (ب) صار موضعُ جدول '
          'الأصناف من القالب لا من استدلال الكود — وقالبٌ بلا عنصرِ جدولٍ '
          'يبقى على الاستدلال أبداً. فالمالكُ يحرّك الجدولَ في المصمّم '
          'ولا يُحفَظ له موضع، والبذرةُ لا تصلح ما هو موجود.',
    );
  });

  test('الإقلاعُ ينادي `backfillShiftClosingChannelElements`', () {
    final called = startup
        .readAsLinesSync()
        .any((l) => _isCall(l, 'backfillShiftClosingChannelElements'));

    expect(
      called,
      isTrue,
      reason: 'نفسُ فئة العطب: البذرةُ تتخطّى قالبَ `shift_closing` القائم، '
          'ومنادي `seedDefaultTemplates` الوحيدُ شاشةُ مصمّم الفواتير. بلا '
          'وصلٍ بالإقلاع يبقى مطبوعُ الوردية بلا قناة «كليك» — قناتان '
          'معروضتان وإجماليٌّ يجمع الثلاث، فالقارئُ يتّهم الحسابَ وهو سليم.',
    );
  });

  test('الإقلاعُ ينادي `resetShiftClosingTemplateToSeed`', () {
    final called = startup
        .readAsLinesSync()
        .any((l) => _isCall(l, 'resetShiftClosingTemplateToSeed'));

    expect(
      called,
      isTrue,
      reason: 'إعادةُ البناء مشروطةٌ بمراجعةٍ مخزَّنة فتعمل مرّةً واحدة. بلا '
          'وصلٍ بالإقلاع لا تصل أبداً — ورفعُ المراجعة لاحقاً لدفع تغييرٍ '
          'في البذرة يصير بلا أثر.',
    );
  });

  test('ضابط: الإصلاحُ المجاور (التسليم) لسه موصولاً', () {
    // لو انفكّ هذا أيضاً فالمشكلةُ أوسعُ من بندٍ واحد، والحارسُ فوق وحدَه
    // كان سيمرّ صامتاً على تجهيزةٍ فقدت الاثنين.
    final called = startup
        .readAsLinesSync()
        .any((l) => _isCall(l, 'repairFailedDeliveryAutoposts'));

    expect(called, isTrue,
        reason: 'إصلاحُ قيود التسليم كان موصولاً — لا يُفكّ');
  });

  test('ضابط: الدالّةُ المقيسة موجودةٌ فعلاً في المحرّك', () {
    // بلا هذا، إعادةُ تسميةٍ تجعل الحارسَ فوق يقيس اسماً لا وجودَ له،
    // فيُقرأ أحمرَ لسببٍ زائف — أو يُحذف الحارسُ لأنه «خطأ».
    final dao = File('lib/data/database/daos/accounting_autopost_dao.dart');
    expect(dao.existsSync(), isTrue);
    expect(dao.readAsStringSync().contains('repairAllMissingInvoiceJEs'), isTrue,
        reason: 'الاسمُ تغيّر — حدّث الحارس، لا تحذفه');
  });
}
