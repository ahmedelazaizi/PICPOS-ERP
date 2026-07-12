part of '../settings_screen.dart';

// ═══════════════════════════════════════════════════════════════════════════
// SCALE BARCODE SETTINGS — Weight and Price profiles
// ═══════════════════════════════════════════════════════════════════════════

/// Scale Barcode Settings - Two profiles: Weight and Quantity
class _ScaleBarcodeSettings extends ConsumerStatefulWidget {
  const _ScaleBarcodeSettings();

  @override
  ConsumerState<_ScaleBarcodeSettings> createState() =>
      _ScaleBarcodeSettingsState();
}

class _ScaleBarcodeSettingsState extends ConsumerState<_ScaleBarcodeSettings> {
  bool _weightEnabled = false;
  bool _priceEnabled = false;
  final _weightPrefixController = TextEditingController(text: '21');
  final _weightCodeLenController = TextEditingController(text: '5');
  final _weightDividerController = TextEditingController(text: '1000');
  final _pricePrefixController = TextEditingController(text: '22');
  final _priceCodeLenController = TextEditingController(text: '5');
  final _priceDividerController = TextEditingController(text: '100');
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _weightPrefixController.dispose();
    _weightCodeLenController.dispose();
    _weightDividerController.dispose();
    _pricePrefixController.dispose();
    _priceCodeLenController.dispose();
    _priceDividerController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final settingsRepo = ref.read(settingsRepositoryProvider);
    final wEnabled = await settingsRepo.getSetting('scale_weight_enabled');
    // Read new key first, fall back to old key
    var pEnabled = await settingsRepo.getSetting('scale_price_enabled');
    pEnabled ??= await settingsRepo.getSetting('scale_qty_enabled');
    // Canonical keys matching scale_barcode_handler.dart (POS parser)
    var wPrefix = await settingsRepo.getSetting('scale_weight_prefix');
    wPrefix ??= await settingsRepo.getSetting('scale_barcode_prefix'); // old key fallback
    var wCodeLen = await settingsRepo.getSetting('scale_weight_item_code_len');
    wCodeLen ??= await settingsRepo.getSetting('scale_barcode_code_length'); // old key fallback
    var wDivider = await settingsRepo.getSetting('scale_weight_divider');
    wDivider ??= await settingsRepo.getSetting('scale_barcode_divider'); // old key fallback
    var pPrefix = await settingsRepo.getSetting('scale_price_prefix');
    pPrefix ??= await settingsRepo.getSetting('scale_qty_prefix');
    var pCodeLen = await settingsRepo.getSetting('scale_price_item_code_len');
    pCodeLen ??= await settingsRepo.getSetting('scale_price_code_length'); // old key fallback
    pCodeLen ??= await settingsRepo.getSetting('scale_qty_code_length');
    var pDivider = await settingsRepo.getSetting('scale_price_divider');
    pDivider ??= await settingsRepo.getSetting('scale_qty_divider');
    if (mounted) {
      setState(() {
        _weightEnabled = wEnabled == 'true';
        _priceEnabled = pEnabled == 'true';
        if (wPrefix != null) _weightPrefixController.text = wPrefix;
        if (wCodeLen != null) _weightCodeLenController.text = wCodeLen;
        if (wDivider != null) _weightDividerController.text = wDivider;
        if (pPrefix != null) _pricePrefixController.text = pPrefix;
        if (pCodeLen != null) _priceCodeLenController.text = pCodeLen;
        if (pDivider != null) _priceDividerController.text = pDivider;
        _loading = false;
      });
    }
  }

  Future<void> _saveAll() async {
    final settingsRepo = ref.read(settingsRepositoryProvider);
    await settingsRepo.saveSetting('scale_weight_enabled', _weightEnabled.toString());
    await settingsRepo.saveSetting('scale_price_enabled', _priceEnabled.toString());
    // Canonical keys matching scale_barcode_handler.dart (POS parser)
    await settingsRepo.saveSetting(
      'scale_weight_prefix',
      _weightPrefixController.text.trim(),
    );
    await settingsRepo.saveSetting(
      'scale_weight_item_code_len',
      _weightCodeLenController.text.trim(),
    );
    await settingsRepo.saveSetting(
      'scale_weight_divider',
      _weightDividerController.text.trim(),
    );
    await settingsRepo.saveSetting(
      'scale_price_prefix',
      _pricePrefixController.text.trim(),
    );
    await settingsRepo.saveSetting(
      'scale_price_item_code_len',
      _priceCodeLenController.text.trim(),
    );
    await settingsRepo.saveSetting(
      'scale_price_divider',
      _priceDividerController.text.trim(),
    );
    // #Forensic Log: Scale barcode settings change
    try {
      final auth = ref.read(authProvider);
      final logger = ref.read(activityLoggerProvider);
      await logger.logSettingsChange(
        auth.user?.id ?? 0,
        auth.user?.displayName ?? '',
        'إعدادات باركود الميزان',
      );
    } catch (e) {
      debugPrint('[ActivityLog] Error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const SizedBox.shrink();
    return ExpansionTile(
      leading: Icon(
        PhosphorIconsBold.barcode,
        color: (_weightEnabled || _priceEnabled)
            ? AppColors.primary
            : Colors.grey,
      ),
      title: const Text('إعدادات باركود الميزان'),
      subtitle: Text(
        _weightEnabled && _priceEnabled
            ? 'ميزان الوزن + ميزان المجموع مفعّلين'
            : _weightEnabled
            ? 'ميزان الوزن مفعّل'
            : _priceEnabled
            ? 'ميزان المجموع مفعّل'
            : 'غير مفعّل',
        style: TextStyle(
          color: (_weightEnabled || _priceEnabled)
              ? AppColors.success
              : Colors.grey,
          fontSize: 12,
        ),
      ),
      children: [
        // ---------- Weight Scale ----------
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'ميزان الوزن',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: const Text('باركود يحتوي على وزن المنتج (كجم)'),
                value: _weightEnabled,
                onChanged: (v) {
                  setState(() => _weightEnabled = v);
                  _saveAll();
                },
              ),
              if (_weightEnabled)
                ..._buildProfileFields(
                  _weightPrefixController,
                  _weightCodeLenController,
                  _weightDividerController,
                  'مثال: 21',
                  'مثال: 1000 (جرام ← كجم)',
                ),
              const SizedBox(height: 8),
              const Divider(height: 1),
              const SizedBox(height: 8),
              // ---------- Price/Total Scale ----------
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'ميزان المجموع (السعر)',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: const Text(
                  'باركود يحتوي على السعر الإجمالي — يحسب الكمية تلقائياً',
                ),
                value: _priceEnabled,
                onChanged: (v) {
                  setState(() => _priceEnabled = v);
                  _saveAll();
                },
              ),
              if (_priceEnabled)
                ..._buildProfileFields(
                  _pricePrefixController,
                  _priceCodeLenController,
                  _priceDividerController,
                  'مثال: 22',
                  'مثال: 100 (فلس ← عملة)',
                ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ],
    );
  }

  List<Widget> _buildProfileFields(
    TextEditingController prefixCtrl,
    TextEditingController codeLenCtrl,
    TextEditingController dividerCtrl,
    String prefixHint,
    String dividerHint,
  ) {
    return [
      const SizedBox(height: 8),
      Row(
        children: [
          Expanded(
            child: TextField(
              controller: prefixCtrl,
              decoration: InputDecoration(
                labelText: 'البادئة (Prefix)',
                hintText: prefixHint,
                isDense: true,
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) => _saveAll(),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: codeLenCtrl,
              decoration: const InputDecoration(
                labelText: 'طول كود المنتج',
                hintText: 'مثال: 5',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
              onChanged: (_) => _saveAll(),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: dividerCtrl,
              decoration: InputDecoration(
                labelText: 'القسمة (Divider)',
                hintText: dividerHint,
                isDense: true,
                border: const OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
              onChanged: (_) => _saveAll(),
            ),
          ),
        ],
      ),
    ];
  }
}
