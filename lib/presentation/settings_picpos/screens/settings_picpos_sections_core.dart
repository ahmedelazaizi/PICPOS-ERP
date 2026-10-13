part of 'settings_picpos_screen.dart';

extension _SettingsPicposCoreSections on _SettingsPicposScreenState {
  _SettingsSection _buildSystemSection(BuildContext context, ThemeMode themeMode, FeaturePolicy features, BusinessProfile profile) => 
      _SettingsSection(
        id: 'system',
        title: tr('النظام والمظهر'),
        icon: PhosphorIconsBold.slidersHorizontal,
        group: tr('التشغيل'),
        desc: tr('الشركة · العملة · المظهر'),
        keywords: tr('شركة صناعة عملة مظهر ثيم داكن نهاري شاشة رئيسية قاعدة بيانات صيانة مزامنة مرآة شيكات فروع سيرفر شبكة لمس كيبورد'),
        children: () => [
          // ═══ 1. النظام والمظهر — على بلوكات التصميم ═══
          SettingsBlockGrid(
            blocks: [
              SettingsBlockSpan(
                span: 12,
                child: SettingsBlock(
                  title: tr('مظهر البرنامج'),
                  subtitle: tr('يُطبَّق على كل الشاشات وشاشة العميل'),
                  child: SettingsChoiceBlock<ThemeMode>(
                    selected: themeMode,
                    onSelect: (m) =>
                        ref.read(themeModeProvider.notifier).setMode(m),
                    options:  [
                      SettingsChoiceOption(
                        value: ThemeMode.light,
                        label: tr('فاتح'),
                        sub: tr('الأنسب للإضاءة القوية والطباعة من الشاشة'),
                      ),
                      SettingsChoiceOption(
                        value: ThemeMode.dark,
                        label: tr('غامق'),
                        sub: tr('مريح للكاشير في الورديات الليلية'),
                      ),
                      SettingsChoiceOption(
                        value: ThemeMode.system,
                        label: tr('تلقائي'),
                        sub: tr('يتبع مظهر ويندوز'),
                      ),
                    ],
                  ),
                ),
              ),
              SettingsBlockSpan(
                span: 7,
                child: SettingsBlock(
                  title: tr('هوية الشركة والتشغيل'),
                  subtitle: tr('تظهر في الفواتير والتقارير المطبوعة'),
                  tint: AppColors.info,
                  child: SettingsRowsBody(
                    children: [
                      // ⚠️ الحُرّاسُ باقون: `settingsCompany` هنا و
                      //    `systemDatabase` في مربّع قاعدة البيانات أسفل.
                      PermissionGuard(
                        permission: PermissionCodes.settingsCompany,
                        fallback: const SizedBox.shrink(),
                        child: SettingsValueRow(
                          first: true,
                          icon: PhosphorIconsBold.buildings,
                          title: tr('معلومات الشركة'),
                          sub: tr('الاسم، السجل التجاري، الرقم الضريبي، الشعار'),
                          onTap: () => showCompanyInfoDialog(context, picpos: true),
                        ),
                      ),
                      // الودجتاتُ القائمةُ نفسُها — بُدِّل رسمُها إلى صفِّ
                      // بلوك، ومنتقياتُها ومعالجةُ القفل فيها كما هي.
                      const _IndustryModeToggle(),
                      const _CurrencySelector(),
                       const UserLanguageSelector(),
                      const _DefaultHomeScreenSelector(),
                    ],
                  ),
                ),
              ),
               SettingsBlockSpan(
                span: 5,
                child: SettingsBlock(
                  title: tr('سلوك التشغيل'),
                  subtitle: tr('خيارات تسري على هذا الجهاز فقط'),
                  tint: AppColors.warning,
                  child: const SettingsRowsBody(
                    children: [
                      // ⚠️ مفتاحٌ واحدٌ لا ثلاثة: التصميمُ يعرض معه
                      //    «المزامنة الإجبارية» و«بدء تلقائي مع ويندوز»،
                      //    والأولى في التطبيق **زرُّ إجراءٍ** لا مفتاحاً
                      //    (‏لوحةُ المزامنة أسفل)، والثانيةُ لا وجودَ لها
                      //    أصلاً. ومفتاحٌ لا يبدّل شيئاً أسوأُ من غيابه.
                      _TouchModeSwitchRow(),
                    ],
                  ),
                ),
              ),
               SettingsBlockSpan(
                span: 12,
                child: SettingsBlock(
                  title: tr('الشاشات المتقدمة'),
                  subtitle: tr('قاعدة البيانات، الربط، وأدوات الصيانة'),
                  tint: AppColors.textMuted,
                  child: _AdvancedTiles(onOpenConnections: () => setState(() => _selectedSectionId = linkedDevicesSectionId)),
                ),
              ),
              // ⚠️ لوحةُ الدفع اليدويِّ بلوكٌ لا مربّع: لها حالةُ تشغيلٍ
              //    وزرٌّ يخمُد أثناء العمل، ولا تُختصر في سطرِ حالة.
               SettingsBlockSpan(
                span: 12,
                child: SettingsBlock(
                  title: tr('مزامنة يدويّة'),
                  subtitle: tr('دفعُ التغييرات إلى السيرفر عند الحاجة'),
                  tint: AppColors.info,
                  child: const _ForceSyncPanel(),
                ),
              ),
            ],
          ),
        ],
      )
;

