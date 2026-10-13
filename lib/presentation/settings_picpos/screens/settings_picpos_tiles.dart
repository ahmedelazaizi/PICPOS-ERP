part of 'settings_picpos_screen.dart';

/// مربّعاتُ «المستخدمون والأدوار».
///
/// الحارسُ على الضغطة لا على العرض — لنفس سببِ [_DeviceTiles]، وبنفس
/// أكواد الصلاحيات: `usersManage` للحسابات و`rolesManage` للأدوار.
class _UserTiles extends ConsumerWidget {
  const _UserTiles();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Future<void> guarded(
      String permission,
      String actionName,
      VoidCallback open,
    ) async {
      final ok = await ensurePermission(
        ref,
        context,
        permission,
        actionName: actionName,
      );
      if (ok && context.mounted) open();
    }

    return SettingsTilesBlock(
      columns: 2,
      tiles: [
        SettingsTile(
          icon: PhosphorIconsBold.usersThree,
          title: tr('إدارة المستخدمين'),
          sub: tr('إضافة مستخدمين وتغيير كلمات المرور'),
          meta: tr('الحساباتُ والدخول'),
          tint: AppColors.primary,
          onTap: () => guarded(
            PermissionCodes.usersManage,
            tr('إدارة المستخدمين'),
            () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const UsersManagementPicposScreen(),
              ),
            ),
          ),
        ),
        SettingsTile(
          icon: PhosphorIconsBold.table,
          title: tr('مصفوفة الأدوار والصلاحيات'),
          sub: tr('قارن الأدوار جنباً إلى جنب وبدّل الصلاحية في مكانها'),
          meta: tr('مصفوفةٌ لا دورٌ واحد'),
          tint: AppColors.warning,
          onTap: () => guarded(
            PermissionCodes.rolesManage,
            tr('إدارة صلاحيات الأدوار'),
            () => showPermissionsMatrixPicpos(context),
          ),
        ),
      ],
    );
  }
}

/// مربّعاتُ «إدارة الأجهزة» — بلوكُ `tiles` في قسم الأجهزة من التصميم.
///
/// ⚠️ **الحارسُ انتقل من العرض إلى الضغطة، وهذا تشديدٌ لا تخفيف.**
/// كانت الصفوفُ ملفوفةً بـ`PermissionGuard(allowManagerOverride: true)`،
/// وهو يحرس **الودجت**: يُخفي الصفَّ أو يطلب موافقةَ مسؤول. و`SettingsTile`
/// وصفُ بياناتٍ لا ودجت، فلا يُلفّ.
///
/// فبدل إسقاطِ الحراسة أو إخفاءِ المربّع، تُحرَس الضغطةُ بـ`ensurePermission`
/// — وهي **القِمع** الذي تمرُّ منه كلُّ المداخل، وتستهلك موافقةَ المسؤول من
/// `ManagerApprovalCache` فلا يُسأل مرّتين. أي أنّ `allowManagerOverride`
/// محفوظٌ بحرفه، والحمايةُ صارت فعليّةً لا بصريّة.
class _DeviceTiles extends ConsumerWidget {
  const _DeviceTiles();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Future<void> guarded(
      String permission,
      String actionName,
      VoidCallback open,
    ) async {
      final ok = await ensurePermission(
        ref,
        context,
        permission,
        actionName: actionName,
      );
      if (ok && context.mounted) open();
    }

