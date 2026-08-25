import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// حارسُ الأسطح الفاتحة الثابتة في فوركات PicPos.
///
/// ═══ العطبُ المُبلَّغ عنه ═══
///
/// أرسل المالكُ صوراً 2026-08-25 تُظهر بطاقاتٍ **بيضاءَ فاقعةً** داخلَ حوارٍ
/// داكن: بطاقاتُ «بند ١/٢» في قوالب القيود، وصندوقُ «شعار الشركة» في معلومات
/// الشركة. والسببُ واحدٌ في الحالتين:
///
///     AppColors.surface = Color(0xFFF8FAFC)   // ثابتٌ فاتحٌ لا يتبع الثيم
///
/// و`AppColors.surfaceDark` موجودةٌ منفصلةً — أي أنّ الفاتحَ **لا يتبدّل**
/// بتبدّل الوضع. فكلُّ `color: AppColors.surface,` داخلَ `BoxDecoration`
/// يرسم لوحاً أبيضَ في الوضع الغامق.
///
/// ═══ لماذا `color:` تحديداً ولماذا الفوركاتُ وحدَها ═══
///
/// **`color:` وحدَها مأمونةُ الحكم**: `AppColors.surface` قد تُستعمل مقدّمةً
/// (‏نصّاً أو أيقونةً على خلفيّةٍ داكنة) وذلك مشروع. أمّا `color:` داخلَ
/// `BoxDecoration`/`Container` فهي **أرضيّةٌ** بالبناء — والأرضيّةُ الفاتحةُ
/// الثابتةُ عطبٌ في وضعٍ غامق. وهذا عينُ الدرس المسجَّل: الأبيضُ مقدّمةٌ في
/// أغلبه، والمأمونُ للحكم أرضيّةُ `BoxDecoration`.
///
/// **والنطاقُ فوركاتُ PicPos وحدَها** لأنّها ما يراه المالك. ومقيسٌ
/// 2026-08-25 أنّ في `lib/presentation` كلِّها **٧٦ موضعاً** بهذا النمط —
/// الباقي في شاشات UralCash المشتركة، وإصلاحُها بندٌ أوسعُ لا يُخلَط بهذا.
void main() {
  /// المجلّداتُ التي تُرسَم بهويّة PicPos — ما يراه المالكُ في التطبيق.
  const picposDirs = [
    'lib/presentation/accounting_picpos',
    'lib/presentation/bookings_picpos',
    'lib/presentation/dashboard_picpos',
    'lib/presentation/inventory_picpos',
    'lib/presentation/invoice_form_picpos',
    'lib/presentation/offers_picpos',
    'lib/presentation/parties_picpos',
    'lib/presentation/picpos_shell',
    'lib/presentation/pos_picpos',
    'lib/presentation/products_picpos',
    'lib/presentation/purchase_returns_picpos',
    'lib/presentation/reports_picpos',
    'lib/presentation/sales_invoices_picpos',
    'lib/presentation/sales_returns_picpos',
    'lib/presentation/settings_picpos',
    'lib/presentation/shift_close_picpos',
    'lib/presentation/treasury_picpos',
    'lib/presentation/users_picpos',
  ];

  /// ملفّاتٌ خارجَ الفوركات لكنّها تُفتَح من واجهة PicPos مباشرةً — بلّغ
  /// المالكُ عن اثنين منها بالصورة.
  const picposReachable = [
    'lib/presentation/screens/create_journal_template_dialog.dart',
    'lib/presentation/widgets/settings/company_info_widget_io.dart',
    'lib/presentation/widgets/settings/hardware/hardware_scale.dart',
  ];

  List<String> dartFiles(String dir) {
    final d = Directory(dir);
    if (!d.existsSync()) return const [];
    return d
        .listSync(recursive: true)
        .whereType<File>()
        .map((f) => f.path.replaceAll(r'\', '/'))
        .where((p) => p.endsWith('.dart'))
        .toList();
  }

  test('لا أرضيّةَ فاتحةً ثابتةً في فوركات PicPos', () {
    final offenders = <String>[];

    for (final path in [
      ...picposDirs.expand(dartFiles),
      ...picposReachable,
    ]) {
      final f = File(path);
      if (!f.existsSync()) continue;
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final l = lines[i];
        if (l.trimLeft().startsWith('//')) continue;
        // أرضيّةٌ صريحة — `color: AppColors.surface,` أو `.background,`.
        if (RegExp(r'color:\s*AppColors\.(surface|background)\s*,')
            .hasMatch(l)) {
          offenders.add('$path:${i + 1}');
        }
      }
    }

    expect(offenders, isEmpty,
        reason: 'أرضيّةٌ فاتحةٌ ثابتةٌ في مسار PicPos — ستظهر لوحاً أبيضَ في '
            'الوضع الغامق، وهو عينُ ما بلّغ عنه المالكُ بالصور 2026-08-25.\n'
            'استعملْ `context.picposField` أو `context.picposCard` — '
            'كلتاهما تتبعان الوضعَين.\n'
            'المواضع:\n  ${offenders.join("\n  ")}');
  });

  test('و`AppColors.surface` ما زالت ثابتةً فاتحةً — فالحارسُ ما زال لازماً',
      () {
    // ⚠️ لو صارت `surface` تتبع الثيمَ يوماً، فهذا الحارسُ يمنع استعمالاً
    //    صار مشروعاً. يقيس هذا الاختبارُ الفرضيّةَ نفسَها بدل أن يفترضها:
    //    إن احمرَّ فالفرضيّةُ سقطت — احذفِ الحارسَ الأوّلَ ولا تلتفّ عليه.
    final src =
        File('lib/core/theme/app_colors.dart').readAsStringSync();
    expect(
      RegExp(r'static const Color surface = Color\(0xFFF8FAFC\)')
          .hasMatch(src),
      isTrue,
      reason: '`AppColors.surface` لم تعد الثابتَ الفاتحَ الذي بُني عليه '
          'الحارسُ أعلاه. أعِد تقييمَ الحارس بدل تجاهله.',
    );
  });
}
