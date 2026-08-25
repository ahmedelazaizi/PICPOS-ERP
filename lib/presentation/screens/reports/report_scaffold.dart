// إطارُ شاشة تقرير — واحدٌ لكلتا الهويّتَين.
//
// ═══ لماذا دالّةٌ واحدةٌ لا فرعٌ في كلّ شاشة ═══
//
// ثماني عشرةَ شاشةَ تقريرٍ تبني كلٌّ منها `Scaffold(appBar: AppBar(...))`
// بيدها، والأربعُ عشرةَ منها بنفس الشكل حرفاً بحرف: عنوانٌ، وأرضيّةُ العلامة،
// ومقدّمةٌ بيضاء، وارتفاعٌ صفر، وأزرارٌ على الطرف. فتفريعُ كلٍّ على حدةٍ ثماني
// عشرةَ نسخةً تنحرف بأوّل تعديلٍ في الهويّة — وهو عينُ ما بُني
// `PicPosScreenScaffold` ليمنعه.
//
// ⚠️ **وفرعُ UralCash هنا نسخةٌ حرفيّةٌ ممّا كانت تبنيه الشاشات** — لا تقريبٌ
// له. أيُّ اختلافٍ في لونٍ أو ارتفاعٍ يظهر في أربعَ عشرةَ شاشةً دفعةً.
//
// ⚠️ **وشاشةُ الضرائب خارجَ هذا الإطار عمداً**: شريطُها يحمل **منتقيَ مركز
// تكلفةٍ داخلَ الـ`AppBar`** وزرَّ رجوعٍ صريحاً (‏Spec 057). ومنتقٍ داخلَ
// الترويسة في تصميم PicPos مكانُه شريطُ المرشِّحات لا الترويسة، فنقلُه قرارٌ
// يُتَّخذ لا تفصيلُ تنسيق.
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../core/config/brand.dart';
import '../../../core/theme/app_colors.dart';
import '../../picpos_shell/picpos_screen_scaffold.dart';

/// يبني إطارَ الشاشة: ترويسةُ PicPos الموحّدة، أو `AppBar` كما كانت.
///
/// [actions] تُوضع في طرف الترويسة في الهويّتَين معاً.
///
/// و[icon] لا أثرَ له في فرع UralCash — الـ`AppBar` هناك عنوانٌ وحدَه.
Widget reportScaffold({
  required BuildContext context,
  required String title,
  required Widget body,
  String? subtitle,
  IconData? icon,
  List<Widget> actions = const [],
}) {
  if (Brand.isPicPos) {
    return PicPosScreenScaffold(
      title: title,
      subtitle: subtitle,
      icon: icon,
      headerActions: actions,
      // ⚠️ **بلا حشو**: شريطُ المرشِّحات أوّلُ ما في جسم التقرير، وهو في
      //    التصميم ممتدٌّ من حافّةٍ إلى حافّةٍ بحشوه الخاصّ. وحشوُ الإطار
      //    الافتراضيُّ كان سيُدخله عن الحافّتَين فيُقرأ بطاقةً لا شريطاً.
      bodyPadding: EdgeInsets.zero,
      body: body,
    );
  }

  return Directionality(
    textDirection: ui.TextDirection.rtl,
    child: Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(title),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: actions,
      ),
      body: body,
    ),
  );
}
