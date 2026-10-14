part of 'pos_settings_widget.dart';

const double _previewPaneWidth = 360;
const double _previewMinTotalWidth = 1120;

extension _PosSettingsWidgetDesign on _PosSettingsWidgetState {
  /// تخطيطُ التصميم — شريطُ أقسامٍ جانبيٌّ ولوحةٌ تعرض المختارَ وحدَه.
  ///
  /// ⚠️ **الشريطُ أوّلُ أبناء `Row` عمداً.** الغلافُ يوفّر `Directionality`
  /// من اليمين، فأوّلُ الأبناء يقع يميناً — وهو موضعُ الشريط في التصميم
  /// (`border-inline-end`). ولهذا الحدُّ `left` لا `right`: الطرفُ المنطقيُّ
  /// `inline-end` هو الأيسرُ فيزيائيّاً في واجهةٍ عربيّة.
  Widget _buildDesignLayout() {
    return LayoutBuilder(
      builder: (context, constraints) => _buildDesignRow(
        showPreview: constraints.maxWidth >= _previewMinTotalWidth,
      ),
    );
  }

  Widget _buildDesignRow({required bool showPreview}) {
    final section = kQuickSaleSections[_sectionIndex];

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 250,
          child: Container(
            decoration: BoxDecoration(
              color: context.picposField,
              border: Border(left: BorderSide(color: context.picposHairline)),
            ),
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              children: [
                Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(8, 6, 8, 8),
                  child: Text(
                    tr('أقسام الحوار'),
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.4,
                      color: context.picposMuted,
                    ),
                  ),
                ),
                for (var i = 0; i < kQuickSaleSections.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: QuickSaleNavTile(
                      icon: kQuickSaleSections[i].icon,
                      tint: kQuickSaleSections[i].tint,
                      title: kQuickSaleSections[i].title,
                      settingCount: kQuickSaleSections[i].settingCount,
                      selected: i == _sectionIndex,
                      onTap: () => setState(() => _sectionIndex = i),
                    ),
                  ),
              ],
            ),
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsetsDirectional.fromSTEB(22, 18, 22, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                QuickSaleSectionHeader(
                  icon: section.icon,
                  tint: section.tint,
                  title: section.title,
                  hint: section.hint,
                ),
                const SizedBox(height: 14),
                _sectionBody(_sectionIndex),
              ],
            ),
          ),
        ),
        // ⚠️ **لوحةُ المعاينة مشروطةٌ بالعرض لا دائمة.** التصميمُ يرسمها
        // ثالثةً على شاشةٍ عريضة، والحوارُ يُفتَح على أجهزةِ تِلٍّ ضيّقةٍ
        // أيضاً. وثلاثةُ أعمدةٍ ثابتةٍ على ٩٠٠px تسحق لوحةَ الإعدادات نفسَها
        // — فالمعاينةُ تُسقَط قبل أن تُضيَّق الإعدادات.
        if (showPreview)
          SizedBox(width: _previewPaneWidth, child: _buildPreviewPane()),
      ],
    );
  }

  /// عرضُ لوحةِ المعاينة — تُعرَض حين يتّسع الحوارُ لها وحدَها.
  /// أدنى عرضٍ يُبقي لوحةَ الإعدادات صالحةً بجوار المعاينة.
  Widget _buildPreviewPane() {
    return Container(
      decoration: BoxDecoration(
        color: context.picposField,
        border: Border(right: BorderSide(color: context.picposHairline)),
      ),
      padding: const EdgeInsetsDirectional.fromSTEB(14, 18, 14, 20),
      child: SingleChildScrollView(
        child: QuickSaleDisplayPreview(
          showTopBar: _showTopBar,
          catIconSize: _catIconSize,
          catFontSize: _catFontSize,
          catSpacing: _catSpacing,
          catRunSpacing: _catRunSpacing,
          catLabelWidth: _catLabelWidth,
          catShape: _catShape,
          gridColumns: _gridColumns,
          gridSpacing: _gridSpacing,
          gridAspectRatio: _gridAspectRatio,
          nameFontSize: _productNameFontSize,
          priceFontSize: _productPriceFontSize,
          showProductImages: _showProductImagesInPOS,
        ),
      ),
    );
  }

  // لونُ كلِّ قسمٍ من [kQuickSaleSections] لا أرقاماً مكرّرة — مصدرٌ واحدٌ
  // للتصميم، فتغييرُ اللون هناك يسري على صفوفه هنا.
  Color get _mainTint => kQuickSaleSections[0].tint;
  Color get _catTint => kQuickSaleSections[1].tint;
  Color get _gridTint => kQuickSaleSections[2].tint;
  Color get _receiptTint => kQuickSaleSections[3].tint;
  Color get _tposTint => kQuickSaleSections[4].tint;

  // ═══════════════════════════════════════════════════════════════════════
  // صفوفُ الإعداد — نداءٌ واحدٌ يخدم العلامتَين
  // ═══════════════════════════════════════════════════════════════════════
  //
  // ⚠️ **لماذا الفرعُ داخلَ الصفِّ لا حولَ القسم.** تفريعُ كلِّ قسمٍ كان
  // يعني نسختَين من ٣٧ صفّاً في ملفٍّ واحد، وأوّلُ إصلاحٍ يدخل واحدةً
  // وينسى الأخرى. فالمُناداةُ واحدةٌ لكلِّ إعداد، والشكلُ وحدَه يتفرّع.
  //
  // و[legacyTitle] يحفظ نصَّ UralCash **حرفاً بحرف** حيث اختلف عن التصميم
  // (‏«حجم خط الاسم» مقابلَ «حجم الخط» مثلاً): العملُ على UralCash موقوفٌ،
  // فلا يصحُّ أن يبدّل هذا البندُ نصوصَها.

  /// ترويسةُ مجموعةٍ داخلَ القسم — شريطٌ ملوّنٌ رفيعٌ ثمّ الاسم.
  ///
  /// التصميمُ يفصل المجموعاتِ ببطاقاتٍ مستقلّة؛ وهنا تبقى بطاقةُ القسم
  /// واحدةً والمجموعاتُ تُفصَل بترويسةٍ بنفس المفردات البصريّة (شريطُ
  /// `3.5×15` بنصف قطر ٣). فرقٌ في التغليف لا في اللغة، ويُجنّب تفكيكَ
  /// خمسةِ بُناةٍ إلى بطاقاتٍ منفصلةٍ في هذا البند.
  Widget _groupHeader(String label, Color tint) {
    if (!widget.picposChrome) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 14,
            color: tint,
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(0, 14, 0, 6),
      child: Row(
        children: [
          Container(
            width: 3.5,
            height: 15,
            decoration: BoxDecoration(
              color: tint,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            label,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w800,
              color: context.picposText,
            ),
          ),
        ],
      ),
    );
  }

  /// صفُّ مِزلاجٍ (‏`toggle` في التصميم).
  Widget _toggleRow({
    required IconData icon,
    required Color tint,
    required String title,
    required String settingKey,
    required bool value,
    required ValueChanged<bool> onChanged,
    String? sub,
    String? legacyTitle,
    bool isLast = false,
  }) {
    if (!widget.picposChrome) {
      // بلا `style` على العنوان الفرعيّ — النسخةُ القديمةُ تتركه لـ`ListTile`،
      // وأيُّ مقاسٍ هنا يبدّل مظهرَ UralCash.
      return SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(legacyTitle ?? title),
        subtitle: sub == null ? null : Text(sub),
        value: value,
        onChanged: onChanged,
      );
    }
    return QuickSaleSettingRow(
      icon: icon,
      tint: tint,
      title: title,
      settingKey: settingKey,
      sub: sub,
      isLast: isLast,
      control: Switch(value: value, onChanged: onChanged),
    );
  }

  /// صفُّ مِنزلقٍ (‏`slider` في التصميم) — القيمةُ تُعرَض إلى جانبه.
  Widget _sliderRow({
    required IconData icon,
    required Color tint,
    required String title,
    required String settingKey,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required ValueChanged<double> onChanged,
    String? sub,
    String? legacyTitle,
    bool isLast = false,

    /// تنسيقُ القيمة المعروضة — `نسبة العرض/الارتفاع` كسريّةٌ بمنزلتَين لا
    /// صحيحة، فتقريبُها يخفي الفرقَ بين ٠٫٧٥ و٠٫٨٥.
    String Function(double)? format,

    /// تلميحُ المِنزلق حين يختلف عن القيمة المعروضة — «٥ دقيقة» في التلميح
    /// و«٥» بجانبه. تقريبُهما إلى صيغةٍ واحدةٍ يبدّل نصَّ UralCash.
    String Function(double)? labelFormat,
  }) {
    final shown = format ?? (v) => '${v.round()}';
    final tip = labelFormat ?? shown;
    final slider = Slider(
      value: value,
      min: min,
      max: max,
      divisions: divisions,
      label: tip(value),
      onChanged: onChanged,
    );

    if (!widget.picposChrome) {
      return Row(
        children: [
          Text('${legacyTitle ?? title}: '),
          Expanded(child: slider),
          Text(
            shown(value),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ],
      );
    }

    return QuickSaleSettingRow(
      icon: icon,
      tint: tint,
      title: title,
      settingKey: settingKey,
      sub: sub,
      isLast: isLast,
      control: SizedBox(
        width: 230,
        child: Row(
          children: [
            Expanded(child: slider),
            SizedBox(
              width: 44,
              child: Text(
                shown(value),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 12.5,
                  color: context.picposText,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// صفُّ اختيارٍ من قائمة (‏`select` في التصميم).
  Widget _selectRow<T>({
    required IconData icon,
    required Color tint,
    required String title,
    required String settingKey,
    required T value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
    String? sub,
    String? legacyTitle,
    bool isLast = false,
  }) {
    final dropdown = DropdownButton<T>(
      value: value,
      underline: const SizedBox.shrink(),
      items: items,
      onChanged: onChanged,
    );

    if (!widget.picposChrome) {
      return ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(legacyTitle ?? title),
        subtitle: sub == null ? null : Text(sub),
        trailing: dropdown,
      );
    }

    return QuickSaleSettingRow(
      icon: icon,
      tint: tint,
      title: title,
      settingKey: settingKey,
      sub: sub,
      isLast: isLast,
      control: dropdown,
    );
  }

  /// جسمُ القسمِ المختار — نفسُ بُناةِ UralCash بلا نسخ.
  Widget _sectionBody(int index) => switch (index) {
    0 => _buildMainPOSSection(),
    1 => _buildCategoryDisplaySection(),
    2 => _buildProductGridSection(),
    3 => _buildReceiptSection(),
    _ => _buildTablePOSSection(),
  };
}
