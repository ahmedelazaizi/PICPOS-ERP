// هل يبلغ الإعدادُ **مسارَ بيعِ PicPos** — لا «أيَّ ملفٍّ في المستودع»؟
//
// ═══ لماذا هذا الحارسُ فوقَ `quick_sale_keys_have_readers_test` ═══
//
// ذاك يسأل: «هل لهذا المفتاح قارئٌ في المستودع؟». وهو سؤالٌ ضروريٌّ لكنّه
// **فضفاض**: `auto_print_receipt` له قارئٌ في `pos_expense_dialog.dart` —
// وهو سندُ **صرفِ مصروف**، لا إيصالُ بيع. فالمفتاحُ يمرّ ذاك الحارسَ وهو
// لا يمسّ بيعةً واحدةً في شاشة الكاشير.
//
// فالسؤالُ هنا أضيق: هل يبلغ المفتاحُ **شجرةَ PicPos** (‏`pos_picpos/`
// و`shift_close_picpos/`) وهي وحدَها ما يجري تحت زرِّ «دفع»؟
//
// ═══ الطرقُ الخمسُ التي يبلغ بها ═══
//
//   ١. نصُّ المفتاح مباشرةً.
//   ٢. معرّفُ الصفّ: `kQuickSaleRows.firstWhere((r) => r.id == 'drawer')`.
//   ٣. مترجِمٌ مسمّى في النموذج: `quickSaleReceiptCopies(policy)`.
//   ٤. مزوِّدٌ وسيطٌ في `data/providers` يقرأ المفتاحَ، واسمُه مذكورٌ في
//      شجرة PicPos — كـ`preventItemStackingProvider`.
//   ٥. حاسمُ القالب (الـDAO) يقرأ المفتاحَ، والمحرّكُ يُشعل الطباعة.
//
// وإسقاطُ أيٍّ منها يُنتج بلاغاً كاذباً، وقد قِيس ذلك: نسخةٌ تبحث عن
// نصِّ المفتاح وحدَه تعدّ عشرةَ مفاتيحَ ميّتةً وكلُّها حيّة.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/domain/models/quick_sale_policy.dart';

const _picposEngineDirs = [
  'lib/presentation/pos_picpos',
  'lib/presentation/shift_close_picpos',
];

const _providersDir = 'lib/data/providers';
const _modelPath = 'lib/domain/models/quick_sale_policy.dart';

String _readAll(String dir) {
  final root = Directory(dir);
  if (!root.existsSync()) return '';
  final buffer = StringBuffer();
  for (final f in root.listSync(recursive: true).whereType<File>()) {
    if (f.path.endsWith('.dart')) buffer.writeln(f.readAsStringSync());
  }
  return buffer.toString();
}

