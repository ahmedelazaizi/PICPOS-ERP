import 'package:ural_erp/core/i18n/tr.dart';
// حوارُ تأكيدِ الخطر — على تصميم «منطقة الخطر» في شاشة الإعدادات.
//
// ═══ ما الذي يميّزه عن [showPicPosConfirm] ═══
//
// حوارُ التأكيد العاديُّ يسأل «هل أنت متأكّد؟» ويكتفي. وهذا لا يكفي حين
// تكون العمليةُ **بلا رجعة**: تصفيرُ البيانات يحذف كلَّ الفواتير والقيود،
// والاستعادةُ تستبدل القاعدةَ كلَّها وتُخرِج كلَّ المستخدمين.
//
// فيضيف هذا الحوارُ ثلاثةَ أشياءَ يطلبها التصميم:
//
//   ١) **قائمتان متقابلتان**: «سيُحذف» و«سيبقى كما هو». المستخدمُ يقرأ
//      الأثرَ بعينه قبل أن يقرّر، بدل أن يستنتجه من عنوانٍ عامّ. وأكثرُ
//      التردّد أمامَ زرِّ الحذف سببُه الجهلُ بما سيبقى لا بما سيُحذف.
//
//   ٢) **كلمةٌ تُكتَب**: الزرُّ خامدٌ حتى تُطابق. زرُّ «موافق» يُضغَط
//      بالغلط؛ والكتابةُ فعلٌ واعٍ لا يقع سهواً.
//
//   ٣) **صفوفُ حالة** (`metaRows`): حجمُ البيانات المتأثّرة، وعددُ
//      الفواتير، وتاريخُ آخر نسخةٍ احتياطية.
//      ⚠️ ويُمرِّرها **المستدعي** ولا يخترعها الحوار: التصميمُ يعرضها
//      بأرقامٍ توضيحيّة، ورقمٌ يكذب هنا أخطرُ من لا رقم — من رأى «آخر نسخة
//      اليوم 03:00» وهي كذبةٌ مضى على النسخة شهرٌ، صفّر وهو مطمئنّ.
//
// ⚠️ **ويُرجع `bool` غيرَ لاغٍ افتراضُه الرفض** — لنفس سببِ
// [showPicPosConfirm]: `showDialog<bool>` يُرجع `null` عند الإغلاق العرَضيّ،
// و`result != false` تقرؤها موافقةً. وهنا الموافقةُ الخاطئةُ تمحو قاعدةَ
// بيانات.
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme/app_colors.dart';
import 'picpos_dialog.dart';
import 'picpos_surface.dart';

/// صفُّ حالةٍ في تذييل الحوار — مفتاحٌ وقيمة.
typedef PicPosDangerMeta = ({String label, String value});

/// حوارُ تأكيدٍ لعمليةٍ لا رجعةَ فيها.
///
/// [typedWord] كلمةُ التأكيد. `null` ⇒ لا حقلَ ولا شرط، والزرُّ حيٌّ من
/// البداية (نمطُ `deluser` في التصميم: الحذفُ الفرديُّ تكفيه القائمتان).
Future<bool> showPicPosDangerConfirm(
  BuildContext context, {
  required IconData icon,
  required String title,
  required String message,
  required String actionLabel,
  required List<String> willDelete,

  /// العمودُ المقابل. **فارغةٌ ⇒ عمودٌ واحدٌ بعرضٍ كامل** — نمطُ `restore`
  /// و`deactivate` في التصميم: ما فيهما تسلسلُ خطواتٍ لا مقابلةُ أثر.
  List<String> willRemain = const [],

  /// ⚠️ العنوانان قابلان للتبديل لأنّ الأثرَ ليس حذفاً دائماً: حذفُ
  /// المستخدم في هذا النظام **تعطيلٌ وقفل**، والاستعادةُ **تسلسلُ خطوات**.
  /// وعنوانٌ يقول «سيُحذف» فوق أثرٍ لا يحذف كذبةٌ في أخطرِ موضع.
  ///
  /// `null` ⇒ «سيُحذف» / «سيبقى كما هو» مترجَمتَين عبر `tr()`.
  String? willDeleteLabel,
  String? willRemainLabel,
  String? typedWord,
  String? subtitle,
  List<PicPosDangerMeta> metaRows = const [],

  /// `warn` للعملياتِ الثقيلةِ القابلةِ للتدارك (الاستعادة · فكُّ التفعيل)،
  /// و`err` للمحو النهائيّ.
  bool warnTone = false,
  double width = 680,
}) async {
  final tone = warnTone ? AppColors.warning : AppColors.error;

  final result = await showDialog<bool>(
    context: context,
    // ⚠️ `false`: الحوارُ يمحو بيانات، فلا يُغلَق بنقرةٍ خارجَه سهواً.
    barrierDismissible: false,
    builder: (ctx) => _DangerBody(
      icon: icon,
      title: title,
      subtitle: subtitle,
      message: message,
      actionLabel: actionLabel,
      typedWord: typedWord,
      willDelete: willDelete,
      willDeleteLabel: willDeleteLabel ?? tr('سيُحذف'),
      willRemainLabel: willRemainLabel ?? tr('سيبقى كما هو'),
      willRemain: willRemain,
      metaRows: metaRows,
      tone: tone,
      width: width,
    ),
  );
  return result ?? false;
}

