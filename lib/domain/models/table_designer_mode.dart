// المهمّة ٦-ب — قواعدُ وضع التصميم الخالصة لشاشة الطاولات بهويّة PicPos.
//
// انظر `.superpowers/sdd/2026-08-20-tables-picpos-restyle/task-6b-brief.md`.
// دالّتان مستخرَجتان عمداً عن `_TablesPicposBody` (ودجت) و`TablesUIController`
// (‏Provider) كي تُقاسا بلا فتح شاشةٍ ولا `ProviderContainer`.

// ⚠️ **و`showDesignerModeToggle` حُذِفت في قسم ٧.** كانت تجيب «هل يظهر
// زرُّ تصميم؟» بـ«في وضع الخريطة وحدَه»، وهو صحيحٌ يومَ كان الزرُّ
// يقلب الشاشةَ نفسَها. وصار يفتح شاشةً مستقلّةً فلا معنى لحصرِه
// بعرضٍ بعينه — **ودالّةٌ بلا مُنادٍ ولها اختبارٌ أخضر تُقرأ عقداً
// قائماً وهي ليست**. و`designerModeAfterViewToggle` تبقى: الشاشةُ القديمة
// (فورك UralCash، `tables_top_bar.dart`) ما زال فيها وضعُ التصميم.

/// حالةُ `isDesignerMode` بعد تبديل العرض (‏`TablesUIController.toggleView`‏).
///
/// مغادرةُ الخريطة (كانت `wasVisualView: true`) تُطفئ وضعَ التصميم دائماً —
/// وإلّا عاد المستخدمُ إلى الخريطة فوجد نفسَه في وضعِ تحريرٍ لا يذكر أنه
/// فتحه. والدخولُ إلى الخريطة من الشبكة لا يُشعله من تلقاء نفسه؛ الزرُّ
/// المحروسُ هو مَن يُشعله.
bool designerModeAfterViewToggle({
  required bool wasVisualView,
  required bool wasDesignerMode,
}) => wasVisualView ? false : wasDesignerMode;
