part of 'cart_view.dart';

// ═══════════════════════════════════════════════════════════════════════════
// CART DISPLAY SETTINGS POPOVER
// ═══════════════════════════════════════════════════════════════════════════

class _CartDisplaySettingsBtn extends ConsumerWidget {
  final double scaleFactor;
  const _CartDisplaySettingsBtn({required this.scaleFactor});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _showSettingsPopover(context, ref),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: EdgeInsets.all(6 * scaleFactor),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            PhosphorIconsBold.slidersHorizontal,
            size: 16 * scaleFactor,
            color: AppColors.primary,
          ),
        ),
      ),
    );
  }

  void _showSettingsPopover(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (_) => _CartDisplaySettingsDialog(),
    );
  }
}

class _CartDisplaySettingsDialog extends ConsumerStatefulWidget {
  @override
  ConsumerState<_CartDisplaySettingsDialog> createState() => _CartDisplaySettingsDialogState();
}

class _CartDisplaySettingsDialogState extends ConsumerState<_CartDisplaySettingsDialog> {
  late double _cartItemScale;
  late double _bottomPanelScale;
  late double _buttonHeight;
  late double _buttonFontSize;
  late double _paymentButtonHeight;

  @override
  void initState() {
    super.initState();
    _cartItemScale = 1.0;
    _bottomPanelScale = 1.0;
    _buttonHeight = 40.0;
    _buttonFontSize = 13.0;
    _paymentButtonHeight = 45.0;
  }

  @override
  Widget build(BuildContext context) {
    // Load current values
    final cartItemScale = ref.watch(posCartItemScaleProvider).value;
    final bottomPanelScale = ref.watch(posBottomPanelScaleProvider).value;
    final buttonHeight = ref.watch(posButtonHeightProvider).value;
    final buttonFontSize = ref.watch(posButtonFontSizeProvider).value;
    final paymentBtnHeight = ref.watch(paymentButtonHeightProvider).value;

    // Initialize once from providers
    if (cartItemScale != null && _cartItemScale == 1.0 && cartItemScale != 1.0) _cartItemScale = cartItemScale;
    if (bottomPanelScale != null && _bottomPanelScale == 1.0 && bottomPanelScale != 1.0) _bottomPanelScale = bottomPanelScale;
    if (buttonHeight != null && _buttonHeight == 40.0 && buttonHeight != 40.0) _buttonHeight = buttonHeight;
    if (buttonFontSize != null && _buttonFontSize == 13.0 && buttonFontSize != 13.0) _buttonFontSize = buttonFontSize;
    if (paymentBtnHeight != null && _paymentButtonHeight == 45.0 && paymentBtnHeight != 45.0) _paymentButtonHeight = paymentBtnHeight;

    if (cartItemScale != null && (_cartItemScale - cartItemScale).abs() < 0.001) {} else if (cartItemScale != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _cartItemScale = cartItemScale);
      });
    }

    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title:  Row(
          children: [
            const Icon(PhosphorIconsBold.slidersHorizontal, color: AppColors.primary, size: 22),
            const SizedBox(width: 8),
            Text(tr('إعدادات عرض السلة'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildSliderRow(
                label: tr('حجم نص الأصناف'),
                icon: PhosphorIconsBold.textAa,
                value: _cartItemScale,
                min: 0.7,
                max: 1.3,
                divisions: 12,
                displayValue: '${(_cartItemScale * 100).round()}%',
                onChanged: (v) {
                  setState(() => _cartItemScale = v);
                  _saveSetting('pos_cart_item_scale', v);
                },
              ),
              const Divider(height: 24),
              _buildSliderRow(
                label: tr('حجم منطقة الدفع'),
                icon: PhosphorIconsBold.rectangleDashed,
                value: _bottomPanelScale,
                min: 0.7,
                max: 1.0,
                divisions: 6,
                displayValue: '${(_bottomPanelScale * 100).round()}%',
                onChanged: (v) {
                  setState(() => _bottomPanelScale = v);
                  _saveSetting('pos_bottom_panel_scale', v);
                },
              ),
              const Divider(height: 24),
              _buildSliderRow(
                label: tr('ارتفاع الأزرار'),
                icon: PhosphorIconsBold.arrowsOutLineVertical,
                value: _buttonHeight,
                min: 30,
                max: 50,
                divisions: 10,
                displayValue: '${_buttonHeight.round()}px',
                onChanged: (v) {
                  setState(() => _buttonHeight = v);
                  _saveSetting('pos_button_height', v);
                },
              ),
              const Divider(height: 24),
              _buildSliderRow(
                label: tr('حجم خط الأزرار'),
                icon: PhosphorIconsBold.textT,
                value: _buttonFontSize,
                min: 10,
                max: 16,
                divisions: 6,
                displayValue: '${_buttonFontSize.round()}pt',
                onChanged: (v) {
                  setState(() => _buttonFontSize = v);
                  _saveSetting('pos_button_font_size', v);
                },
              ),
              const Divider(height: 24),
              _buildSliderRow(
                label: tr('ارتفاع أزرار الدفع'),
                icon: PhosphorIconsBold.creditCard,
                value: _paymentButtonHeight,
                min: 30,
                max: 80,
                divisions: 10,
                displayValue: '${_paymentButtonHeight.round()}px',
                onChanged: (v) {
                  setState(() => _paymentButtonHeight = v);
                  _saveSetting('pos_payment_button_height', v);
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => _resetDefaults(),
            child:  Text(tr('استعادة الافتراضي'), style: const TextStyle(color: AppColors.warning)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
            child:  Text(tr('تم')),
          ),
        ],
      ),
    );
  }

  Widget _buildSliderRow({
    required String label,
    required IconData icon,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required String displayValue,
    required ValueChanged<double> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 18, color: AppColors.primary),
            const SizedBox(width: 8),
            Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                displayValue,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.primary),
              ),
            ),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 4,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
          ),
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            activeColor: AppColors.primary,
            inactiveColor: AppColors.primary.withValues(alpha: 0.15),
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }

  void _saveSetting(String key, double value) {
    final repo = ref.read(settingsRepositoryProvider);
    repo.saveSetting(key, value.toStringAsFixed(2));
    // Invalidate all display providers to refresh immediately
    _invalidateAll();
  }

  void _invalidateAll() {
    ref.invalidate(posCartItemScaleProvider);
    ref.invalidate(posBottomPanelScaleProvider);
    ref.invalidate(posButtonHeightProvider);
    ref.invalidate(posButtonFontSizeProvider);
    ref.invalidate(paymentButtonHeightProvider);
  }

  void _resetDefaults() {
    setState(() {
      _cartItemScale = 1.0;
      _bottomPanelScale = 1.0;
      _buttonHeight = 40.0;
      _buttonFontSize = 13.0;
    });
    final repo = ref.read(settingsRepositoryProvider);
    repo.saveSetting('pos_cart_item_scale', '1.0');
    repo.saveSetting('pos_bottom_panel_scale', '1.0');
    repo.saveSetting('pos_button_height', '40.0');
    repo.saveSetting('pos_button_font_size', '13.0');
    repo.saveSetting('pos_payment_button_height', '45.0');
    _invalidateAll();
  }
}