    return SettingsTilesBlock(
      tiles: [
        SettingsTile(
          icon: PhosphorIconsBold.printer,
          title: tr('إعدادات الأجهزة'),
          sub: tr('الماسح والطابعة الحرارية والميزان'),
          // ⚠️ وصفٌ لا عدّاد: التصميمُ يعرض «٤ طابعات معرّفة» وهو رقمُ
          //    عرضٍ في ملفّ التصميم لا شيءٌ تحمله القاعدةُ اليوم.
          meta: tr('ماسح · طابعة · ميزان'),
          tint: AppColors.info,
          onTap: () => guarded(
            PermissionCodes.settingsPrinter,
            tr('إعدادات الأجهزة'),
            () => showHardwareSettingsDialog(context, picpos: true),
          ),
        ),
        SettingsTile(
          icon: PhosphorIconsBold.printer,
          title: tr('إدارة الطابعات'),
          sub: tr('طابعات أوامر الشغل للأقسام'),
          meta: tr('توزيعُ الطباعة على الأقسام'),
          tint: AppColors.secondary,
          onTap: () => guarded(
            PermissionCodes.settingsPrinter,
            tr('إدارة الطابعات'),
            () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const PrintersPicposScreen()),
            ),
          ),
        ),
        SettingsTile(
          icon: PhosphorIconsBold.cashRegister,
          title: tr('نقاط البيع'),
          sub: tr('إدارة الماكينات وسياسة نقص الخامات'),
          meta: tr('سياسةٌ لكل نقطة'),
          tint: AppColors.primary,
          onTap: () => guarded(
            PermissionCodes.settingsPrinter,
            tr('نقاط البيع'),
            () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => const PosTerminalsPicposScreen()),
            ),
          ),
        ),
        SettingsTile(
          icon: PhosphorIconsBold.books,
          title: tr('مكتبة النماذج'),
          sub: tr('استعراضُ قوالب الطباعة وربطُها بالمستندات'),
          meta: tr('المطبوعات'),
          tint: AppColors.info,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const TemplateLibraryPicposScreen(),
            ),
          ),
        ),
        // بلوغٌ ثانٍ لشاشةِ الحسم بجوار المكتبة: من يربط قالباً هنا يسأل
        // فوراً «هل وصل؟» — والقائمةُ الجانبيّةُ بعيدةٌ عن لحظة السؤال.
        SettingsTile(
          icon: PhosphorIconsBold.gitFork,
          title: tr('حسم القوالب'),
          sub: tr('أيُّ مستندٍ يخرج بأيِّ قالبٍ — وسلسلةُ السقوط'),
          meta: tr('تشخيصُ الطباعة'),
          tint: AppColors.info,
          onTap: () => guarded(
            PermissionCodes.settingsPrinter,
            tr('حسم القوالب'),
            () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const TemplateResolutionPicposScreen(),
              ),
            ),
          ),
        ),
        // ⚠️ **السطحُ القديمُ باقٍ عن قصدٍ لا عن إهمال**: هو الوحيدُ الذي
        //    يحرّر **ملصقاتِ الباركود** (‏`templateCategory == 'barcode'`)،
        //    والمكتبةُ تُرشِّحها والمحرّرُ الجديدُ لا يخدمها. فإخفاؤه كان
        //    سيُلغي الطريقَ الوحيدَ لتعديل الملصقات.
        //
        //    وتحريرُ قوالب الفواتير مدخلُه **المكتبة**: المحرّرُ الجديدُ يفتح
        //    على قالبٍ بعينه (`templateId`)، فلا معنى لفتحه بلا اختيار.
        SettingsTile(
          icon: PhosphorIconsBold.barcode,
          title: tr('مصمّم ملصقات الباركود'),
          sub: tr('السطحُ القديم — ملصقاتُ الباركود وقوالبُها'),
          meta: tr('الملصقات'),
          tint: AppColors.info,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const InvoiceDesignerScreen(picposChrome: true),
            ),
          ),
        ),
      ],
    );
  }
}

class _AdvancedTiles extends ConsumerWidget {
  const _AdvancedTiles({required this.onOpenConnections});

  final VoidCallback onOpenConnections;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = NetworkService.instance.mode;
    final isServer = NetworkService.instance.isServer;

