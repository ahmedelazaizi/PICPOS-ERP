// المهمّة ٦-ب — قواعدُ وضع التصميم الخالصة لشاشة الطاولات بهويّة PicPos.
//
// انظر `.superpowers/sdd/2026-08-20-tables-picpos-restyle/task-6b-brief.md`.
// دالّتان مستخرَجتان عمداً عن `_TablesPicposBody` (ودجت) و`TablesUIController`
// (‏Provider) كي تُقاسا بلا فتح شاشةٍ ولا `ProviderContainer`.

/// هل يظهر زرُّ «تصميم» في ترويسة شاشة الطاولات؟ — ترتيبُ المخطَّط معنى فقط
/// في وضع الخريطة؛ في وضع الشبكة لا مخطّط يُرتَّب.
bool showDesignerModeToggle({required bool isVisualView}) => isVisualView;

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
