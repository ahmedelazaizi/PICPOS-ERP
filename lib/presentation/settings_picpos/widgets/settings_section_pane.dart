import 'package:flutter/material.dart';

/// اللوح المتمرِّر لقسم واحد من شاشة إعدادات PicPos.
///
/// مُستخرَج من `SettingsPicposScreen._buildSectionPane` ليصير قابلاً للقياس
/// وحدَه — الشاشة كاملةً تحتاج عشرات الـproviders وقاعدة بيانات، واللوح لا
/// يحتاج شيئاً منها.
///
/// ── لماذا الأولاد ملفوفون في `PageStorage` ──
/// الـ`PageStorageKey` على الـListView ضروري لحفظ موضع التمرير لكل قسم، لكنه
/// **موروث**: `PageStorageBucket._allKeys` يمشي من أي ودجت لأعلى ويلمّ كل
/// `PageStorageKey` في الطريق. فالـ`Scrollable` يكتب إزاحة التمرير (double)
/// تحت المعرِّف `[settings-<id>]`، وأي `ExpansionTile` داخل اللوح بلا مفتاح
/// خاص به يحسب **نفس** المعرِّف ويقرأ تلك الإزاحة `as bool?` في
/// `_ExpansibleState.initState` — فينفجر ويختفي القسم خلف صندوق خطأ.
///
/// اللفّ يقطع التوريث: `_allKeys` يتوقّف عند أول `PageStorage` في طريق الصعود،
/// فأولاد اللوح يحصلون على دلو خاص لا يرون فيه مفتاح التمرير. والـ`Scrollable`
/// ليس من نسل اللفّة (هو ابن الـListView مباشرةً) فيحتفظ بسلوكه كما هو.
///
/// الاصطدام ثنائي الاتجاه أصلاً: لو `ExpansionTile` كتب `true` أولاً، انفجر
/// `ScrollPosition.restoreScrollOffset` بـ`as double?` بدلاً منه.
class SettingsSectionPane extends StatefulWidget {
  const SettingsSectionPane({
    super.key,
    required this.sectionId,
    required this.children,
  });

  /// مُعرِّف القسم — يدخل في `PageStorageKey` كي يحتفظ كل قسم بموضع تمريره
  /// عند التنقّل بين الأقسام والعودة.
  final String sectionId;

  final List<Widget> children;

  @override
  State<SettingsSectionPane> createState() => _SettingsSectionPaneState();
}

class _SettingsSectionPaneState extends State<SettingsSectionPane> {
  /// دلو خاص بأولاد اللوح، معزول عن الدلو الذي يكتب فيه الـ`Scrollable`.
  /// يعيش في الـState فيبقى عبر إعادات البناء.
  final PageStorageBucket _childStorage = PageStorageBucket();

  @override
  Widget build(BuildContext context) {
    return ListView(
      key: PageStorageKey('settings-${widget.sectionId}'),
      padding: const EdgeInsetsDirectional.fromSTEB(16, 14, 16, 24),
      children: [
        for (final child in widget.children)
          PageStorage(bucket: _childStorage, child: child),
      ],
    );
  }
}