    return SettingsTilesBlock(
      tiles: [
        SettingsTile(
          icon: PhosphorIconsBold.database,
          title: tr('قاعدة البيانات'),
          sub: tr('نوع القاعدة ومسارها'),
          meta: tr('إعدادات الاتصال'),
          tint: AppColors.success,
          dot: AppColors.success,
          onTap: () => showDatabaseSettingsDialog(context),
        ),
        SettingsTile(
          icon: PhosphorIconsBold.wifiHigh,
          title: tr('الربط بين الفروع والسيرفر'),
          sub: tr('وضع الشبكة والمزامنة'),
          // ⚠️ الحالةُ من `NetworkService` الحيّ لا نصٌّ ثابت.
          meta: switch (mode) {
            NetworkMode.server => tr('سيرفر رئيسي'),
            NetworkMode.client => tr('عميل مرتبط'),
            NetworkMode.mirror => tr('مرآة'),
            _ => tr('مستقل'),
          },
          tint: AppColors.primary,
          dot: isServer ? AppColors.success : AppColors.primary,
          onTap: onOpenConnections,
        ),
        SettingsTile(
          icon: PhosphorIconsBold.shield,
          title: tr('أدوات صيانة المسؤول'),
          sub: tr('حصر الفروع وتشخيص القيود'),
          meta: tr('أدوات تشخيصية'),
          tint: AppColors.warning,
          onTap: () => showBranchScopeAdminDialog(context),
         ),
         SettingsTile(
           icon: PhosphorIconsBold.currencyCircleDollar,
           title: tr('أسعار الصرف وإعادة التقييم'),
           sub: tr('إدارة العملات وقيد فروق الصرف الدوري'),
           meta: tr('معاينة ثم تنفيذ محمي'),
           tint: AppColors.info,
           permission: PermissionCodes.accountingJournal,
           onTap: () => Navigator.push(
             context,
             MaterialPageRoute(builder: (_) => const ExchangeRateScreen()),
           ),
         ),
         SettingsTile(
           icon: PhosphorIconsBold.scales,
           title: tr('تدقيق أرصدة الأطراف'),
           sub: tr('مقارنة أرصدة العملاء والموردين بالأستاذ'),
           meta: tr('إعادة احتساب محمية بالصلاحية'),
           tint: AppColors.warning,
           permission: PermissionCodes.accountingJournal,
           onTap: () {
             final userId = ref.read(authProvider).effectiveUser?.id;
             if (userId == null) return;
             showPartyBalanceRepairDialog(
               context,
               repository: ref.read(partiesRepositoryProvider),
               userId: userId,
             );
           },
         ),
         // ⚠️ التدقيقان مشروطان بالوضع لا معطَّلَين فيه: تدقيقُ المرآة
        //    يقارن بالسيرفر فلا معنى له في وضعٍ مستقلّ، وتدقيقُ الشيكات
        //    يقرأ سجلَّ السيرفر. ومربّعٌ حاضرٌ لا يعمل يُسأل عنه.
        if (mode == NetworkMode.mirror)
          SettingsTile(
            icon: PhosphorIconsBold.arrowsCounterClockwise,
            title: tr('تدقيق مزامنة المرآة'),
            sub: tr('مقارنة البيانات الأساسية بالسيرفر'),
            meta: tr('قراءةٌ ثمّ إعادةُ مزامنة'),
            tint: AppColors.primary,
            onTap: () => showMirrorParityAuditDialog(context),
          ),
        if (isServer)
          SettingsTile(
            icon: PhosphorIconsBold.magnifyingGlass,
            title: tr('تدقيق ازدواج شيكات القبض'),
            sub: tr('أرصدةٌ تأثّرت بازدواج سندات القبض'),
            meta: tr('قراءةٌ فقط — الإصلاحُ مؤجَّل'),
            tint: AppColors.warning,
            onTap: () => showChequeReceiptDriftAdminDialog(context),
          ),
      ],
    );
  }
}

/// حوارُ وضع الشبكة — يُفتح من قسم «ربط التطبيقات والأجهزة» وحده.
Future<void> _showNetworkModeDialog(BuildContext context) => showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: const SingleChildScrollView(
            padding: EdgeInsets.all(16),
            child: _NetworkModeSettings(),
          ),
        ),
      ),
    );
