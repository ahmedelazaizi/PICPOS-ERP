import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:picpos_erp/core/i18n/tr.dart';
import 'package:picpos_erp/core/widgets/app_toast.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/providers/providers.dart';
import '../../picpos_shell/picpos_surface.dart';
import '../../pos/services/scale_barcode_config.dart';
import '../../pos/services/scale_barcode_encoder.dart';
import 'scale_barcode_preview.dart';

/// رسالة كل خطأ إعداد — تُستدعى من `build` (‏`tr()` وقتَ الرسم).
String scaleBarcodeIssueText(ScaleBarcodeIssue issue) => switch (issue) {
  ScaleBarcodeIssue.weightPrefixInvalid => tr(
    'بادئة الوزن: أرقام فقط، تبدأ بـ2، من 1 إلى 4 خانات',
  ),
  ScaleBarcodeIssue.pricePrefixInvalid => tr(
    'بادئة السعر: أرقام فقط، تبدأ بـ2، من 1 إلى 4 خانات',
  ),
  ScaleBarcodeIssue.fallbackPrefixInvalid => tr(
    'البادئة البديلة للوزن: أرقام فقط، تبدأ بـ2، من 1 إلى 4 خانات',
  ),
  ScaleBarcodeIssue.weightCodeLenInvalid => tr(
    'خانات PLU للوزن لا تتسع: البادئة + PLU يجب أن تترك خانة قيمة واحدة على الأقل من 12',
  ),
  ScaleBarcodeIssue.priceCodeLenInvalid => tr(
    'خانات PLU للسعر لا تتسع: البادئة + PLU يجب أن تترك خانة قيمة واحدة على الأقل من 12',
  ),
  ScaleBarcodeIssue.weightDividerInvalid => tr(
    'معامل قسمة الوزن يجب أن يكون 1 أو 10 أو 100 أو 1000 أو 10000 أو 100000',
  ),
  ScaleBarcodeIssue.priceDividerInvalid => tr(
    'معامل قسمة السعر يجب أن يكون 1 أو 10 أو 100 أو 1000 أو 10000 أو 100000',
  ),
  ScaleBarcodeIssue.prefixConflict => tr(
    'تعارض: بادئة الوزن وبادئة السعر متساويتان أو إحداهما تبدأ بالأخرى — نقطة البيع ستقرأ ملصقات الوزن كسعر',
  ),
  ScaleBarcodeIssue.fallbackConflict => tr(
    'تعارض: البادئة البديلة للوزن تتداخل مع بادئة السعر',
  ),
};

/// إعداد باركود الميزان — الحقول **ظاهرة دائماً** (كانت مخفيّة خلف مفتاح
/// التفعيل فبدت الشاشة «غير مفعّل» بلا حقول)، تحقّقٌ قبل الحفظ، ومعاينةٌ حيّة.
/// مفاتيحُ الإعداد وقواعدها في [ScaleBarcodeConfig].
class ScaleBarcodeSettingsPanel extends ConsumerStatefulWidget {
  const ScaleBarcodeSettingsPanel({super.key});

  @override
  ConsumerState<ScaleBarcodeSettingsPanel> createState() =>
      _ScaleBarcodeSettingsPanelState();
}

