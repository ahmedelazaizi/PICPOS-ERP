// تبويباتُ شاشة التقرير على هويّة PicPos.
//
// المصدر: `PicPos Reports.dc.html` — شريطُ التبويبات تحت شريط المرشِّحات:
// ارتفاعُ الخانة ٥٠، وأيقونةٌ ١٦ وعنوانٌ ١٣، وخطٌّ سفليٌّ ٢.٥ بلون العلامة
// للنشط وشفّافٌ لغيره، وشارةٌ اختياريّةٌ ١٠.٥ باستدارةٍ كاملة.
//
// ⚠️ **لا يملك الحالةَ ولا يبدّلها بنفسه.** يقرأ `TabController` الذي تملكه
// الشاشةُ أصلاً ويكتب فيه عند اللمس — فمحتوى التبويبات يبقى `TabBarView`
// كما هو، ولا يصير للشاشة مصدرا حقيقةٍ للتبويب المفتوح.
import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import 'picpos_surface.dart';

/// تبويبٌ واحد: عنوانٌ، وأيقونةٌ اختياريّة، وشارةٌ اختياريّة.
typedef PicPosReportTab = ({String label, IconData? icon, String? badge});

class PicPosReportTabs extends StatelessWidget {
  const PicPosReportTabs({
    super.key,
    required this.controller,
    required this.tabs,
  });

  final TabController controller;
  final List<PicPosReportTab> tabs;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.picposCard,
        border: Border(bottom: BorderSide(color: context.picposHairline)),
      ),
      // ⚠️ يتمرّر أفقيّاً: القوائمُ المالية خمسةُ تبويباتٍ بعناوينَ طويلةٍ
      //    («قائمة الدخل (P&L)») — وصفٌّ ثابتٌ يفيض على الشاشات الضيّقة.
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 26),
        child: AnimatedBuilder(
          animation: controller,
          builder: (context, _) => Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < tabs.length; i++) ...[
                if (i > 0) const SizedBox(width: 2),
                _tab(context, i),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _tab(BuildContext context, int i) {
    final t = tabs[i];
    final on = controller.index == i;
    final fg = on ? context.picposBrandInk : context.picposMuted;
    return InkWell(
      onTap: () => controller.animateTo(i),
      child: Container(
        height: 50,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: on ? AppColors.primary : Colors.transparent,
              width: 2.5,
            ),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (t.icon != null) ...[
              Icon(t.icon, size: 16, color: fg),
              const SizedBox(width: 8),
            ],
            Text(
              t.label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: on ? FontWeight.w800 : FontWeight.w700,
                color: fg,
              ),
            ),
            if (t.badge != null && t.badge!.isNotEmpty) ...[
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: on
                      ? AppColors.primary.withValues(alpha: 0.08)
                      : context.picposField,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  t.badge!,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    color: fg,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