void main() {
  late String engine;
  late String providers;
  late String model;

  setUpAll(() {
    engine = _picposEngineDirs.map(_readAll).join('\n');
    providers = _readAll(_providersDir);
    model = File(_modelPath).readAsStringSync();
    expect(engine.length, greaterThan(10000),
        reason: 'لم تُقرأ شجرةُ PicPos — المسارُ النسبيُّ غلطٌ والنتيجةُ '
            'كلُّها بلا معنى. (صفرُ مطابقاتٍ = نمطٌ غلطٌ غالباً)');
  });

  /// أسماءُ المترجِمات في النموذج التي تخصّ [rowId].
  List<String> translatorsFor(String rowId) {
    final out = <String>[];
    final decl = RegExp(
      r'^[A-Za-z_<>?, ]+\s+(quickSale\w+)\s*\([^)]*\)\s*=>([\s\S]*?);',
      multiLine: true,
    );
    for (final m in decl.allMatches(model)) {
      if ((m.group(2) ?? '').contains("_rowById('$rowId')")) {
        out.add(m.group(1)!);
      }
    }
    return out;
  }

  /// أسماءُ المزوِّدات في `data/providers` التي تقرأ [key].
  ///
  /// ⚠️ **لا `[^;]*?;`**: جسمُ المزوِّد فيه فواصلُ منقوطةٌ، فالنمطُ يتوقّف
  /// قبل أن يبلغ نصَّ المفتاح ويعطي صفرَ مطابقاتٍ كاذباً. والتقطيعُ عند
  /// `\nfinal ` هو الحدُّ الصحيح.
  List<String> providersFor(String key) {
    final out = <String>[];
    for (final chunk in providers.split(RegExp(r'^final\s', multiLine: true))) {
      if (!chunk.contains("'$key'")) continue;
      final name = RegExp(r'^(\w+Provider)\s*=').firstMatch(chunk);
      if (name != null) out.add(name.group(1)!);
    }
    return out;
  }

  /// هل تقرأ طبقةُ البيانات [key] مباشرةً؟ — مسارُ المرايا.
  bool dataLayerReads(String key) {
    final buffer = StringBuffer()
      ..write(_readAll('lib/data/database'))
      ..write(_readAll('lib/data/repositories'));
    return buffer.toString().contains("'$key'");
  }

  /// أسماءُ الثوابت في النموذج التي تحمل نصَّ [key].
  ///
  /// ⚠️ **بدونها يقرأ الفحصُ صفراً كاذباً**: القارئُ قد يستعمل ثابتاً مسمّىً
  /// (`kQuickSaleReceiptTemplateKey`) لا نصَّ المفتاح، فالبحثُ عن النصّ وحدَه
  /// يعدّ الصفَّ ميّتاً وهو حيّ. مقيسٌ على `tpl` قبل هذا السطر بدقائق.
  List<String> constantsFor(String key) => [
        for (final m
            in RegExp("const\\s+(\\w+)\\s*=\\s*'$key'\\s*;").allMatches(model))
          m.group(1)!,
      ];

  /// هل يقرأ **حاسمُ القالب** أيّاً من [tokens]؟
  ///
  /// ⚠️ **ملفٌّ واحدٌ بعينه، وهو القارئُ الفعليّ.** و`template_resolver.dart`
  /// مستبعَدٌ عمداً رغم أنّه يذكر الثابت: هو نقيٌّ لا يقرأ إعداداً، وإنّما
  /// يعرض اسمَ المفتاح مفتاحاً للسطر في شاشة الحسم. فإدراجُه كان يُبقي
  /// الحارسَ أخضرَ لو توقّف الـDAO عن القراءة — أي حارسٌ يحرس ذِكرَ اسمٍ لا
  /// وصلةً.
  bool resolverDaoReads(List<String> tokens) {
    final f = File('lib/data/database/daos/template_binding_dao.dart');
    if (!f.existsSync()) return false;
    final src = f.readAsStringSync();
    return tokens.any(src.contains);
  }

  /// بأيّ طريقةٍ يبلغ الصفُّ محرّكَ PicPos؟ — `null` حين لا يبلغ.
  String? reach(QuickSaleRow row) {
    if (engine.contains("'${row.settingKey}'")) return 'نصُّ المفتاح';
    if (engine.contains("r.id == '${row.id}'")) return 'معرّفُ الصفّ';
    for (final t in translatorsFor(row.id)) {
      if (engine.contains('$t(')) return 'مترجِم $t';
    }
    for (final p in providersFor(row.settingKey)) {
      if (engine.contains(p)) return 'مزوِّد $p';
    }
    // المرآةُ: صفٌّ يكتب مفتاحاً ثانياً تقرأه طبقةُ البيانات — وهو مسارُ
    // `negstock` عبر `enable_negative_sales`.
    final mirror = row.mirrorKey;
    if (mirror != null && dataLayerReads(mirror)) return 'مرآة $mirror';

    // ٥ · سلسلةُ حسم القالب — يقرؤها الحاسمُ، ويشعلها المحرّكُ بنداء الطباعة.
    //
    // ⚠️ **مشروطةٌ بشقَّين عن قصد.** «طبقةُ البيانات تقرأ المفتاح» وحدَها هي
    // عينُ الفحص الفضفاض الذي بُني هذا الملفُّ ليتجاوزه (‏`auto_print_receipt`
    // كان له قارئٌ في سندِ مصروف). فيُشترط معه أنّ شجرةَ PicPos **تُشعل
    // الطباعةَ فعلاً** — وإلّا فالمفتاحُ يُقرأ في مسارٍ لا يمرُّ به زرُّ الدفع.
    if (resolverDaoReads([
          "'${row.settingKey}'",
          ...constantsFor(row.settingKey),
        ]) &&
        RegExp(r'printInvoice\(|_tryPrintReceipt\(').hasMatch(engine)) {
      return 'سلسلةُ حسم القالب';
    }
    return null;
  }

  group('كلُّ صفٍّ موسومٍ `enforced` يبلغ شجرةَ PicPos', () {
    // ⚠️ قائمةُ الاستثناءات **مقيسةٌ لا مفترضة**، وكلُّ سطرٍ فيها عطبٌ
    // مبلَّغٌ عنه — لا إذنٌ دائم. وإصلاحُ أيٍّ منها يُسقط اختبارَ
    // «القائمةُ لا تكبر» أدناه، فيُشطَب السطرُ عمداً.
    // ✅ **فارغةٌ عمداً — وهذا هو المقصد.**
    //
    // كان فيها `autoprint`: الطباعةُ كانت يحكمها `printAfter` وحدَه (‏F4 يطبع
    // · F2 لا) ولا يُستشار `auto_print_receipt` إطلاقاً، وقارئُه الوحيدُ في
    // المستودع سندُ مصروفٍ لا إيصالُ بيع. ثمّ حسم المالكُ 2026-08-30: «F4
    // يوقف الطباعة» ⇒ وُصِّل في `_processPaymentAndSave`، فسقط هذا الفحصُ
    // وأُفرغ المدخل — وهو بالضبط ما صُمِّم له.
    //
    // ⚠️ **ولا تُضِف مدخلاً هنا لتُسكِت الحارس.** المدخلُ يعني «صفٌّ يقول
    // للمدير إنّه يعمل وهو لا يعمل» — والوسمُ الصحيحُ لذلك `enforced: false`
    // مع `notEnforcedReason`، لا استثناءٌ في اختبار.
    const knownUnreachable = <String, String>{};

    for (final row in kQuickSaleRows.where((r) => r.enforced)) {
      test('${row.id} (${row.settingKey})', () {
        final how = reach(row);
        if (knownUnreachable.containsKey(row.id)) {
          expect(how, isNull,
              reason: 'صار «${row.id}» يبلغ المحرّكَ عبر «$how» — '
                  'احذفه من `knownUnreachable`.');
          return;
        }
        expect(how, isNotNull,
            reason: 'الصفُّ «${row.id}» موسومٌ `enforced: true` ولا يبلغ '
                'شجرةَ PicPos بأيٍّ من الطرق الخمس ⇒ **ميزةٌ ميّتةٌ '
                'صامتة**: المديرُ يبدّله ولا يتغيّر شيء.');
      });
    }

    test('قائمةُ ما لا يبلغ لا تكبر', () {
      final unreachable = [
        for (final r in kQuickSaleRows.where((r) => r.enforced))
          if (reach(r) == null) r.id,
      ];
      expect(unreachable, isEmpty,
          reason: 'كلُّ اسمٍ هنا إعدادٌ موسومٌ بالإنفاذ ولا أثرَ له — المديرُ '
              'يبدّله ولا يتغيّر شيء. وكان فيها `autoprint` حتّى وُصِّل '
              'بقرار المالك 2026-08-30.');
    });
  });

  group('مجموعاتُ الاختيار كذلك', () {
    test('كلُّ `pick` موسومةٍ بالإنفاذ يبلغ مفتاحُها المحرّك', () {
      for (final pick in kQuickSalePicks) {
        final enforced = pick.enforced;
        final reached = engine.contains("'${pick.settingKey}'") ||
            providersFor(pick.settingKey)
                .any((p) => engine.contains(p)) ||
            // المحرّكُ قد يبلغها عبر ثابتٍ مسمّىً في شجرة PicPos نفسِها.
            engine.contains('enabledPaymentMethodsSettingKey');
        if (enforced) {
          expect(reached, isTrue,
              reason: 'المجموعةُ «${pick.id}» (${pick.settingKey}) موسومةٌ '
                  'بالإنفاذ ولا يقرأها المحرّك');
        } else {
          expect(pick.notEnforcedReason, isNotNull,
              reason: 'مجموعةٌ غيرُ منفَّذةٍ بلا سببٍ معلَنٍ تبدو للمدير '
                  'عاملةً — «${pick.id}»');
        }
      }
    });
  });

  group('حيويّةُ القراءة — لا يكفي أن يبلغ، بل أن يصل ساخناً', () {
    test(
        '`preventItemStackingProvider` يُقرأ بارداً لكنّ الشجرةَ تُسخّنه', () {
      // القراءةُ الباردةُ لمزوِّدٍ مستقبليٍّ ترجع `null` حتّى يُجلَب،
      // و`?? false` تفسّرها «التجميعُ يعمل» — أياً كان المحفوظ. فالقراءةُ
      // الباردةُ مقبولةٌ **بشرط** مراقبٍ في الشجرة يُبقي المزوِّدَ ساخناً،
      // وهو نفسُ علاجِ `quickSalePolicyProvider`. (‏عولج 2026-08-30 · D1)
      final coldReads = RegExp(r'ref\s*\.\s*read\(\s*preventItemStackingProvider')
          .allMatches(engine)
          .length;
      final watches = RegExp(r'ref\s*\.\s*watch\(\s*preventItemStackingProvider')
          .allMatches(engine)
          .length;

      expect(coldReads, greaterThan(0),
          reason: 'إن صار صفراً فقد تغيّر المسارُ — أعِد قياسَ العطب');
      expect(watches, greaterThan(0),
          reason: 'لا مراقبَ للمزوِّد في شجرة PicPos ⇒ يبقى بارداً فترجع '
              '`null`، و`?? false` تقرؤها «التجميعُ مسموح»: المديرُ يُطفئ '
              '«تجميع الصنف المتكرر» والأصنافُ تظلّ تندمج.');
    });

    test('وبالمقابل `quickSalePolicyProvider` مُسخَّنٌ في شاشتَيه', () {
      final watches = RegExp(r'ref\s*\.\s*watch\(quickSalePolicyProvider\)')
          .allMatches(engine)
          .length;
      expect(watches, greaterThanOrEqualTo(2),
          reason: 'شاشةُ الكاشير وحوارُ الإغلاق كلاهما يقرأ متزامناً '
              '(`_refocusScanner` و`_blindClose`) فلا بدّ من مراقبٍ في كلٍّ');
    });
  });
}
