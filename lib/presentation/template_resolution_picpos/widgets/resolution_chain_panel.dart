import 'package:ural_erp/core/i18n/tr.dart';
import 'package:ural_erp/core/design_system/typography.dart';
// لوحةُ سلسلة السقوط — المستوياتُ الستّةُ بالترتيب، وأوّلُ مطابقٍ يفوز.
//
// ── لماذا تُعرض المستوياتُ المخفِقةُ أيضاً ────────────────────────────────
// «القالبُ الخطأ يُطبع» لا يُشخَّص بمعرفة الفائز وحدَه: السؤالُ الحقيقيُّ
// «لماذا لم تفز قاعدتي؟». والمستوى المخفِقُ بمفتاحه المعروضِ يجيب — يرى
// المالكُ أنّ قاعدتَه كُتبت بفرعٍ آخرَ أو بلغةٍ أخرى، فيصلحها.

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../domain/models/print_resolution_row.dart';
import '../../../services/printing/template_resolver.dart';
import '../../picpos_shell/picpos_content_card.dart';
import '../../picpos_shell/picpos_empty_state.dart';
import '../../picpos_shell/picpos_section_header.dart';
import '../../picpos_shell/picpos_surface.dart';
import '../screens/template_resolution_picpos_screen.dart' show resolutionTone;

class ResolutionChainPanel extends StatelessWidget {
  const ResolutionChainPanel({super.key, required this.row});

  final PrintResolutionRow? row;

  @override
  Widget build(BuildContext context) {
    final r = row;
    if (r == null) {
      return  PicPosContentCard(
        child: PicPosEmptyState(
          icon: PhosphorIconsBold.stack,
          title: tr('اختر مساراً'),
          hint: tr('تُعرض هنا سلسلةُ حسمِه ومستوياتُها الستّة'),
        ),
      );
    }

    return PicPosContentCard(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          PicPosSectionHeader(
            title: tr(r.documentLabel),
            subtitle: '${r.category} · ${r.paperLabel}',
            icon: PhosphorIconsBold.fileText,
          ),
          _Section(
            icon: PhosphorIconsBold.stack,
            title: tr('سلسلة السقوط'),
            subtitle: tr('تُجرَّب بالترتيب — أول قاعدة تُطابِق تفوز'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final s in r.chain) _ChainStep(step: s),
              ],
            ),
          ),
          _Section(
            icon: PhosphorIconsBold.printer,
            title: tr('سلوك الطباعة'),
            child: Column(
              children: [
                _Behaviour(
                  icon: PhosphorIconsBold.copy,
                  title: tr('عدد النُّسخ'),
                  sub: tr('تُطبع تلقائياً عند التأكيد'),
                  value: '${r.copies}',
                  tone: context.picposBrandInk,
                ),
                _Behaviour(
                  icon: PhosphorIconsBold.lightning,
                  title: tr('طباعة مباشرة'),
                  sub: tr('بلا نافذة اختيار طابعة'),
                  value: r.directPrint ? tr('مُفعَّلة') : tr('معطَّلة'),
                  tone: r.directPrint
                      ? AppColors.success
                      : context.picposMuted,
                ),
                _Behaviour(
                  icon: PhosphorIconsBold.ruler,
                  title: tr('عرض القالب'),
                  sub: tr('يجب أن يطابق عرضَ الطابعة'),
                  value: r.paperLabel,
                  tone: r.health == ResolutionHealth.paperMismatch
                      ? AppColors.error
                      : AppColors.success,
                ),
                _Behaviour(
                  icon: PhosphorIconsBold.plugsConnected,
                  title: tr('مسار الطباعة'),
                  sub: tr('هل يمرّر منادٍ حيٌّ نوعَ هذا المستند؟'),
                  value: TemplateResolver.wiredDocumentTypes
                          .contains(r.documentType)
                      ? tr('موصول')
                      : tr('غير موصول'),
                  tone: TemplateResolver.wiredDocumentTypes
                          .contains(r.documentType)
                      ? AppColors.success
                      : AppColors.warning,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(14, 4, 14, 14),
            child: _Verdict(row: r),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.child,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(14, 12, 14, 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: context.picposHairline)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 15, color: context.picposBrandInk),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(title,
                        style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
                            color: context.picposText)),
                    if (subtitle != null)
                      Text(subtitle!,
                          style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                              color: context.picposMuted)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _ChainStep extends StatelessWidget {
  const _ChainStep({required this.step});

  final ResolutionStepView step;

  @override
  Widget build(BuildContext context) {
    final (icon, tone) = switch (step.state) {
      ResolutionStepState.matched => (
          PhosphorIconsBold.checkCircle,
          AppColors.success
        ),
      ResolutionStepState.missed => (PhosphorIconsBold.x, AppColors.error),
      ResolutionStepState.notTried => (
          PhosphorIconsBold.dot,
          context.picposMuted
        ),
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: tone.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 12, color: tone),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        tr(step.label),
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                          color: step.isWinner
                              ? context.picposText
                              : context.picposMuted,
                        ),
                      ),
                    ),
                    if (step.isWinner) ...[
                      const SizedBox(width: 7),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.success.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child:  Text(tr('المُطبَّق'),
                            style: const TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w800,
                                color: AppColors.success)),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  step.key,
                  style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      fontFamily: AppTypography.mono,
                      height: 1.6,
                      color: context.picposMuted),
                ),
                const SizedBox(height: 3),
                Text(
                  _localizedStepResult(step),
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: step.isWinner
                          ? AppColors.success
                          : context.picposMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _localizedStepResult(ResolutionStepView step) {
  if (step.state == ResolutionStepState.missed) {
    return tr('لا قاعدة مطابقة');
  }
  if (step.state == ResolutionStepState.notTried) {
    return tr('لم يُجرَّب');
  }
  if (step.result == '← التصميم المدمج في الكود') {
    return tr('← التصميم المدمج في الكود');
  }

  const prefix = '← ';
  final value = step.result.startsWith(prefix)
      ? step.result.substring(prefix.length)
      : step.result;
  if (value.startsWith('قالب #')) {
    return tr('← قالب #{id}', {'id': value.substring('قالب #'.length)});
  }
  return '$prefix${trData(value)}';
}

class _Behaviour extends StatelessWidget {
  const _Behaviour({
    required this.icon,
    required this.title,
    required this.sub,
    required this.value,
    required this.tone,
  });

  final IconData icon;
  final String title;
  final String sub;
  final String value;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: context.picposHairline)),
      ),
      child: Row(
        children: [
          SizedBox(width: 18, child: Icon(icon, size: 14, color: tone)),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title,
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: context.picposText)),
                Text(sub,
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        height: 1.45,
                        color: context.picposMuted)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(value,
              style: TextStyle(
                  fontSize: 11.5, fontWeight: FontWeight.w800, color: tone)),
        ],
      ),
    );
  }
}

