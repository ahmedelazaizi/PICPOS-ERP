part of 'settings_picpos_screen.dart';

extension _SettingsPicposServiceSections on _SettingsPicposScreenState {
  _SettingsSection _buildDataSection(BuildContext context, ThemeMode themeMode, FeaturePolicy features, BusinessProfile profile) => 
      _SettingsSection(
        id: 'data',
        title: tr('إدارة البيانات'),
        icon: PhosphorIconsBold.database,
        group: tr('المال والبيانات'),
        desc: tr('النسخ الاحتياطي · الاستعادة'),
        keywords: tr('نسخ احتياطي استعادة باك اب backup restore تصدير'),
        children: () => [
          // ═══ 6. إدارة البيانات ═══
          // ⚠️ الحارسُ يلفُّ الشبكةَ كلَّها لا بلوكاً فيها: النسخُ
          //    والاستعادةُ عمليّةٌ واحدة، وإظهارُ نصفِها بلا صلاحيةٍ يوهم
          //    بأن الشاشةَ ناقصةٌ لا محميّة.
           PermissionGuard(
            permission: PermissionCodes.settingsBackup,
            allowManagerOverride: true,
            actionName: tr('إدارة البيانات'),
            child: SettingsBlockGrid(
              blocks: [
                SettingsBlockSpan(
                  span: 12,
                  child: SettingsBlock(
                    title: tr('النسخ الاحتياطي والاستعادة'),
                    subtitle: tr('حفظُ نسخةٍ من القاعدة واستعادتُها'),
                    tint: AppColors.success,
                    child: const BackupRestoreWidget(),
                  ),
                ),
              ],
            ),
          ),
        ],
      )
;

