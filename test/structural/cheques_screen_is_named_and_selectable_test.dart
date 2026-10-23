// حارسُ العقد: «إدارة الشيكات» — **اسمٌ واحدٌ، وإيداعٌ جماعيٌّ لا يسقط**.
//
// ═══ 🔴 ما كان ═══
//
// ‏١ — **اسمان لشاشةٍ واحدة**: «الشيكات» في المدخل الجانبيّ وفي المُوجِّه،
//     و«الشيكات والأوراق التجارية» عنواناً للشاشة. فمن ينقر «الشيكات» يجد
//     فوق رأسه اسماً آخر.
//
// ‏٢ — **والاسمُ لا يصف ما تفعله الشاشة**: تُنشئ وتُودع وتُظهِّر وتُرتجع.
//     وقرارُ المالك 2026-09-18: «إدارة الشيكات».
//
// ⚠️ **وبقاءُ «إيداع دفعة شيكات» منفصلاً قرارٌ صريح**: الاختيارُ المفردُ
// بالراديو **لا يُلغيه**. وهو مُسيَّجٌ بـ`PermissionGuard` فلا يُرسَم في
// اختبار ودجتٍ بلا تجهيزةِ صلاحيّات — فيُحرَس هنا.

import 'package:flutter_test/flutter_test.dart';

import '../helpers/library_source.dart';
import 'package:picpos_erp/core/navigation/screen_id.dart';

/// نصُّ الملفّ بلا أسطر التعليق وبلا `\r` — أغلبُ الملفّات هنا CRLF.
String _code(String path) => [
  for (final line in readLibrarySource(path).split('\n'))
    if (!line.trimLeft().startsWith('//')) line.replaceAll('\r', ''),
].join('\n');

const _screen =
    'lib/presentation/settings_picpos/screens/cheques_picpos_screen.dart';
const _main = 'lib/app_main_screen.dart';
const _nav = 'lib/data/providers/auth_providers.dart';

void main() {
  test('الاسمُ ثابتٌ واحدٌ وقيمتُه «إدارة الشيكات»', () {
    expect(
      chequesScreenLabel,
      'إدارة الشيكات',
      reason: 'قرارُ المالك 2026-09-18 على تسمية الشاشة',
    );
  });

  test('🔴 والمواضعُ الثلاثةُ تقرؤه لا تكتبه', () {
    for (final path in [_screen, _main, _nav]) {
      final code = _code(path);
      expect(
        code.contains('chequesScreenLabel'),
        isTrue,
        reason: '$path يكتب الاسمَ بيده — فيتفرّق الاسمُ على الأبواب',
      );
      expect(
        code.contains("label: 'الشيكات'"),
        isFalse,
        reason: '$path ما زال يحمل الاسمَ القديم مكتوباً',
      );
    }
    expect(
      _code(_screen).contains("'الشيكات والأوراق التجارية'"),
      isFalse,
      reason: 'عنوانُ الشاشة ما زال بالصيغة القديمة',
    );
  });

  test('🔴 و«إيداع دفعة شيكات» يبقى زرّاً منفصلاً في الرأس', () {
    // 🔴 الاختيارُ المفردُ يُغري بحذفه — وقرارُ المالك يُبقيه صراحةً:
    //    إيداعُ عشرين شيكاً بقسيمةٍ واحدةٍ لا يُنجَز بورقةٍ ورقة.
    final code = _code(_screen);
    // ⚠️ النصُّ وحدَه مرساةً: `label: const Text(...)` و`label: Text(...)`
    //    صيغتان لنفس الشيء، ونمطٌ يشترط إحداهما يسقط على تعديلٍ تجميليّ.
    expect(
      "'إيداع دفعة شيكات'".allMatches(code).length,
      1,
      reason: 'الإيداعُ الجماعيُّ سقط مع الاختيار المفرد — أو تكرّر',
    );
    // ويُسيَّج: إنشاءُ إيداعٍ يكتب على الخادم في وضع العميل.
    final at = code.indexOf("إيداع دفعة شيكات");
    final guardAt = code.lastIndexOf('PermissionGuard(', at);
    expect(
      guardAt,
      greaterThan(-1),
      reason: 'زرُّ الإيداع الجماعيِّ بلا حارس صلاحية',
    );
  });

  test('🔴 والاختيارُ مفردٌ — خانةٌ واحدةٌ من نوع الراديو', () {
    final code = _code(_screen);
    expect(
      code.contains('PicPosRadioCell('),
      isTrue,
      reason: 'خانةُ الاختيار اختفت',
    );
    expect(
      code.contains('Checkbox('),
      isFalse,
      reason: 'مربّعُ تعليمٍ يَعِد بتعدّدٍ لا يقع — والشريطُ لورقةٍ واحدة',
    );
  });

  test('ومرساةٌ — طولُ الإجماليّات يطابق عددَ الأعمدة', () {
    // ⚠️ خانةُ الاختيار عمودٌ تاسعٌ. وإسقاطُ خانتِها من `totals` يُزيح
    //    الإجماليَّ عموداً كاملاً — رقمٌ يُقرأ تحت عنوانٍ ليس له.
    final code = _code(_screen);
    final at = code.indexOf('List<PicPosTableColumn> get _selectableCols');
    expect(at, greaterThan(0), reason: 'أعمدةُ الجدول المفرد اختفت');
    final cols = code.substring(at, code.indexOf('];', at));
    expect(
      'PicPosTableColumn('.allMatches(cols).length,
      9,
      reason: 'عددُ الأعمدة تغيّر — فراجِع `totals` معه',
    );
  });
}
