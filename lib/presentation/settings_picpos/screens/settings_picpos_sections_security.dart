part of 'settings_picpos_screen.dart';

extension _SettingsPicposSecuritySections on _SettingsPicposScreenState {
  _SettingsSection _buildUsersSection(BuildContext context, ThemeMode themeMode, FeaturePolicy features, BusinessProfile profile) => 
      _SettingsSection(
        id: 'users',
        title: tr('المستخدمون والأمان'),
        icon: PhosphorIconsBold.shieldCheck,
        group: tr('الأمان'),
        desc: tr('الحسابات · الأدوار · الصلاحيات'),
        keywords: tr('مستخدمين صلاحيات أدوار كلمة مرور جلسة مهلة حماية أقسام'),
        children: () => [
          // ═══ 4. المستخدمون والأمان — شبكةُ بلوكاتِ التصميم ═══
          //
          // إدارةُ المستخدمين والأدوار سلطتُها على السيرفر: العميلُ لا
          // يُنشئ مستخدماً (تصادمُ معرّفات) ولا يحرّر صلاحيةً (تُسحَب من
          // السيرفر كلَّ مزامنة) — فيرى بلوكاً إعلاميّاً مكانَها.
          SettingsBlockGrid(
            blocks: [
              if (!NetworkService.instance.isClient) ...[
                 SettingsBlockSpan(
                  span: 12,
                  child: SettingsBlock(
                    title: tr('المستخدمون والأدوار'),
                    subtitle: tr('الحساباتُ وصلاحياتُ كل دور'),
                    child: const _UserTiles(),
                  ),
                ),
                SettingsBlockSpan(
                  span: 12,
                  child: SettingsBlock(
                    title: tr('فحص الصلاحيات على السيرفر'),
                    subtitle: tr('تفعيلُ التحقّق من الصلاحية عند السيرفر'),
                    tint: AppColors.warning,
                    // ⚠️ الحارسُ باقٍ بحرفه: `rolesManage` — من يغيّر صلاحياتِ
                    //    الأدوار هو وحدَه من يفتح فرضَها على السيرفر.
                    child: PermissionGuard(
                      permission: PermissionCodes.rolesManage,
                      allowManagerOverride: true,
                      actionName: tr('فحص الصلاحيات على السيرفر'),
                      child: _ServerPermsToggleTile(),
                    ),
                  ),
                ),
              ] else
                 SettingsBlockSpan(
                  span: 12,
                  child: SettingsBlock(
                    title: tr('إدارة المستخدمين والصلاحيات'),
                    subtitle: tr('تتم إدارتها من السيرفر — وضع العميل للعرض فقط'),
                    tint: AppColors.info,
                    child: const SizedBox.shrink(),
                  ),
                ),
               SettingsBlockSpan(
                span: 7,
                child: SettingsBlock(
                  title: tr('انتهاء الجلسة'),
                  subtitle: tr('إغلاقٌ تلقائيٌّ بعد خمولٍ'),
                  tint: AppColors.info,
                  child: const _SessionTimeoutSetting(),
                ),
              ),
              SettingsBlockSpan(
                span: 5,
                child: SettingsBlock(
                  title: tr('كلمة مرور الإعدادات'),
                  subtitle: tr('حمايةُ هذه الشاشة'),
                  tint: AppColors.error,
                  child: SettingsRowsBody(
                    children: [
                      SettingsValueRow(
                        first: true,
                        icon: PhosphorIconsBold.lockKey,
                        title: tr('تغيير كلمة المرور'),
                        sub: tr('اتركها فارغةً لإلغاء الحماية'),
                        tint: AppColors.error,
                        onTap: _showChangePasswordDialog,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
        ],
      )
;

  _SettingsSection _buildLinkedDevicesSection(BuildContext context, ThemeMode themeMode, FeaturePolicy features, BusinessProfile profile) => 
      // ═══ ٤-أ. ربط التطبيقات والأجهزة — المحتوى في `linked_devices_section.dart` ═══
      _SettingsSection(
        id: linkedDevicesSectionId,
        title: linkedDevicesSectionTitle(),
        icon: PhosphorIconsBold.devices,
        group: tr('الربط'),
        desc: linkedDevicesSectionDesc(),
        keywords: linkedDevicesSectionKeywords(),
        children: () => [
          LinkedDevicesSection(
            onOpenNetworkMode: () => _showNetworkModeDialog(context),
          ),
        ],
      )
;

  _SettingsSection _buildGuardsSection(BuildContext context, ThemeMode themeMode, FeaturePolicy features, BusinessProfile profile) => 
      // ═══ ٤-ب. حماية الأقسام — قسمٌ مستقلٌّ على التصميم الجديد ═══
      //
      // كان بلوكاً داخلَ «المستخدمون والأمان»، وفصلَه التصميمُ لأنّ حراستَه
      // **مستقلّةٌ عن الصلاحيات**: كلمةٌ يعرفها من يجلس على الجهاز، لا دورٌ
      // يُسنَد لحساب. فخلطُهما في قسمٍ واحدٍ يوحي بأنّ أحدَهما يُغني عن الآخر.
      //
      // ⚠️ **ولا تسييجَ بـ`kitchenEnabled || hrEnabled` بعد اليوم.** كان
      //    القسمُ كلُّه مخفيّاً في بروفايل السوبرماركت، فيختفي معه قفلُ
      //    **المخازن والمشتريات والتقارير** — وهي أقسامٌ موجودةٌ في كلّ
      //    بروفايل. التسييجُ صار على البند: `hr_access_password` وحدَه يتبع
      //    `features.hrEnabled`.
      _SettingsSection(
        id: 'guards',
        title: tr('حماية الأقسام'),
        icon: PhosphorIconsBold.lockKey,
        group: tr('الأمان'),
        desc: tr('أقفال الشاشات'),
        keywords: tr('قفل كلمة مرور حماية اقسام مخازن مشتريات تقارير حسابات موظفين بديلة'),
        children: () => [
          SettingsBlockGrid(
            blocks: [
              SettingsBlockSpan(
                span: 12,
                child: SettingsBlock(
                  title: tr('الأقسام المحميّة'),
                  subtitle: tr('تُطلَب كلمةٌ عند الدخول لكلِّ قسمٍ مفعَّل'),
                  tint: AppColors.error,
                  child: _GuardedSectionRows(features: features),
                ),
              ),
            ],
          ),
        ],
      )
;

  _SettingsSection _buildFinanceSection(BuildContext context, ThemeMode themeMode, FeaturePolicy features, BusinessProfile profile) => 
      _SettingsSection(
        id: 'finance',
        title: tr('المالية والمحاسبة'),
        icon: PhosphorIconsBold.bank,
        group: tr('المال والبيانات'),
        desc: tr('ربط الحسابات · التكلفة · الفوترة'),
        keywords: tr('حسابات ربط تلقائي تكلفة تسعير نقص مخزون فوترة إلكترونية ضريبة قيمة مضافة'),
        children: () => [
          // ═══ 5. الإعدادات المالية ═══
          PermissionGuard(
            permission: PermissionCodes.settingsBackup,
            allowManagerOverride: true,
            actionName: tr('إعدادات المحاسبة'),
            child: SettingsBlockGrid(
              blocks: [
                SettingsBlockSpan(
                  span: 12,
                  child: SettingsBlock(
                    title: tr('ربط الحسابات'),
                    subtitle: tr('تحديد الحسابات الدفترية للعمليات'),
                    child: SettingsRowsBody(
                      children: [
                        SettingsValueRow(
                          first: true,
                          icon: PhosphorIconsBold.bookOpen,
                          title: tr('ربط الحسابات التلقائي'),
                          sub: tr('حسابُ كلِّ عمليةٍ في الدفتر'),
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  const AccountMappingPicPosScreen(),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                 SettingsBlockSpan(
                  span: 12,
                  child: SettingsBlock(
                    title: tr('التكلفة والمخزون'),
                    subtitle: tr('طريقةُ التسعير وسياسةُ نقص الخامات'),
                    tint: AppColors.info,
                    // ⚠️ الثلاثةُ ودجتاتٌ لها حالتُها ومزوّداتُها، فتُوضَع
                    //    كما هي جسماً للبلوك ولا تُفكَّك إلى صفوفِ قيمة.
                    //    وتبديلُ «البيع بالسالب» ليس هنا: نُقل إلى إعدادات
                    //    البيع السريع بطلبِ المشغّلين، والمفتاحُ نفسُه
                    //    (`enable_negative_sales`) لم يتبدّل.
                    child: const Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _CostingMethodToggle(),
                        _StockShortagePolicyToggle(),
                        _StockShortagePolicyPerBranchTile(),
                      ],
                    ),
                  ),
                ),
                // الفوترةُ الإلكترونيّةُ مخفيّةٌ في بروفايل السوبرماركت.
                if (profile != BusinessProfile.supermarket)
                   SettingsBlockSpan(
                    span: 12,
                    child: SettingsBlock(
                      title: tr('الفوترة الإلكترونية'),
                      subtitle: tr('حقولُ مصلحة الضرائب في المستندات'),
                      tint: AppColors.warning,
                      child: const _EInvoiceVisibilityToggles(),
                    ),
                  ),
              ],
            ),
          ),
        ],
      )
;

  _SettingsSection _buildHrSection(BuildContext context, ThemeMode themeMode, FeaturePolicy features, BusinessProfile profile) => 
      _SettingsSection(
        id: 'hr',
        title: tr('شؤون الموظفين'),
        icon: PhosphorIconsBold.calendarCheck,
        // ⚠️ قسمٌ **لا يذكره التصميم** — فلا يقرّره. باقٍ كما هو، ومسيَّجٌ
        //    أصلاً بـ`features.hrEnabled` (‏قرارُ المالك: lite تؤجّل الأجور).
        group: tr('المال والبيانات'),
        desc: tr('الورديات · الإجازات · الرواتب'),
        keywords: tr('عطلات عطل إجازات أسبوعية أعياد أيام العمل رواتب أجر الساعة إضافي وقت'),
        children: () => [
          // ═══ 5.1 شؤون الموظفين ═══
          // `features.hrEnabled` **شرطٌ لا تجميل**: بروفايل `lite` — وهو
          // افتراضيُّ PicPos (`Brand.defaultProfileCode`) — يضبطه `false`،
          // فالوحدةُ غيرُ موجودةٍ في هذا المنتج. المدخلُ هنا لأن الشاشتين
          // فوركان من نفس الكود ويعملان لبروفايلاتٍ أخرى.
          if (features.hrEnabled)
            SettingsBlockGrid(
              blocks: [
                SettingsBlockSpan(
                  span: 12,
                  child: SettingsBlock(
                    title: tr('العطلات وأيام العمل'),
                    subtitle: tr('الأيامُ التي لا يقع عليها غياب'),
                    tint: AppColors.secondary,
                    // الحارسُ ودجتٌ يحمل فحصَه، فيُوضَع جسماً للبلوك.
                    child: buildWorkHolidaysTileGuarded(
                      onOpen: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const WorkHolidaysPicposScreen()),
                      ),
                    ),
                  ),
                ),
              ],
            ),
        ],
      )
;

}