/// صندوقُ الحكم — سببُ الحال وما يُفعَل به.
class _Verdict extends StatelessWidget {
  const _Verdict({required this.row});

  final PrintResolutionRow row;

  @override
  Widget build(BuildContext context) {
    final tone = resolutionTone(context, row.health);
    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.07),
        border: Border.all(color: tone.withValues(alpha: 0.4), width: 1.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(PhosphorIconsBold.info, size: 15, color: tone),
              const SizedBox(width: 8),
              Expanded(
                child: Text(tr(row.health.label),
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        color: tone)),
              ),
            ],
          ),
          const SizedBox(height: 7),
          Text(
            verdictBody(row),
            style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                height: 1.7,
                color: context.picposText),
          ),
        ],
      ),
    );
  }
}

/// شرحُ الحال وما يُفعَل — يقرأ حالَ الصفّ لا نوعَ مستنده.
///
/// ⚠️ ولا يُكتب فيه اسمُ مستندٍ بعينه: نصٌّ يقول «المرتجعُ يطبع قالبَ
/// الفاتورة» يبقى معروضاً بعد أن يُصلَح المرتجعُ ويكذب.
String verdictBody(PrintResolutionRow row) => switch (row.health) {
      ResolutionHealth.builtIn =>
        tr('لا قالبَ يطابق هذا المستند في أيٍّ من المستويات الخمسة، فتُستدعى الدالّةُ المدمجةُ في الكود ولا يملك المالكُ من شكلها شيئاً. العلاج: افتح المكتبة، واختر قالباً يناسب الورق، ثمّ «تفعيل كافتراضي» لهذا المستند.'),
      ResolutionHealth.paperMismatch =>
        tr('عرضُ القالب يتجاوز عرضَ الطابعة المربوطة، فيُقصّ المطبوعُ من الحافّة بلا رسالةِ خطأ — وعمودُ الإجمالي أوّلُ ما يضيع. العلاج: اربط قالباً بعرض الطابعة، أو غيّر الطابعةَ في الرابطة.'),
      ResolutionHealth.collision =>
        tr('لا رابطةَ لهذا المستند، فيرث افتراضيَّ فئتِه — ونوعٌ آخرُ يرث القالبَ نفسَه. فأيُّ تعديلٍ لأحدهما يقع على الآخر. العلاج: اربط لكلٍّ قالبَه صراحةً من المكتبة، فالرابطةُ تسبق الفئةَ في السلسلة.'),
      ResolutionHealth.unwired =>
        tr('القالبُ محسومٌ صحيحاً، لكنّ مسارَ طباعة هذا المستند لا يمرّ على منظومة القوالب بعد — فلا يصل التعديلُ الورقةَ مهما رُبط. وهذا نقصُ امتدادٍ مخطَّطٌ له، لا عطبُ إعداد.'),
      ResolutionHealth.branchScoped =>
        tr('رابطةٌ مقيَّدةٌ بفرعٍ تحسم هذا المستند، وهي أخصُّ من العامّة فتتقدّم عليها. أيُّ فرعٍ آخرَ يسقط للمستوى الأعمّ.'),
      ResolutionHealth.categoryOnly =>
        tr('لا رابطةَ صريحةٌ لهذا المستند، فيحسمه افتراضيُّ الفئة — وهو السلوكُ القائم قبل الرابطات ويعمل. وربطُه صراحةً يجعله محصَّناً من أيّ تبديلٍ لافتراضيِّ الفئة.'),
      ResolutionHealth.bound =>
        tr('رابطةٌ صريحةٌ تطابق هذا المستند، والقالبُ وعرضُ الطابعة متوافقان. أيُّ تعديلٍ يُحفَظ في المحرر يسري على هذا المسار مباشرةً.'),
    };
