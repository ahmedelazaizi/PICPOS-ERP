// لوحة «الوصول من المتصفح» في إعدادات السيرفر (م3-9).
//
// مطفأة افتراضياً. عند التفعيل (يسري عند إعادة تشغيل السيرفر):
//   * يقدّم السيرفر ملفات `build/web` من نفس الأصل،
//   * يفتح كتابات جلسة الويب (`ApiAuthMiddleware.enableWebSessionWrites`)،
//   * يضبط `WebOriginPolicy` بالأصول المذكورة (فارغ = نفس الأصل فقط).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:ural_erp/core/i18n/tr.dart';

import '../../../core/design_system/typography.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/providers/providers.dart';
import '../../../services/api/web_static_handler.dart';
import '../../picpos_shell/picpos_surface.dart';

class WebAccessSettingsPanel extends ConsumerStatefulWidget {
  const WebAccessSettingsPanel({super.key});

  @override
  ConsumerState<WebAccessSettingsPanel> createState() =>
      _WebAccessSettingsPanelState();
}

class _WebAccessSettingsPanelState
    extends ConsumerState<WebAccessSettingsPanel> {
  final _origins = TextEditingController();
  final _dir = TextEditingController();
  bool _enabled = false;

  @override
  void initState() {
    super.initState();
    final repo = ref.read(syncRepositoryProvider);
    _enabled = repo.webAccessEnabled;
    _origins.text = repo.webAllowedOrigins.join('\n');
    _dir.text = repo.webStaticDir ?? '';
  }

  @override
  void dispose() {
    _origins.dispose();
    _dir.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    await ref.read(syncRepositoryProvider).configureWebAccess(
          enabled: _enabled,
          allowedOrigins: _origins.text.split(RegExp(r'[\n,;]')),
          staticDir: _dir.text,
        );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(tr('تم حفظ إعدادات الويب — أعد تشغيل السيرفر لتطبيقها'))),
    );
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final dir = _dir.text.trim();
    final missingBuild = _enabled && dir.isNotEmpty && !WebStaticHandler.hasBuild(dir);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.picposField,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(PhosphorIconsBold.globe, color: AppColors.primary),
              const SizedBox(width: 8),
              Text(tr('تفعيل الوصول من المتصفح'), style: AppTypography.bodyLarge),
              const Spacer(),
              Switch(
                value: _enabled,
                onChanged: (v) => setState(() => _enabled = v),
              ),
            ],
          ),
          Text(
            tr('يقدّم السيرفر نسخة الويب ويقبل كتابات جلسة المتصفح. مطفأ افتراضياً.'),
            style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _origins,
            minLines: 1,
            maxLines: 4,
            decoration: InputDecoration(
              labelText: tr('الأصول المسموحة (Origins) — فارغ = نفس الأصل فقط'),
              hintText: 'https://erp.example.com',
              isDense: true,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _dir,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: tr('مجلد ملفات الويب (build/web)'),
              isDense: true,
            ),
          ),
          if (missingBuild) ...[
            const SizedBox(height: 6),
            Text(
              tr('لم يُعثر على index.html في المجلد المحدد'),
              style: const TextStyle(fontSize: 11, color: AppColors.error),
            ),
          ],
          const SizedBox(height: 8),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: FilledButton(
              onPressed: _save,
              child: Text(tr('حفظ إعدادات الويب')),
            ),
          ),
        ],
      ),
    );
  }
}