  _SettingsSection _buildDevicesSection(BuildContext context, ThemeMode themeMode, FeaturePolicy features, BusinessProfile profile) => 
      _SettingsSection(
        id: 'devices',
        title: tr('الأجهزة والطباعة'),
        icon: PhosphorIconsBold.printer,
        group: tr('التشغيل'),
        desc: tr('طابعات · نقاط بيع · قوالب'),
        keywords: tr('طابعة باركود ماسح ميزان حراري قوالب فواتير نقاط بيع بصمة تصميم'),
        children: () => [
          // ═══ 2. الأجهزة والطباعة — شبكةُ بلوكاتِ التصميم ═══
          SettingsBlockGrid(
            blocks: [
               SettingsBlockSpan(
                span: 12,
                child: SettingsBlock(
                  title: tr('إدارة الأجهزة'),
                  subtitle: tr('كل جهاز طرفي مربوط بالنظام'),
                  child: const _DeviceTiles(),
                ),
              ),
               SettingsBlockSpan(
                span: 12,
                child: SettingsBlock(
                  title: tr('باركود الميزان'),
                  subtitle: tr('بادئةُ الملصق وتوزيعُ خاناته'),
                  tint: AppColors.textMuted,
                  child: const _ScaleBarcodeSettings(),
                ),
              ),
              if (features.hrEnabled)
                 SettingsBlockSpan(
                  span: 12,
                  child: SettingsBlock(
                    title: tr('جهاز البصمة'),
                    subtitle: tr('ربطُ الحضور والانصراف'),
                    tint: AppColors.info,
                    child: const FingerprintSettingsWidget(),
                  ),
                ),
            ],
          ),
        ],
      )
;

  _SettingsSection _buildPosSection(BuildContext context, ThemeMode themeMode, FeaturePolicy features, BusinessProfile profile) => 
      _SettingsSection(
        id: 'pos',
        title: tr('البيع السريع'),
        icon: PhosphorIconsBold.shoppingCart,
        group: tr('التشغيل'),
        desc: tr('الكاشير · الدفع · الخصم'),
        keywords: tr('تراكم أصناف ميزان وزن سلة أزرار تصنيفات شبكة منتجات إيصال طباعة تلقائية بيع بالسالب خصم ضريبة درج مصروفات وردية مخزن افتراضي بادئة ترقيم طرق الدفع نقدي بطاقة تحويل آجل متعدد'),
        children: () => [
          // ═══ 3. البيع السريع — شبكةُ بلوكاتِ التصميم ═══
          //
          // ⚠️ الحارسُ `buildPosSettingsTileGuarded` يبقى كما هو: هو نفسُه
          //    ودجتٌ يحمل فحصَ الصلاحية، فيُوضَع جسماً للبلوك لا يُفكَّك.
          SettingsBlockGrid(
            blocks: [
              SettingsBlockSpan(
                span: 12,
                child: SettingsBlock(
                  title: tr('إعدادات البيع السريع'),
                  subtitle: tr('سلوكُ شاشة الكاشير وحدودُ الخصم'),
                  child: buildPosSettingsTileGuarded(
                    onOpen: () => showPosSettingsDialog(context, picpos: true),
                  ),
                ),
              ),
              // §٤ — شاشةُ السياسة بجوار ديالوج العرض.
              //
              // ⚠️ **بلوكان لا واحد عن قصد.** البلوكُ أعلاه يفتح ديالوجاً
              // يضبط **ما يُعرَض** (مقاساتٌ وأعمدةٌ وأيقونات)، وهذا يفتح
              // شاشةً تضبط **ما يحدث** (‏البيعُ بالسالب · سقفُ الخصم · من
              // يصادق على الإغلاق). ودمجُهما كان يخلط قرارَ مظهرٍ بقرارٍ
              // محاسبيّ في نافذةٍ واحدة.
              SettingsBlockSpan(
                span: 12,
                child: SettingsBlock(
                  title: tr('سياسة البيع السريع'),
                  subtitle: tr('ما يحدث بين المسح والإغلاق — بخمس خطوات'),
                  tint: AppColors.info,
                  child: buildQuickSalePolicyTileGuarded(
                    onOpen: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const QuickSalePolicyScreenPicpos(),
                      ),
                    ),
                  ),
                ),
              ),
               SettingsBlockSpan(
                span: 7,
                child: SettingsBlock(
                  title: tr('طرق الدفع الظاهرة'),
                  subtitle: tr('ما يراه الكاشير في لوحة الدفع'),
                  tint: AppColors.success,
                  child: const _PaymentMethodsSettingsCard(),
                ),
              ),
               SettingsBlockSpan(
                span: 5,
                child: SettingsBlock(
                  title: tr('إغلاق الوردية'),
                  subtitle: tr('الإغلاقُ السريع بلا جرد'),
                  tint: AppColors.warning,
                  child: const _QuickCloseSettingTile(),
                ),
              ),
            ],
          ),
        ],
      )
;

}