class _DangerBody extends StatefulWidget {
  const _DangerBody({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.message,
    required this.actionLabel,
    required this.typedWord,
    required this.willDelete,
    required this.willRemain,
    required this.willDeleteLabel,
    required this.willRemainLabel,
    required this.metaRows,
    required this.tone,
    required this.width,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final String message;
  final String actionLabel;
  final String? typedWord;
  final List<String> willDelete;
  final List<String> willRemain;
  final String willDeleteLabel;
  final String willRemainLabel;
  final List<PicPosDangerMeta> metaRows;
  final Color tone;
  final double width;

  @override
  State<_DangerBody> createState() => _DangerBodyState();
}

class _DangerBodyState extends State<_DangerBody> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// المطابقةُ حرفيّةٌ بعد تشذيبِ الفراغ وحدَه.
  ///
  /// ⚠️ لا `contains` ولا تجاهلَ حالةِ الأحرف: كلمةُ التأكيد حاجزٌ متعمَّد،
  /// وكلُّ تسهيلٍ فيه يُلغي سببَ وجوده.
  bool get _unlocked {
    final word = widget.typedWord;
    if (word == null) return true;
    return _controller.text.trim() == word;
  }

  @override
  Widget build(BuildContext context) {
    return PicPosDialog(
      icon: widget.icon,
      title: widget.title,
      subtitle: widget.subtitle,
      accent: widget.tone,
      width: widget.width,
      onCancel: () => Navigator.pop(context, false),
      primaryAction: PicPosDialogAction(
        label: widget.actionLabel,
        icon: PhosphorIconsBold.warningOctagon,
        color: widget.tone,
        // `null` ⇒ خامد. وهذا هو الحاجزُ نفسُه.
        onPressed: _unlocked ? () => Navigator.pop(context, true) : null,
      ),
      body: [
        Text(
          widget.message,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            height: 1.7,
          ),
        ),
        const SizedBox(height: 14),
        // القائمتان متقابلتان — الأثرُ يُقرأ لا يُستنتَج.
        // وعمودٌ واحدٌ حين لا مقابلَ (تسلسلُ خطواتٍ لا مقابلةُ أثر).
        if (widget.willRemain.isEmpty)
          _ImpactList(
            label: widget.willDeleteLabel,
            items: widget.willDelete,
            tint: widget.tone,
            mark: PhosphorIconsBold.arrowLeft,
          )
        else
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _ImpactList(
                  label: widget.willDeleteLabel,
                  items: widget.willDelete,
                  tint: AppColors.error,
                  mark: PhosphorIconsBold.x,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _ImpactList(
                  label: widget.willRemainLabel,
                  items: widget.willRemain,
                  tint: AppColors.success,
                  mark: PhosphorIconsBold.check,
                ),
              ),
            ],
          ),
        if (widget.metaRows.isNotEmpty) ...[
          const SizedBox(height: 14),
          _MetaTable(rows: widget.metaRows),
        ],
        if (widget.typedWord != null) ...[
          const SizedBox(height: 14),
          _TypedGate(
            word: widget.typedWord!,
            controller: _controller,
            tone: widget.tone,
            onChanged: () => setState(() {}),
          ),
        ],
      ],
    );
  }
}

/// عمودُ أثرٍ — عنوانٌ ملوَّنٌ ثمّ بنودٌ بعلامة.
class _ImpactList extends StatelessWidget {
  const _ImpactList({
    required this.label,
    required this.items,
    required this.tint,
    required this.mark,
  });

  final String label;
  final List<String> items;
  final Color tint;
  final IconData mark;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: tint.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: tint,
            ),
          ),
          const SizedBox(height: 8),
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Icon(mark, size: 12, color: tint),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      item,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.5,
                        color: context.picposText,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// صفوفُ الحالة — أرقامٌ يمرّرها المستدعي.
class _MetaTable extends StatelessWidget {
  const _MetaTable({required this.rows});

  final List<PicPosDangerMeta> rows;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: context.picposField,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: context.picposHairline),
      ),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 9),
              decoration: i == 0
                  ? null
                  : BoxDecoration(
                      border: Border(
                        top: BorderSide(color: context.picposHairline),
                      ),
                    ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      rows[i].label,
                      style: TextStyle(
                        fontSize: 12,
                        color: context.picposMuted,
                      ),
                    ),
                  ),
                  Text(
                    rows[i].value,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: context.picposText,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// حاجزُ الكلمة — الكلمةُ معروضةٌ ليُنسَخ نصُّها بالعين لا بالحدس.
class _TypedGate extends StatelessWidget {
  const _TypedGate({
    required this.word,
    required this.controller,
    required this.tone,
    required this.onChanged,
  });

  final String word;
  final TextEditingController controller;
  final Color tone;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(PhosphorIconsBold.keyboard, size: 14, color: tone),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                tr('اكتب «{word}» للتأكيد', {'word': word}),
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: tone,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          autofocus: true,
          onChanged: (_) => onChanged(),
          decoration: InputDecoration(
            hintText: tr('اكتب كلمة التأكيد هنا'),
            isDense: true,
            filled: true,
            fillColor: context.picposField,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: context.picposHairline),
            ),
          ),
        ),
      ],
    );
  }
}
