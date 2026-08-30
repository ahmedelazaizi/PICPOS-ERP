// نسخة حرفية من lib/presentation/screens/settings/admin_home_settings.dart
// (مصيدة النسخ §٥.٨) — أي إصلاح منطقي يتصلّح في المصدر أولاً ثم يُنقل بـ patch
// لهذا الملف. لا يُنسخ أبداً من D:\URAL-ERP. `part of` فقط تغيّر — لا تعديل
// منطقي ولا تسمية (الكلاسات خاصة، لا تعارض عبر المكتبات).
//
// ملاحظة: `_AdminPasswordSetting` غير مستخدم فعلياً داخل شجرة `build()` في
// settings_screen.dart الأصلي (كود ميت) — نفس الحال هنا، انسخ فقط، لا تحذف.
part of 'settings_picpos_screen.dart';

// ═══════════════════════════════════════════════════════════════════════════
// ADMIN PASSWORD & HOME SCREEN — Settings sub-widgets
// ═══════════════════════════════════════════════════════════════════════════

/// Admin Password Setting for invoice deletion authorization
class _AdminPasswordSetting extends ConsumerStatefulWidget {
  const _AdminPasswordSetting();

  @override
  ConsumerState<_AdminPasswordSetting> createState() =>
      _AdminPasswordSettingState();
}

