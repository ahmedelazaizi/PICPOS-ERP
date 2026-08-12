part of '../settings_screen.dart';

// ═══════════════════════════════════════════════════════════════════════════
// CFD SETTINGS — Customer Facing Display & QR Menu (Multi-Transport)
// ═══════════════════════════════════════════════════════════════════════════

/// CFD & QR Menu Settings Card — supports Network, Serial, USB, HDMI
class _CFDSettingsCard extends StatefulWidget {
  const _CFDSettingsCard();

  @override
  State<_CFDSettingsCard> createState() => _CFDSettingsCardState();
}

class _CFDSettingsCardState extends State<_CFDSettingsCard> {
  final _cfd = CfdService.instance;
  final _ns = NetworkService.instance;
  bool _loading = true;
  bool _testing = false;

  // Form controllers
  late CfdConnectionType _selectedType;
  String? _selectedPort;
  int _selectedBaudRate = 9600;
  int _selectedMonitor = 1;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _cfd.loadSettings();
    await _ns.loadSettings();
    _selectedType = _cfd.connectionType;
    _selectedPort = _cfd.savedPort;
    _selectedBaudRate = _cfd.savedBaudRate;
    _selectedMonitor = _cfd.savedMonitorIndex;
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header with status ──
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(
                    PhosphorIconsBold.monitor,
                    color: AppColors.primary,
                    size: 20,
                  ),
                  SizedBox(width: 8),
                  Text(
                    'شاشة العميل والمنيو',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                ],
              ),
              _buildStatusBadge(),
            ],
          ),
          const SizedBox(height: 16),

          // ── Enable/Disable Toggle ──
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text(
              'تفعيل شاشة العميل',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              _cfd.enabled
                  ? 'الشاشة مفعلة - ${_selectedType.label}'
                  : 'الشاشة معطلة',
              style: const TextStyle(fontSize: 12),
            ),
            value: _cfd.enabled,
            activeTrackColor: AppColors.primary,
            onChanged: (v) async {
              await _cfd.setEnabled(v);
              if (v) {
                await _cfd.setConnectionType(
                  _selectedType,
                  port: _selectedPort,
                  baudRate: _selectedBaudRate,
                  monitorIndex: _selectedMonitor,
                );
                await _cfd.connectTransport();
              }
              setState(() {});
            },
          ),
          const Divider(height: 24),

          // ── Connection Type Selector ──
          const Text(
            'نوع الاتصال',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 13,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: CfdConnectionType.values.map((type) {
              final isSelected = _selectedType == type;
              return ChoiceChip(
                label: Text(
                  type.label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight:
                        isSelected ? FontWeight.bold : FontWeight.normal,
                    color: isSelected ? Colors.white : null,
                  ),
                ),
                avatar: Icon(
                  _getIconForType(type),
                  size: 16,
                  color: isSelected ? Colors.white : AppColors.textMuted,
                ),
                selected: isSelected,
                selectedColor: AppColors.primary,
                backgroundColor: AppColors.surface,
                onSelected: (selected) {
                  if (selected) {
                    setState(() => _selectedType = type);
                  }
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 4),
          Text(
            _selectedType.description,
            style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
          ),
          const SizedBox(height: 16),

          // ── Dynamic Config Panel ──
          _buildConfigPanel(),

          const SizedBox(height: 16),

          // ── Action Buttons ──
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _testing ? null : _testConnection,
                  icon: _testing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(PhosphorIconsBold.plugsConnected, size: 16),
                  label: Text(_testing ? 'جاري الاختبار...' : 'اختبار الاتصال'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.info,
                    side: const BorderSide(color: AppColors.info),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _saveAndConnect,
                  icon: const Icon(PhosphorIconsBold.floppyDisk, size: 16),
                  label: const Text('حفظ وتطبيق'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // ── Content Customization ──
          _buildContentCustomization(),

          const SizedBox(height: 16),

          // ── Network CFD Links (always shown) ──
          const Divider(),
          const SizedBox(height: 8),
          const Text(
            'روابط الشبكة (متاحة دائماً)',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 12,
              color: AppColors.textMuted,
            ),
          ),
          const SizedBox(height: 8),
          _buildCFDLink(
            title: 'شاشة العميل (CFD)',
            url: '${_ns.buildServerUrl()}/cfd',
            icon: PhosphorIconsBold.monitor,
            color: Colors.blue,
          ),
          const SizedBox(height: 8),
          _buildCFDLink(
            title: 'منيو الطاولات (QR Menu)',
            url: '${_ns.buildServerUrl()}/menu',
            icon: PhosphorIconsBold.qrCode,
            color: Colors.purple,
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge() {
    final connected = _cfd.isConnected;
    final enabled = _cfd.enabled;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: !enabled
            ? Colors.grey.withValues(alpha: 0.1)
            : connected
                ? AppColors.success.withValues(alpha: 0.1)
                : AppColors.error.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        !enabled
            ? 'معطل'
            : connected
                ? _cfd.statusText
                : 'غير متصل',
        style: TextStyle(
          color: !enabled
              ? Colors.grey
              : connected
                  ? AppColors.success
                  : AppColors.error,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildContentCustomization() {
    final config = _cfd.displayConfig;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: ExpansionTile(
        leading: const Icon(
          PhosphorIconsBold.slidersHorizontal,
          size: 18,
          color: AppColors.primary,
        ),
        title: const Text(
          'تخصيص المحتوى المعروض',
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        ),
        subtitle: const Text(
          'تحكم فيما يظهر على شاشة العميل',
          style: TextStyle(fontSize: 10, color: AppColors.textMuted),
        ),
        childrenPadding: const EdgeInsets.symmetric(horizontal: 8),
        children: [
          const Divider(height: 1),
          const SizedBox(height: 4),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              'بيانات الأصناف',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 11,
                color: AppColors.textMuted,
              ),
            ),
          ),
          _configToggle(
            'اسم الصنف',
            'إظهار اسم كل صنف في القائمة',
            config.showItemName,
            (v) => _updateConfig(config.copyWith(showItemName: v)),
          ),
          _configToggle(
            'الكمية',
            'إظهار كمية كل صنف',
            config.showItemQuantity,
            (v) => _updateConfig(config.copyWith(showItemQuantity: v)),
          ),
          _configToggle(
            'سعر الوحدة',
            'إظهار سعر الوحدة لكل صنف',
            config.showItemPrice,
            (v) => _updateConfig(config.copyWith(showItemPrice: v)),
          ),
          _configToggle(
            'إجمالي الصنف',
            'إظهار إجمالي سعر كل صنف (الكمية × السعر)',
            config.showItemTotal,
            (v) => _updateConfig(config.copyWith(showItemTotal: v)),
          ),
          const Divider(height: 8),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              'ملخص الفاتورة',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 11,
                color: AppColors.textMuted,
              ),
            ),
          ),
          _configToggle(
            'المجموع الفرعي',
            'إظهار المجموع قبل الخصم والضريبة',
            config.showSubtotal,
            (v) => _updateConfig(config.copyWith(showSubtotal: v)),
          ),
          _configToggle(
            'الخصم',
            'إظهار نسبة/قيمة الخصم',
            config.showDiscount,
            (v) => _updateConfig(config.copyWith(showDiscount: v)),
          ),
          _configToggle(
            'الضريبة',
            'إظهار مبلغ الضريبة',
            config.showTax,
            (v) => _updateConfig(config.copyWith(showTax: v)),
          ),
          _configToggle(
            'الإجمالي النهائي',
            'إظهار المبلغ الإجمالي للفاتورة',
            config.showTotal,
            (v) => _updateConfig(config.copyWith(showTotal: v)),
          ),
          _configToggle(
            'اسم العميل',
            'إظهار اسم العميل المحدد',
            config.showCustomerName,
            (v) => _updateConfig(config.copyWith(showCustomerName: v)),
          ),
          const Divider(height: 8),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              'رسالة الترحيب',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 11,
                color: AppColors.textMuted,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: TextFormField(
                    initialValue: config.welcomeMessage,
                    decoration: const InputDecoration(
                      labelText: 'السطر الأول',
                      isDense: true,
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                    ),
                    style: const TextStyle(fontSize: 12),
                    onChanged: (v) =>
                        _updateConfig(config.copyWith(welcomeMessage: v)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    initialValue: config.welcomeSubMessage,
                    decoration: const InputDecoration(
                      labelText: 'السطر الثاني',
                      isDense: true,
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                    ),
                    style: const TextStyle(fontSize: 12),
                    onChanged: (v) =>
                        _updateConfig(config.copyWith(welcomeSubMessage: v)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _configToggle(
    String title,
    String subtitle,
    bool value,
    ValueChanged<bool> onChanged,
  ) {
    return SwitchListTile(
      title: Text(title, style: const TextStyle(fontSize: 12)),
      subtitle: Text(subtitle,
          style: const TextStyle(fontSize: 10, color: AppColors.textMuted)),
      value: value,
      dense: true,
      activeTrackColor: AppColors.primary,
      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
      onChanged: onChanged,
    );
  }

  void _updateConfig(CfdDisplayConfig config) {
    _cfd.setDisplayConfig(config);
    setState(() {});
  }

  Widget _buildConfigPanel() {
    switch (_selectedType) {
      case CfdConnectionType.network:
        return _buildNetworkConfig();
      case CfdConnectionType.serial:
        return _buildSerialConfig(isUsb: false);
      case CfdConnectionType.usb:
        return _buildSerialConfig(isUsb: true);
      case CfdConnectionType.hdmi:
        return _buildHdmiConfig();
    }
  }

  /// Network config — IP + Port (existing)
  Widget _buildNetworkConfig() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(PhosphorIconsBold.wifiHigh, size: 16, color: AppColors.info),
              SizedBox(width: 6),
              Text(
                'اتصال الشبكة',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'شاشة العميل عبر الشبكة تعمل تلقائياً عند تشغيل السيرفر من إعدادات وضع الشبكة. '
            'يمكن لأي جهاز (تابلت، هاتف) على نفس الشبكة فتح الرابط أعلاه.',
            style: TextStyle(fontSize: 11, color: AppColors.textMuted),
          ),
          const SizedBox(height: 8),
          if (!_ns.isServerRunning)
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Row(
                children: [
                  Icon(PhosphorIconsBold.warningCircle,
                      color: AppColors.warning, size: 14),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'السيرفر غير مشغل. شغّل السيرفر من "وضع الشبكة" لتفعيل شاشة العميل عبر الشبكة.',
                      style: TextStyle(fontSize: 10, color: AppColors.warning),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// Serial/USB config — COM port + Baud rate
  Widget _buildSerialConfig({required bool isUsb}) {
    // Get available ports
    final ports = isUsb
        ? CfdUsbTransport.getAvailablePorts()
        : CfdSerialTransport.getAvailablePorts();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isUsb ? PhosphorIconsBold.usb : PhosphorIconsBold.plugs,
                size: 16,
                color: AppColors.info,
              ),
              const SizedBox(width: 6),
              Text(
                isUsb ? 'إعدادات USB' : 'إعدادات Serial / COM',
                style: const TextStyle(
                    fontWeight: FontWeight.w600, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              // COM Port Dropdown
              Expanded(
                flex: 2,
                child: DropdownButtonFormField<String>(
                  initialValue: ports.contains(_selectedPort) ? _selectedPort : null,
                  decoration: InputDecoration(
                    labelText: isUsb ? 'USB Port' : 'COM Port',
                    isDense: true,
                    border: const OutlineInputBorder(),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                  ),
                  items: ports.isEmpty
                      ? [
                          const DropdownMenuItem(
                            value: null,
                            child: Text(
                              'لا توجد منافذ',
                              style: TextStyle(
                                  color: AppColors.textMuted, fontSize: 12),
                            ),
                          ),
                        ]
                      : ports
                          .map((p) => DropdownMenuItem(
                                value: p,
                                child:
                                    Text(p, style: const TextStyle(fontSize: 12)),
                              ))
                          .toList(),
                  onChanged: (v) => setState(() => _selectedPort = v),
                ),
              ),
              const SizedBox(width: 12),
              // Baud Rate Dropdown
              Expanded(
                flex: 1,
                child: DropdownButtonFormField<int>(
                  initialValue: _selectedBaudRate,
                  decoration: const InputDecoration(
                    labelText: 'Baud Rate',
                    isDense: true,
                    border: OutlineInputBorder(),
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                  items: CfdSerialTransport.supportedBaudRates
                      .map((b) => DropdownMenuItem(
                            value: b,
                            child: Text('$b',
                                style: const TextStyle(fontSize: 12)),
                          ))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setState(() => _selectedBaudRate = v);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Refresh ports button
          TextButton.icon(
            onPressed: () => setState(() {}),
            icon: const Icon(PhosphorIconsBold.arrowClockwise, size: 14),
            label: const Text('تحديث المنافذ', style: TextStyle(fontSize: 11)),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.textMuted,
              padding: EdgeInsets.zero,
              minimumSize: const Size(0, 30),
            ),
          ),
          if (ports.isEmpty)
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                children: [
                  const Icon(PhosphorIconsBold.warningCircle,
                      color: AppColors.warning, size: 14),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      isUsb
                          ? 'لم يتم العثور على أجهزة USB. تأكد من توصيل الشاشة وتثبيت الدرايفر.'
                          : 'لم يتم العثور على منافذ COM. تأكد من توصيل كابل Serial.',
                      style:
                          const TextStyle(fontSize: 10, color: AppColors.warning),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// HDMI config — Monitor selector
  Widget _buildHdmiConfig() {
    final monitors = CfdHdmiTransport.getAvailableMonitors();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(PhosphorIconsBold.screencast, size: 16, color: AppColors.info),
              SizedBox(width: 6),
              Text(
                'إعدادات HDMI / الشاشة الثانية',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
            initialValue: _selectedMonitor < monitors.length ? _selectedMonitor : 0,
            decoration: const InputDecoration(
              labelText: 'اختر الشاشة',
              isDense: true,
              border: OutlineInputBorder(),
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
            items: monitors.isEmpty
                ? [
                    const DropdownMenuItem(
                      value: 0,
                      child: Text(
                        'شاشة واحدة فقط',
                        style:
                            TextStyle(color: AppColors.textMuted, fontSize: 12),
                      ),
                    ),
                  ]
                : monitors
                    .map((m) => DropdownMenuItem(
                          value: m['index'] as int,
                          child: Text(
                            m['label'] as String,
                            style: const TextStyle(fontSize: 12),
                          ),
                        ))
                    .toList(),
            onChanged: (v) {
              if (v != null) setState(() => _selectedMonitor = v);
            },
          ),
          const SizedBox(height: 8),
          if (monitors.length <= 1)
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.info.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Row(
                children: [
                  Icon(PhosphorIconsBold.info, color: AppColors.info, size: 14),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'قم بتوصيل شاشة ثانية عبر HDMI أو DisplayPort، ثم اضبط الشاشة كـ "Extended Display" من إعدادات Windows.',
                      style: TextStyle(fontSize: 10, color: AppColors.info),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 8),
          const Text(
            'سيتم فتح نافذة شاشة العميل في متصفح الويب على الشاشة المحددة مع عرض بيانات السلة في الوقت الفعلي.',
            style: TextStyle(fontSize: 10, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }

  /// Test connection with detailed diagnostics
  Future<void> _testConnection() async {
    setState(() => _testing = true);

    final diagnostics = <String, String>{};
    bool result = false;
    String? errorDetail;

    try {
      diagnostics['نوع الاتصال'] = _selectedType.label;

      if (_selectedType == CfdConnectionType.network) {
        diagnostics['عنوان السيرفر'] = '${_ns.serverAddress}:${_ns.serverPort}';
        diagnostics['حالة السيرفر'] = _ns.isServerRunning ? 'يعمل ✓' : 'متوقف ✗';
        result = _ns.isServerRunning;
        if (!result) {
          errorDetail = 'السيرفر غير مشغل. شغّل السيرفر من إعدادات الشبكة أولاً.';
        }
      } else if (_selectedType == CfdConnectionType.serial || _selectedType == CfdConnectionType.usb) {
        final ports = _selectedType == CfdConnectionType.usb
            ? CfdUsbTransport.getAvailablePorts()
            : CfdSerialTransport.getAvailablePorts();
        diagnostics['المنافذ المتاحة'] = ports.isEmpty ? 'لا توجد' : ports.join(', ');
        diagnostics['المنفذ المحدد'] = _selectedPort ?? 'غير محدد';
        diagnostics['سرعة البث'] = '$_selectedBaudRate bps';

        if (_selectedPort == null || !ports.contains(_selectedPort)) {
          errorDetail = _selectedPort == null
              ? 'لم يتم اختيار منفذ. حدد المنفذ الصحيح.'
              : 'المنفذ "$_selectedPort" غير متاح. تحقق من التوصيل وأعد التحديث.';
        } else {
          result = await _cfd.testConnection(
            _selectedType,
            port: _selectedPort,
            baudRate: _selectedBaudRate,
            monitorIndex: _selectedMonitor,
          );
          if (!result) {
            errorDetail = 'تعذر فتح المنفذ. تأكد من:\n'
                '• عدم استخدام المنفذ من برنامج آخر\n'
                '• تثبيت الدرايفر الصحيح\n'
                '• توصيل الشاشة بشكل صحيح';
          }
        }
      } else {
        // HDMI
        final monitors = CfdHdmiTransport.getAvailableMonitors();
        diagnostics['عدد الشاشات'] = '${monitors.length}';
        diagnostics['الشاشة المحددة'] = 'شاشة رقم $_selectedMonitor';

        if (monitors.length <= 1) {
          errorDetail = 'لم يتم اكتشاف شاشة ثانية.\n'
              '• تأكد من توصيل الشاشة عبر HDMI/DisplayPort\n'
              '• اضبط الشاشة كـ "Extended Display" من إعدادات Windows';
        } else {
          result = await _cfd.testConnection(
            _selectedType,
            port: _selectedPort,
            baudRate: _selectedBaudRate,
            monitorIndex: _selectedMonitor,
          );
          if (!result) {
            errorDetail = 'فشل فتح الشاشة الثانية. تحقق من إعدادات العرض في Windows.';
          }
        }
      }

      diagnostics['النتيجة'] = result ? 'اتصال ناجح ✓' : 'فشل الاتصال ✗';
    } catch (e) {
      diagnostics['النتيجة'] = 'خطأ ✗';
      errorDetail = e.toString();
    } finally {
      if (mounted) {
        setState(() => _testing = false);
        _showDiagnosticDialog(diagnostics, result, errorDetail);
      }
    }
  }

  void _showDiagnosticDialog(Map<String, String> diagnostics, bool success, String? errorDetail) {
    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Row(
            children: [
              Icon(
                success ? PhosphorIconsBold.checkCircle : PhosphorIconsBold.warningCircle,
                color: success ? AppColors.success : AppColors.error,
                size: 24,
              ),
              const SizedBox(width: 8),
              Text(success ? 'اتصال ناجح' : 'فشل الاتصال'),
            ],
          ),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'تشخيص الاتصال:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                const SizedBox(height: 8),
                ...diagnostics.entries.map((e) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 120,
                        child: Text(
                          e.key,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          e.value,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: e.key == 'النتيجة'
                                ? (success ? AppColors.success : AppColors.error)
                                : null,
                          ),
                        ),
                      ),
                    ],
                  ),
                )),
                if (errorDetail != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.error.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: AppColors.error.withValues(alpha: 0.2)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(PhosphorIconsBold.lightbulb, size: 16, color: AppColors.warning),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            errorDetail,
                            style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إغلاق'),
            ),
          ],
        ),
      ),
    );
  }

  /// Save and connect
  Future<void> _saveAndConnect() async {
    await _cfd.setConnectionType(
      _selectedType,
      port: _selectedPort,
      baudRate: _selectedBaudRate,
      monitorIndex: _selectedMonitor,
    );

    if (_cfd.enabled) {
      final success = await _cfd.connectTransport();
      if (mounted) {
        if (success) {
          AppToast.show(context, 'تم الحفظ والاتصال بنجاح ✓',
              type: ToastType.success);
        } else {
          AppToast.show(context, 'تم الحفظ لكن فشل الاتصال',
              type: ToastType.warning);
        }
      }
    } else {
      if (mounted) {
        AppToast.show(context, 'تم الحفظ ✓', type: ToastType.success);
      }
    }
    setState(() {});
  }

  IconData _getIconForType(CfdConnectionType type) {
    switch (type) {
      case CfdConnectionType.network:
        return PhosphorIconsBold.wifiHigh;
      case CfdConnectionType.serial:
        return PhosphorIconsBold.plugs;
      case CfdConnectionType.usb:
        return PhosphorIconsBold.usb;
      case CfdConnectionType.hdmi:
        return PhosphorIconsBold.screencast;
    }
  }

  Widget _buildCFDLink({
    required String title,
    required String url,
    required IconData icon,
    required Color color,
  }) {
    final enabled = _ns.isServerRunning;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: enabled
            ? color.withValues(alpha: 0.05)
            : Colors.grey.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: enabled
              ? color.withValues(alpha: 0.2)
              : Colors.grey.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: enabled ? color : Colors.grey),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: enabled ? null : Colors.grey,
                  ),
                ),
                Text(
                  url,
                  style: TextStyle(
                    fontSize: 10,
                    color: enabled ? AppColors.textMuted : Colors.grey,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