class _ScaleBarcodeSettingsPanelState
    extends ConsumerState<ScaleBarcodeSettingsPanel> {
  bool _loading = true;
  bool _saving = false;
  bool _weightEnabled = false;
  bool _priceEnabled = false;
  ScaleBarcodeConfig _saved = const ScaleBarcodeConfig();
  final _wPrefix = TextEditingController();
  final _wLen = TextEditingController();
  final _wDiv = TextEditingController();
  final _pPrefix = TextEditingController();
  final _pLen = TextEditingController();
  final _pDiv = TextEditingController();
  final _fallback = TextEditingController();

  List<TextEditingController> get _all => [
    _wPrefix,
    _wLen,
    _wDiv,
    _pPrefix,
    _pLen,
    _pDiv,
    _fallback,
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in _all) {
      c.dispose();
    }
    super.dispose();
  }

  ScaleBarcodeConfig get _config => ScaleBarcodeConfig(
    weightEnabled: _weightEnabled,
    priceEnabled: _priceEnabled,
    weightPrefix: _wPrefix.text,
    pricePrefix: _pPrefix.text,
    fallbackPrefix: _fallback.text,
    weightCodeLen: _wLen.text,
    priceCodeLen: _pLen.text,
    weightDivider: _wDiv.text,
    priceDivider: _pDiv.text,
  );

  Future<void> _load() async {
    final repo = ref.read(settingsRepositoryProvider);
    final values = <String, String?>{
      for (final k in ScaleBarcodeConfig.readKeys) k: await repo.getSetting(k),
    };
    if (!mounted) return;
    _apply(ScaleBarcodeConfig.fromSettings(values));
    setState(() => _loading = false);
  }

  void _apply(ScaleBarcodeConfig c) {
    _saved = c;
    _weightEnabled = c.weightEnabled;
    _priceEnabled = c.priceEnabled;
    _wPrefix.text = c.weightPrefix;
    _wLen.text = c.weightCodeLen;
    _wDiv.text = c.weightDivider;
    _pPrefix.text = c.pricePrefix;
    _pLen.text = c.priceCodeLen;
    _pDiv.text = c.priceDivider;
    _fallback.text = c.fallbackPrefix;
  }

  bool get _dirty {
    final a = _config.toSettings(), b = _saved.toSettings();
    return a.keys.any((k) => a[k] != b[k]);
  }

  Future<void> _save() async {
    final config = _config;
    if (config.validate().isNotEmpty || _saving) return;
    setState(() => _saving = true);
    final repo = ref.read(settingsRepositoryProvider);
    for (final e in config.toSettings().entries) {
      await repo.saveSetting(e.key, e.value);
    }
    // #Forensic Log: Scale barcode settings change (منقول من الشاشة القديمة)
    try {
      final auth = ref.read(authProvider);
      await ref
          .read(activityLoggerProvider)
          .logSettingsChange(
            auth.user?.id ?? 0,
            auth.user?.displayName ?? '',
            tr('إعدادات باركود الميزان'),
          );
    } catch (e) {
      debugPrint('[ActivityLog] Error: $e');
    }
    if (!mounted) return;
    setState(() {
      _saved = config;
      _saving = false;
    });
    AppToast.show(
      context,
      tr('تم حفظ إعدادات باركود الميزان'),
      type: ToastType.success,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const SizedBox(height: 48);
    final config = _config;
    final issues = config.validate();
    final status = _weightEnabled && _priceEnabled
        ? tr('ميزان الوزن + ميزان المجموع مفعّلين')
        : _weightEnabled
        ? tr('ميزان الوزن مفعّل')
        : _priceEnabled
        ? tr('ميزان المجموع مفعّل')
        : tr('غير مفعّل');
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            status,
            key: const Key('scale_cfg_status'),
            style: TextStyle(
              color: config.anyEnabled
                  ? AppColors.success
                  : context.picposSecondary,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          _profile(
            id: 'weight',
            title: tr('تفعيل باركود الوزن'),
            subtitle: tr('الملصق يحمل الوزن (كجم) — يُستخدم لملصق الميزان'),
            enabled: _weightEnabled,
            onToggle: (v) => setState(() => _weightEnabled = v),
            prefix: _wPrefix,
            len: _wLen,
            div: _wDiv,
            kind: ScaleBarcodeValueKind.weight,
          ),
          const SizedBox(height: 12),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: _field(
              'scale_cfg_fallback_prefix',
              _fallback,
              tr('بادئة وزن بديلة'),
              tr('تُقرأ وزناً أيضاً عند البيع'),
            ),
          ),
          const Divider(height: 24),
          _profile(
            id: 'price',
            title: tr('تفعيل باركود السعر (المجموع)'),
            subtitle: tr('الملصق يحمل السعر الإجمالي — تُحسب الكمية تلقائياً'),
            enabled: _priceEnabled,
            onToggle: (v) => setState(() => _priceEnabled = v),
            prefix: _pPrefix,
            len: _pLen,
            div: _pDiv,
            kind: ScaleBarcodeValueKind.price,
          ),
          const SizedBox(height: 8),
          Text(
            tr('خانة التحقق (الخانة 13) تُحسب تلقائياً وفق EAN-13، ونقطة البيع ترفض الملصق إن كانت خاطئة.'),
            style: TextStyle(fontSize: 12, color: context.picposSecondary),
          ),
          if (issues.isNotEmpty) ...[
            const SizedBox(height: 8),
            Column(
              key: const Key('scale_cfg_issues'),
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final i in issues)
                  Text(
                    '• ${scaleBarcodeIssueText(i)}',
                    style: const TextStyle(color: AppColors.error),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 24,
            runSpacing: 12,
            children: [
              ScaleBarcodePreview(
                config: config,
                kind: ScaleBarcodeValueKind.weight,
              ),
              ScaleBarcodePreview(
                config: config,
                kind: ScaleBarcodeValueKind.price,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              ElevatedButton.icon(
                key: const Key('scale_cfg_save'),
                onPressed: _dirty && issues.isEmpty && !_saving ? _save : null,
                icon: const Icon(Icons.save_outlined, size: 16),
                label: Text(tr('حفظ')),
              ),
              const SizedBox(width: 12),
              if (_dirty)
                Text(
                  issues.isEmpty
                      ? tr('تغييرات غير محفوظة')
                      : tr('لا يمكن الحفظ قبل تصحيح الأخطاء'),
                  style: TextStyle(
                    color: issues.isEmpty ? AppColors.warning : AppColors.error,
                    fontSize: 12,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _profile({
    required String id,
    required String title,
    required String subtitle,
    required bool enabled,
    required ValueChanged<bool> onToggle,
    required TextEditingController prefix,
    required TextEditingController len,
    required TextEditingController div,
    required ScaleBarcodeValueKind kind,
  }) {
    final config = _config;
    final digits = config.valueDigitsOf(kind);
    final decimals = config.decimalsOf(kind);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SwitchListTile(
          key: Key('scale_cfg_${id}_enabled'),
          contentPadding: EdgeInsets.zero,
          title: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          subtitle: Text(subtitle),
          value: enabled,
          onChanged: onToggle,
        ),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _field(
              'scale_cfg_${id}_prefix',
              prefix,
              tr('البادئة (Prefix)'),
              kind == ScaleBarcodeValueKind.weight
                  ? tr('مثال: 21')
                  : tr('مثال: 20'),
            ),
            _field(
              'scale_cfg_${id}_code_len',
              len,
              tr('خانات PLU'),
              tr('مثال: 5'),
            ),
            _field(
              'scale_cfg_${id}_divider',
              div,
              tr('معامل القسمة'),
              decimals == null
                  ? tr('قوة للعشرة')
                  : tr('الدقة: {n} منازل عشرية', {'n': decimals}),
            ),
            SizedBox(
              width: 150,
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: tr('خانات القيمة'),
                  helperText: tr('= 12 − البادئة − PLU'),
                  isDense: true,
                  border: const OutlineInputBorder(),
                ),
                child: Text(
                  digits == null || digits < 1 ? '—' : '$digits',
                  key: Key('scale_cfg_${id}_value_digits'),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _field(
    String key,
    TextEditingController c,
    String label,
    String helper,
  ) => SizedBox(
    width: 150,
    child: TextField(
      key: Key(key),
      controller: c,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      onChanged: (_) => setState(() {}),
      decoration: InputDecoration(
        labelText: label,
        helperText: helper,
        isDense: true,
        border: const OutlineInputBorder(),
      ),
    ),
  );
}