class _AdminPasswordSettingState extends ConsumerState<_AdminPasswordSetting> {
  void _showChangePasswordDialog() {
    final oldPasswordController = TextEditingController();
    final newPasswordController = TextEditingController();
    final confirmPasswordController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: ui.TextDirection.rtl,
        child: PicPosDialog(
          icon: PhosphorIconsBold.lock,
          title: 'تغيير كلمة سر المدير',
          subtitle: 'تُستخدم هذه الكلمة لتأكيد حذف الفواتير',
          width: 460,
          onCancel: () => Navigator.pop(ctx),
          body: [
            PicPosDialogField(
              label: 'كلمة السر الحالية',
              child: TextField(
                controller: oldPasswordController,
                obscureText: true,
                decoration: const InputDecoration(
                  prefixIcon: Icon(PhosphorIconsBold.lock),
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(height: 12),
            PicPosDialogField(
              label: 'كلمة السر الجديدة',
              child: TextField(
                controller: newPasswordController,
                obscureText: true,
                decoration: const InputDecoration(
                  prefixIcon: Icon(PhosphorIconsBold.lockKey),
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(height: 12),
            PicPosDialogField(
              label: 'تأكيد كلمة السر الجديدة',
              child: TextField(
                controller: confirmPasswordController,
                obscureText: true,
                decoration: const InputDecoration(
                  prefixIcon: Icon(PhosphorIconsBold.lockKey),
                  border: OutlineInputBorder(),
                ),
              ),
            ),
          ],
          primaryAction: PicPosDialogAction(
            label: 'حفظ',
            icon: PhosphorIconsBold.floppyDisk,
            onPressed: () async {
                final adminPwd = ref.read(adminPasswordServiceProvider);
                // Validate
                if (!(await adminPwd.verify(oldPasswordController.text))) {
                  AppToast.show(
                    ctx,
                    'كلمة السر الحالية غير صحيحة',
                    type: ToastType.error,
                  );
                  return;
                }
                if (newPasswordController.text.isEmpty) {
                  AppToast.show(
                    ctx,
                    'يرجى إدخال كلمة سر جديدة',
                    type: ToastType.error,
                  );
                  return;
                }
                if (newPasswordController.text !=
                    confirmPasswordController.text) {
                  AppToast.show(
                    ctx,
                    'كلمة السر غير متطابقة',
                    type: ToastType.error,
                  );
                  return;
                }

                // Save new password as hash
                await adminPwd.setPassword(newPasswordController.text);
                // #Forensic Log: Admin password change
                try {
                  final auth = ref.read(authProvider);
                  final logger = ref.read(activityLoggerProvider);
                  await logger.logSettingsChange(
                    auth.user?.id ?? 0,
                    auth.user?.displayName ?? '',
                    'كلمة سر المدير',
                  );
                } catch (e) {
                  debugPrint('[ActivityLog] Error: $e');
                }

                if (ctx.mounted) {
                  Navigator.pop(ctx);
                  AppToast.show(
                    ctx,
                    'تم تغيير كلمة السر بنجاح',
                    type: ToastType.success,
                  );
                }
            },
            color: AppColors.success,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(PhosphorIconsBold.lock, color: AppColors.warning),
      title: const Text('كلمة سر الحذف'),
      subtitle: const Text('تغيير كلمة السر المطلوبة لحذف الفواتير'),
      trailing: const Icon(PhosphorIconsBold.caretLeft),
      onTap: _showChangePasswordDialog,
    );
  }
}

/// UI to select the default home screen on login
class _DefaultHomeScreenSelector extends ConsumerStatefulWidget {
  const _DefaultHomeScreenSelector();

  @override
  ConsumerState<_DefaultHomeScreenSelector> createState() =>
      _DefaultHomeScreenSelectorState();
}

class _DefaultHomeScreenSelectorState
    extends ConsumerState<_DefaultHomeScreenSelector> {
  int? _selectedHomeScreenIndex;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadCurrentSetting();
  }

  Future<void> _loadCurrentSetting() async {
    final settingsRepo = ref.read(settingsRepositoryProvider);
    final val = await settingsRepo.getSetting('default_home_screen');
    if (mounted) {
      setState(() {
        _selectedHomeScreenIndex = val != null
            ? int.tryParse(val)
            : 1; // Default to POS (1)
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const SizedBox.shrink();

    // Get all screens allowed by the current flavor
    final flavorScreenIds = AppConfig.allowedScreenIds;

    // Define screen names mapping (must match main.dart allScreens)
    const screenNames = {
      ScreenId.dashboard: 'Dashboard',
      ScreenId.pos: 'البيع السريع (POS)',
      ScreenId.offers: 'العروض (Offers)',
      ScreenId.tables: 'الطاولات (Tables)',
      ScreenId.products: 'الأصناف (Products)',
      ScreenId.categories: 'التصنيفات (Categories)',
      ScreenId.parties: 'العملاء والموردين',
      ScreenId.inventory: 'المخزون (Inventory)',
      ScreenId.purchases: 'فواتير المشتريات',
      ScreenId.treasury: 'الخزينة (Treasury)',
      ScreenId.reports: 'التقارير (Reports)',
      ScreenId.settings: 'الإعدادات (Settings)',
      ScreenId.branches: 'إدارة الفروع',
      ScreenId.kitchen: 'شاشة المطبخ (KDS)',
      ScreenId.analytics: 'تحليلات المبيعات',
      ScreenId.hr: 'شؤون الموظفين (HR)',
      ScreenId.salesInvoices: 'فواتير المبيعات',
      ScreenId.activityLog: 'سجل العمليات (Audit)',
      ScreenId.inventoryBonds: 'أرصدة المخزون',
      ScreenId.stockTransfer: 'التحويل المخزني',
      ScreenId.scalePlu: 'ميزان التسعير',
      ScreenId.eInvoice: 'الفوترة الإلكترونية',
      ScreenId.loyalty: 'نقاط الولاء',
      ScreenId.distribution: 'التوزيع والمناديب',
    };

    return ListTile(
      leading: const Icon(PhosphorIconsBold.houseLine, color: AppColors.info),
      title: const Text('الشاشة الرئيسية الافتراضية'),
      subtitle: const Text('اختر الشاشة التي تفتح تلقائياً عند تسجيل الدخول'),
      trailing: DropdownButton<int>(
        value: _selectedHomeScreenIndex,
        underline: const SizedBox.shrink(),
        items: flavorScreenIds.map((screenId) {
          return DropdownMenuItem<int>(
            value: screenId.navigationIndex,
            child: Text(screenNames[screenId] ?? 'شاشة مجهولة (${screenId.navigationIndex})'),
          );
        }).toList(),
        onChanged: (newVal) async {
          if (newVal != null) {
            setState(() => _selectedHomeScreenIndex = newVal);
            await ref
                .read(settingsRepositoryProvider)
                .saveSetting('default_home_screen', newVal.toString());
            if (context.mounted) {
              AppToast.show(
                context,
                'تم حفظ الشاشة الافتراضية بنجاح',
                type: ToastType.success,
              );
            }
          }
        },
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// FORCE SYNC PANEL — Database synchronization triggering
// ═══════════════════════════════════════════════════════════════════════════

class _ForceSyncPanel extends ConsumerStatefulWidget {
  const _ForceSyncPanel();

  @override
  ConsumerState<_ForceSyncPanel> createState() => _ForceSyncPanelState();
}

class _ForceSyncPanelState extends ConsumerState<_ForceSyncPanel> {
  bool _isSyncing = false;

  Future<void> _performForceSync() async {
    // Requires admin or financial manager permissions. Previously this
    // check used hardcoded roleId==1||2, which broke on any DB where the
    // seeding order differed (role IDs are auto-increment and not stable
    // across setups). We now resolve by role NAME so the check works
    // regardless of which numeric ID the admin role happens to have.
    final authState = ref.read(authProvider);
    final currentUser = authState.user;
    if (currentUser == null) {
      AppToast.show(context,
          'صلاحية مرفوضة. هذه العملية مخصصة لمدير النظام والمدير المالي فقط.',
          type: ToastType.error);
      return;
    }

    // First: authState.isAdmin is the canonical admin check (resolved against
    // the user's role.name). Also accept "مدير مالى" / "المدير المالي" by name.
    bool canForceSync = authState.isAdmin;
    if (!canForceSync && currentUser.roleId != null) {
      try {
        final db = ref.read(databaseProvider);
        final role = await db.getRoleById(currentUser.roleId!);
        if (role != null) {
          final name = role.name.trim();
          canForceSync = name == 'مدير النظام' ||
              name == 'مدير مالى' ||
              name == 'المدير المالي' ||
              name == 'مدير مالي' ||
              role.isSystemRole;
        }
      } catch (_) { /* fall through to deny */ }
    }

    if (!canForceSync) {
      if (mounted) {
        AppToast.show(context,
            'صلاحية مرفوضة. هذه العملية مخصصة لمدير النظام والمدير المالي فقط.',
            type: ToastType.error);
      }
      return;
    }

    setState(() => _isSyncing = true);

    try {
      final syncRepo = ref.read(syncRepositoryProvider);
      final serverUrl = await ref.read(settingsRepositoryProvider).getSetting('server_url') ?? 'http://localhost:8080';
      await syncRepo.performFullSync(serverUrl);

      if (mounted) {
        AppToast.show(context, 'تم جلب البيانات وإتمام المزامنة الإجبارية بنجاح.', type: ToastType.success);
      }
    } catch (e) {
      if (mounted) {
        AppToast.show(context, 'فشل المزامنة الإجبارية: \$e', type: ToastType.error);
      }
    } finally {
      if (mounted) {
        setState(() => _isSyncing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.primary.withOpacity(0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.primary.withOpacity(0.3)),
        ),
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(PhosphorIconsBold.arrowsClockwise, color: AppColors.primary),
                SizedBox(width: 8),
                Text(
                  'المزامنة الإجبارية (Smart Sync)',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'أداة النجدة للمدير المالي ومدير النظام. تقوم هذه العملية بالاتصال المباشر بالسيرفر لجلب جميع التحديثات وإجبار المزامنة لحل أي تعارض في البيانات أو الأرصدة.',
              style: TextStyle(color: AppColors.textMuted, fontSize: 13),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isSyncing ? null : _performForceSync,
                icon: _isSyncing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(PhosphorIconsBold.cloudArrowDown),
                label: Text(_isSyncing ? 'جاري السحب والمزامنة بطريقة آمنة...' : 'بدء المزامنة الذكية الآن'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