  _SettingsSection _buildIntegrationsSection(BuildContext context, ThemeMode themeMode, FeaturePolicy features, BusinessProfile profile) => 
      _SettingsSection(
        id: 'integrations',
        title: tr('التكاملات والخدمات'),
        icon: PhosphorIconsBold.plugsConnected,
        group: tr('الامتدادات'),
        desc: tr('شاشة العميل · المطبخ · التوصيل · رمز الطاولة · واتساب'),
        keywords: tr('توصيل مناديب شاشة عميل CFD مطبخ KDS إضافات معدلات رمز طاولة QR حساب ضيف دومين واتساب whatsapp رمز دولة رسائل عملاء'),
        children: () => [
          // ═══ 7. التكاملات والخدمات ═══
          SettingsBlockGrid(
            blocks: [
              // ⚠️ **هنا لا في حوار الطباعة وحدَه.** كانت رايتا رمز الطاولة
              // تُضبطان داخلَ حوارٍ يُفتَح لطباعة الأكواد — فمن بحث عنها في
              // الإعدادات لم يجدها، وهو بلاغُ المالك بنصّه. ورايةُ طلبِ
              // الضيف لم يكن لها **كاتبٌ في `lib/` كلِّها**، فالنصفُ الذي
              // طُلب صراحةً كان مطفأً إلى الأبد.
              if (features.tablesEnabled)
                 SettingsBlockSpan(
                  span: 12,
                  child: SettingsBlock(
                    title: tr('رمز حساب الطاولة'),
                    subtitle: tr('الضيفُ يرى حسابَه ويطلب من هاتفه'),
                    tint: AppColors.info,
                    child: const Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TableBillSettingsCard(),
                        // قسمُ ٧ — طباعةُ الأكواد نُقلت من رأس شاشة
                        // الطاولات: ورقةٌ تُطبَع مرّةً عند التجهيز، وموضعُها
                        // في رأسِ شاشةٍ يفتحها النادلُ كلَّ دقيقةٍ يزاحم
                        // أفعالَه اليوميّة بفعلٍ لا يفعلُه.
                        TableBillQrLauncherRow(),
                      ],
                    ),
                  ),
                ),
               SettingsBlockSpan(
                span: 12,
                child: SettingsBlock(
                  title: tr('رسائل العملاء — واتساب'),
                  subtitle: tr('الفاتورةُ وكشفُ الحساب والمطالبة'),
                  tint: AppColors.success,
                  child: const WhatsAppSettingsCard(),
                ),
              ),
              if (features.deliveryEnabled)
                SettingsBlockSpan(
                  span: 12,
                  child: SettingsBlock(
                    title: tr('التوصيل'),
                    subtitle: tr('شركاتُ التوصيل والمناديب'),
                    tint: AppColors.success,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const _DeliveryToggle(),
                        // ⚠️ الحارسُ باقٍ بحرفه — `deliveryManage` مع
                        //    تجاوزِ المدير، كما كان قبل النقل.
                        PermissionGuard(
                          permission: PermissionCodes.deliveryManage,
                          allowManagerOverride: true,
                          actionName: tr('إدارة التوصيل'),
                          child: SettingsRowsBody(
                            children: [
                              SettingsValueRow(
                                first: true,
                                icon: PhosphorIconsBold.moped,
                                title: tr('إدارة التوصيل'),
                                sub: tr('شركات التوصيل والمناديب'),
                                tint: AppColors.success,
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        const DeliveryManagementPicposScreen(),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
               SettingsBlockSpan(
                span: 12,
                child: SettingsBlock(
                  title: tr('شاشة العميل'),
                  subtitle: tr('العرضُ الخارجيُّ ووصلتُه'),
                  tint: AppColors.info,
                  child: const _CFDSettingsCard(),
                ),
              ),
              if (features.kitchenEnabled) ...[
                 SettingsBlockSpan(
                  span: 12,
                  child: SettingsBlock(
                    title: tr('شاشة المطبخ'),
                    subtitle: tr('توزيعُ أوامر الشغل على الأقسام'),
                    tint: AppColors.warning,
                    child: PermissionGuard(
                      permission: PermissionCodes.kdsSettings,
                      allowManagerOverride: true,
                      actionName: tr('إعدادات شاشة المطبخ'),
                      child: const KdsSettingsWidget(),
                    ),
                  ),
                ),
                SettingsBlockSpan(
                  span: 12,
                  child: SettingsBlock(
                    title: tr('الإضافات والمعدلات'),
                    subtitle: tr('مجموعات الإضافات والخيارات للأصناف'),
                    tint: AppColors.warning,
                    // ⚠️ `onGranted` باقٍ: هو المسارُ الذي يفتح الشاشةَ بعد
                    //    موافقةِ المسؤول، وحذفُه يجعل الموافقةَ بلا أثر.
                    child: PermissionGuard(
                      permission: PermissionCodes.modifiersManage,
                      allowManagerOverride: true,
                      actionName: tr('إدارة الإضافات والمعدلات'),
                      onGranted: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const ModifierManagementWidget(),
                        ),
                      ),
                      child: SettingsRowsBody(
                        children: [
                          SettingsValueRow(
                            first: true,
                            icon: PhosphorIconsBold.forkKnife,
                            title: tr('إدارة الإضافات والمعدلات'),
                            sub: tr('مجموعات الإضافات والخيارات للأصناف'),
                            tint: AppColors.warning,
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const ModifierManagementWidget(),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      )
;

  _SettingsSection _buildAboutSection(BuildContext context, ThemeMode themeMode, FeaturePolicy features, BusinessProfile profile) => 
      _SettingsSection(
        id: 'about',
        title: tr('عن البرنامج'),
        icon: PhosphorIconsBold.info,
        group: tr('الامتدادات'),
        desc: tr('الإصدار · الترخيص · التشخيص'),
        keywords: tr('إصدار نسخة ترخيص تفعيل لوج تشخيصي مطور دعم'),
        children: () => [
          // ═══ 8. عن البرنامج والترخيص ═══
          _buildAboutCard(),

          const SizedBox(height: 16),
          _buildLicenseCard(context, ref),

          // P5: "Copy Diagnostic Log" card — visible to ALL users.
          // Lets a cashier/manager who hits a problem pull the
          // last 200 log lines and send them to the admin without
          // needing access to the developer-tools screen or the
          // Documents folder. Pure read-only operation — no
          // sensitive data exposure beyond what's already in the
          // log file.
          const SizedBox(height: 16),
          _buildCopyLogCard(context),

          // Phase D: developer-tools entry. The screen
          // self-gates with a password — this tile is just a
          // discoverable surface for the developer.
          //
          // P5 (visibility update): expose the tile to system
          // admins in Release builds too — admin users routinely
          // need DB diagnostics and feature toggles. The screen
          // itself remains password-protected (PBKDF2-SHA256), so
          // accidental navigation by a non-developer admin is
          // still safe — they hit the password prompt and stop.
          // Non-admin users (cashier/manager) never see the tile,
          // matching the previous Release behaviour for them.
          Consumer(
            builder: (context, ref, _) {
              final permsAsync =
                  ref.watch(currentUserPermissionsProvider);
              final isAdmin = permsAsync.maybeWhen(
                data: (codes) =>
                    codes.contains('system_admin') ||
                    codes.contains('*'),
                orElse: () => false,
              );
              if (!kDebugMode && !isAdmin) {
                return const SizedBox.shrink();
              }
              return Padding(
                padding: const EdgeInsets.only(top: 16),
                child: _buildDeveloperToolsCard(context),
              );
            },
          ),
        ],
      )
;

}
