part of 'settings_picpos_screen.dart';

extension _SettingsPicposAbout on _SettingsPicposScreenState {
  Widget _buildAboutCard() {
    // كان `Card(elevation: 2)` — آخر أربع كروت فضلوا بالشكل المرفوع بتاع
    // UralCash جنب كروت PicPos المسطّحة، فالشاشة كانت بتبان نصّين تصميم.
    return PicPosContentCard(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // Logo
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.asset(Brand.logoAsset, fit: BoxFit.contain),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              Brand.name,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: AppColors.primary,
              ),
            ),
             Text(
              tr('نظام الكاشير المتكامل'),
              style: const TextStyle(color: AppColors.textMuted),
            ),
            const SizedBox(height: 8),
            // ⚠️ **كان نصّاً ثابتاً `'الإصدار 1.0.0'`** — بلاغُ المالك
            // 2026-08-22: «رقمُ الإصدار لا يظهر تحديثُه في إعدادات النظام».
            //
            // والسببُ ليس أن القيمةَ غيرُ متاحة: `AppVersionService.initialize()`
            // تُنادى في `main.dart` **قبل** `runApp` وتملأ
            // [AppConstants.appVersion] من `pubspec` عبر `package_info_plus`
            // (‏وهي اليومَ 3.1.3+248). الكارتُ وحدَه كان يطبع حرفاً محفوراً
            // فلا يتحرّك مهما تغيّرت النسخة — فيقرأ المشغّلُ نسخةً غيرَ التي
            // يشغّلها، وهو أسوأُ من ألّا يُعرض رقمٌ أصلاً.
            //
            // ورقمُ البناء يُعرض معه: نسختان بنفس الرقم وبناءَين مختلفَين
            // تقعان فعلاً بين إصدارَين تجريبيَّين، والرقمُ وحدَه لا يفرّقهما.
            Text(
              tr('الإصدار {p0} ({p1})', {'p0': AppConstants.appVersion, 'p1': AppConstants.appBuildNumber}),
              style: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 12,
              ),
            ),
            // Vendor block — values from `Brand`. A brand that declares no
            // vendor info renders nothing here; printing another product's
            // support contacts is worse than printing none.
            if (Brand.hasVendorInfo) ...[
              const Divider(height: 24),
               Text(
                tr('تطوير: {p0}', {'p0': Brand.vendorName}),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              // Contact Links
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  _buildContactChip(
                    PhosphorIconsBold.envelope,
                    Brand.vendorEmail,
                  ),
                  _buildContactChip(
                      PhosphorIconsBold.globe, Brand.vendorWebsite),
                  _buildContactChip(
                    PhosphorIconsBold.whatsappLogo,
                    Brand.vendorPhone,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Social Icons Row
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    icon: const Icon(
                      PhosphorIconsBold.facebookLogo,
                      color: Color(0xFF1877F2),
                    ),
                    onPressed: () =>
                        launchUrl(Uri.parse(Brand.vendorFacebookUrl)),
                    tooltip: 'Facebook',
                  ),
                  IconButton(
                    icon: const Icon(
                      PhosphorIconsBold.instagramLogo,
                      color: Color(0xFFE4405F),
                    ),
                    onPressed: () =>
                        launchUrl(Uri.parse(Brand.vendorInstagramUrl)),
                    tooltip: 'Instagram',
                  ),
                  IconButton(
                    icon: const Icon(
                      PhosphorIconsBold.whatsappLogo,
                      color: Color(0xFF25D366),
                    ),
                    onPressed: () =>
                        launchUrl(Uri.parse(Brand.vendorWhatsappUrl)),
                    tooltip: 'WhatsApp',
                  ),
                ],
              ),
              const SizedBox(height: 4),
              const Text(
                '© 2026 ${Brand.vendorName}',
                style: TextStyle(color: AppColors.textMuted, fontSize: 10),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildLicenseCard(BuildContext context, WidgetRef ref) {
    final activationAsync = ref.watch(activationStatusProvider);

    return activationAsync.when(
      // مسطّح زي باقي كروت PicPos، بس بحد ملوّن بيفرّق حالة التفعيل — الحد
      // هنا معلومة مش زينة، فاتساب على `Container` بدل `PicPosContentCard`
      // اللي حدّه ثابت.
      data: (isActivated) => Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: context.picposCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isActivated
                ? AppColors.success.withValues(alpha: 0.5)
                : AppColors.warning.withValues(alpha: 0.5),
          ),
        ),
        child: ListTile(
          leading: Icon(
            isActivated
                ? PhosphorIconsBold.checkCircle
                : PhosphorIconsBold.info,
            color: isActivated ? AppColors.success : AppColors.warning,
          ),
          title: Text(
            isActivated ? tr('النسخة مفعلة بالكامل') : tr('نسخة تجريبية محدودة'),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          subtitle: Text(
            isActivated
                ? tr('لديك صلاحية الوصول لكافة مميزات النظام بدون قيود.')
                : tr('هذه النسخة محدودة بـ 50 صنف/عميل. قم بالتفعيل لإزالة القيود.'),
            style: const TextStyle(fontSize: 12),
          ),
          trailing: isActivated
              ? null
              : buildLicenseActivateButtonGuarded(
                  onOpen: () => showActivationDialog(context, picpos: true),
                ),
        ),
      ),
      loading: () =>
           Card(child: ListTile(title: Text(tr('جاري التحقق من الترخيص...')))),
      error: (_, _) =>
           Card(child: ListTile(title: Text(tr('خطأ في التحقق من الترخيص')))),
    );
  }

  /// Phase D: surface for opening the developer-tools screen. The
  /// screen itself prompts for the developer password — this tile only
  /// makes the entry discoverable to anyone who can read the settings
  /// page (admin or higher).
  Widget _buildDeveloperToolsCard(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
      ),
      child: ListTile(
        leading: const Icon(
          PhosphorIconsBold.shieldStar,
          color: AppColors.primary,
        ),
        title:  Text(
          tr('أدوات المطوّر'),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle:  Text(
          tr('تغيير ملف النشاط، نمط التشغيل، الميزات وكلمة مرور المطوّر (محمى بكلمة مرور منفصلة).'),
          style: const TextStyle(fontSize: 12),
        ),
        trailing: const Icon(PhosphorIconsBold.caretLeft),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const DeveloperToolsPicposScreen(),
          ),
        ),
      ),
    );
  }

  /// P5: Copies the last 200 lines of the diagnostic log to clipboard.
  /// Visible to every user — a cashier who hits a problem can grab the log
  /// in two taps and WhatsApp it to the admin without leaving the app or
  /// needing access to developer tools.
  Widget _buildCopyLogCard(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.info.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.info.withValues(alpha: 0.25)),
      ),
      child: ListTile(
        leading: const Icon(
          PhosphorIconsBold.clipboard,
          color: AppColors.info,
        ),
        title:  Text(
          tr('نسخ اللوج التشخيصى'),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle:  Text(
          tr('انسخ آخر 200 سطر من سجل التشخيص لإرساله للمدير عند حدوث مشكلة.'),
          style: const TextStyle(fontSize: 12),
        ),
        trailing: const Icon(PhosphorIconsBold.copy),
        onTap: () async {
          try {
            final dir = await getApplicationDocumentsDirectory();
            final candidates = <String>{
              // Spec 136 ISS-5 — the active mode-labelled login log first,
              // then the legacy unlabelled name for older sessions.
              DiagnosticLogger.currentFileName,
              '${Brand.dbPrefix}_login_log.txt',
              '${Brand.dbPrefix}_startup_log.txt',
              'server_errors.log',
            }.toList();
            final buffer = StringBuffer();
            for (final name in candidates) {
              final f = File('${dir.path}/$name');
              if (!await f.exists()) continue;
              final lines = await f.readAsLines();
              final tail = lines.length > 200
                  ? lines.sublist(lines.length - 200)
                  : lines;
              buffer
                ..writeln('═══════════════════════════════════════════')
                ..writeln('FILE: $name (last ${tail.length} lines)')
                ..writeln('═══════════════════════════════════════════');
              for (final l in tail) {
                buffer.writeln(l);
              }
              buffer.writeln();
            }
            if (buffer.isEmpty) {
              if (context.mounted) {
                AppToast.show(
                  context,
                  tr('لا توجد ملفات لوج بعد'),
                  type: ToastType.warning,
                );
              }
              return;
            }
            await Clipboard.setData(ClipboardData(text: buffer.toString()));
            if (context.mounted) {
              AppToast.show(
                context,
                tr('تم نسخ اللوج إلى الحافظة — الصقه فى الواتساب أو الإيميل'),
                type: ToastType.success,
              );
            }
          } catch (e) {
            if (context.mounted) {
              AppToast.show(
                context,
                tr('تعذّر قراءة اللوج: {e}', {'e': e}),
                type: ToastType.error,
              );
            }
          }
        },
      ),
    );
  }

  Widget _buildContactChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: context.picposField,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.picposHairline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppColors.primary),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}
