part of '../settings_screen.dart';

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
        child: AlertDialog(
          title:  Row(
            children: [
              const Icon(PhosphorIconsBold.lock, color: AppColors.primary),
              const SizedBox(width: 8),
              Text(tr('تغيير كلمة سر المدير')),
            ],
          ),
          content: SizedBox(
            width: 350,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                 Text(
                  tr('تُستخدم هذه الكلمة لتأكيد حذف الفواتير'),
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: oldPasswordController,
                  obscureText: true,
                  decoration:  InputDecoration(
                    labelText: tr('كلمة السر الحالية'),
                    prefixIcon: const Icon(PhosphorIconsBold.lock),
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: newPasswordController,
                  obscureText: true,
                  decoration:  InputDecoration(
                    labelText: tr('كلمة السر الجديدة'),
                    prefixIcon: const Icon(PhosphorIconsBold.lockKey),
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: confirmPasswordController,
                  obscureText: true,
                  decoration:  InputDecoration(
                    labelText: tr('تأكيد كلمة السر الجديدة'),
                    prefixIcon: const Icon(PhosphorIconsBold.lockKey),
                    border: const OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child:  Text(tr('إلغاء')),
            ),
            ElevatedButton.icon(
              onPressed: () async {
                final adminPwd = ref.read(adminPasswordServiceProvider);
                // Validate
                if (!(await adminPwd.verify(oldPasswordController.text))) {
                  if (!ctx.mounted) return;
                  AppToast.show(
                    ctx,
                    tr('كلمة السر الحالية غير صحيحة'),
                    type: ToastType.error,
                  );
                  return;
                }
                if (newPasswordController.text.isEmpty) {
                  if (!ctx.mounted) return;
                  AppToast.show(
                    ctx,
                    tr('يرجى إدخال كلمة سر جديدة'),
                    type: ToastType.error,
                  );
                  return;
                }
                if (newPasswordController.text !=
                    confirmPasswordController.text) {
                  if (!ctx.mounted) return;
                  AppToast.show(
                    ctx,
                    tr('كلمة السر غير متطابقة'),
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
                    tr('كلمة سر المدير'),
                  );
                } catch (e) {
                  debugPrint('[ActivityLog] Error: $e');
                }

                if (ctx.mounted) {
                  Navigator.pop(ctx);
                  AppToast.show(
                    ctx,
                    tr('تم تغيير كلمة السر بنجاح'),
                    type: ToastType.success,
                  );
                }
              },
              icon: const Icon(PhosphorIconsBold.check),
              label:  Text(tr('حفظ')),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.success,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(PhosphorIconsBold.lock, color: AppColors.warning),
      title:  Text(tr('كلمة سر الحذف')),
      subtitle:  Text(tr('تغيير كلمة السر المطلوبة لحذف الفواتير')),
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
    final screenNames = {
      ScreenId.dashboard: 'Dashboard',
      ScreenId.pos: tr('البيع السريع (POS)'),
      ScreenId.offers: tr('العروض (Offers)'),
      ScreenId.tables: tr('الطاولات (Tables)'),
      ScreenId.products: tr('الأصناف (Products)'),
      ScreenId.categories: tr('التصنيفات (Categories)'),
      ScreenId.parties: tr('العملاء والموردين'),
      ScreenId.inventory: tr('المخزون (Inventory)'),
      ScreenId.purchases: tr('فواتير المشتريات'),
      ScreenId.treasury: tr('الخزينة (Treasury)'),
      ScreenId.reports: tr('التقارير (Reports)'),
      ScreenId.settings: tr('الإعدادات (Settings)'),
      ScreenId.branches: tr('إدارة الفروع'),
      ScreenId.kitchen: tr('شاشة المطبخ (KDS)'),
      ScreenId.analytics: tr('تحليلات المبيعات'),
      ScreenId.hr: tr('شؤون الموظفين (HR)'),
      ScreenId.salesInvoices: tr('فواتير المبيعات'),
      ScreenId.activityLog: tr('سجل العمليات (Audit)'),
      ScreenId.inventoryBonds: tr('أرصدة المخزون'),
      ScreenId.stockTransfer: tr('التحويل المخزني'),
      ScreenId.scalePlu: tr('ميزان التسعير'),
      ScreenId.eInvoice: tr('الفوترة الإلكترونية'),
      ScreenId.loyalty: tr('نقاط الولاء'),
      ScreenId.distribution: tr('التوزيع والمناديب'),
    };

    return ListTile(
      leading: const Icon(PhosphorIconsBold.houseLine, color: AppColors.info),
      title:  Text(tr('الشاشة الرئيسية الافتراضية')),
      subtitle:  Text(tr('اختر الشاشة التي تفتح تلقائياً عند تسجيل الدخول')),
      trailing: DropdownButton<int>(
        value: _selectedHomeScreenIndex,
        underline: const SizedBox.shrink(),
        items: flavorScreenIds.map((screenId) {
          return DropdownMenuItem<int>(
            value: screenId.navigationIndex,
            child: Text(screenNames[screenId] ?? tr('شاشة مجهولة ({p0})', {'p0': screenId.navigationIndex})),
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
                tr('تم حفظ الشاشة الافتراضية بنجاح'),
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
          tr('صلاحية مرفوضة. هذه العملية مخصصة لمدير النظام والمدير المالي فقط.'),
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
            tr('صلاحية مرفوضة. هذه العملية مخصصة لمدير النظام والمدير المالي فقط.'),
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
        AppToast.show(context, tr('تم جلب البيانات وإتمام المزامنة الإجبارية بنجاح.'), type: ToastType.success);
      }
    } catch (e) {
      if (mounted) {
        AppToast.show(context, tr('فشل المزامنة الإجبارية: \$e'), type: ToastType.error);
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
             Row(
              children: [
                const Icon(PhosphorIconsBold.arrowsClockwise, color: AppColors.primary),
                const SizedBox(width: 8),
                Text(
                  tr('المزامنة الإجبارية (Smart Sync)'),
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ],
            ),
            const SizedBox(height: 8),
             Text(
              tr('أداة النجدة للمدير المالي ومدير النظام. تقوم هذه العملية بالاتصال المباشر بالسيرفر لجلب جميع التحديثات وإجبار المزامنة لحل أي تعارض في البيانات أو الأرصدة.'),
              style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
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
                label: Text(_isSyncing ? tr('جاري السحب والمزامنة بطريقة آمنة...') : tr('بدء المزامنة الذكية الآن')),
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
