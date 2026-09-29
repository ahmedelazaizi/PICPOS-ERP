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
               Row(
                children: [
                  const Icon(
                    PhosphorIconsBold.monitor,
                    color: AppColors.primary,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    tr('شاشة العميل والمنيو'),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
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
            title:  Text(
              tr('تفعيل شاشة العميل'),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              _cfd.enabled
                  ? tr('الشاشة مفعلة - {p0}', {'p0': _selectedType.label})
                  : tr('الشاشة معطلة'),
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
           Text(
            tr('نوع الاتصال'),
            style: const TextStyle(
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
                  label: Text(_testing ? tr('جاري الاختبار...') : tr('اختبار الاتصال')),
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
                  label:  Text(tr('حفظ وتطبيق')),
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
           Text(
            tr('روابط الشبكة (متاحة دائماً)'),
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 12,
              color: AppColors.textMuted,
            ),
          ),
          const SizedBox(height: 8),
          _buildCFDLink(
            title: tr('شاشة العميل (CFD)'),
            url: '${_ns.buildServerUrl()}/cfd',
            icon: PhosphorIconsBold.monitor,
            color: Colors.blue,
          ),
          const SizedBox(height: 8),
          _buildCFDLink(
            title: tr('منيو الطاولات (QR Menu)'),
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
            ? tr('معطل')
            : connected
                ? _cfd.statusText
                : tr('غير متصل'),
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
        title:  Text(
          tr('تخصيص المحتوى المعروض'),
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        ),
        subtitle:  Text(
          tr('تحكم فيما يظهر على شاشة العميل'),
          style: const TextStyle(fontSize: 10, color: AppColors.textMuted),
        ),
        childrenPadding: const EdgeInsets.symmetric(horizontal: 8),
        children: [
          const Divider(height: 1),
          const SizedBox(height: 4),
           Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              tr('بيانات الأصناف'),
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 11,
                color: AppColors.textMuted,
              ),
            ),
          ),
          _configToggle(
            tr('اسم الصنف'),
            tr('إظهار اسم كل صنف في القائمة'),
            config.showItemName,
            (v) => _updateConfig(config.copyWith(showItemName: v)),
          ),
          _configToggle(
            tr('الكمية'),
            tr('إظهار كمية كل صنف'),
            config.showItemQuantity,
            (v) => _updateConfig(config.copyWith(showItemQuantity: v)),
          ),
          _configToggle(
            tr('سعر الوحدة'),
            tr('إظهار سعر الوحدة لكل صنف'),
            config.showItemPrice,
            (v) => _updateConfig(config.copyWith(showItemPrice: v)),
          ),
          _configToggle(
            tr('إجمالي الصنف'),
            tr('إظهار إجمالي سعر كل صنف (الكمية × السعر)'),
            config.showItemTotal,
            (v) => _updateConfig(config.copyWith(showItemTotal: v)),
          ),
          const Divider(height: 8),
           Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              tr('ملخص الفاتورة'),
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 11,
                color: AppColors.textMuted,
              ),
            ),
          ),
          _configToggle(
            tr('المجموع الفرعي'),
            tr('إظهار المجموع قبل الخصم والضريبة'),
            config.showSubtotal,
            (v) => _updateConfig(config.copyWith(showSubtotal: v)),
          ),
          _configToggle(
            tr('الخصم'),
            tr('إظهار نسبة/قيمة الخصم'),
            config.showDiscount,
            (v) => _updateConfig(config.copyWith(showDiscount: v)),
          ),
          _configToggle(
            tr('الضريبة'),
            tr('إظهار مبلغ الضريبة'),
            config.showTax,
            (v) => _updateConfig(config.copyWith(showTax: v)),
          ),
          _configToggle(
            tr('الإجمالي النهائي'),
            tr('إظهار المبلغ الإجمالي للفاتورة'),
            config.showTotal,
            (v) => _updateConfig(config.copyWith(showTotal: v)),
          ),
          _configToggle(
            tr('اسم العميل'),
            tr('إظهار اسم العميل المحدد'),
            config.showCustomerName,
            (v) => _updateConfig(config.copyWith(showCustomerName: v)),
          ),
          const Divider(height: 8),
           Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              tr('رسالة الترحيب'),
              style: const TextStyle(
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
                    decoration:  InputDecoration(
                      labelText: tr('السطر الأول'),
                      isDense: true,
                      border: const OutlineInputBorder(),
                      contentPadding: const EdgeInsets.symmetric(
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
                    decoration:  InputDecoration(
                      labelText: tr('السطر الثاني'),
                      isDense: true,
                      border: const OutlineInputBorder(),
                      contentPadding: const EdgeInsets.symmetric(
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
           Row(
            children: [
              const Icon(PhosphorIconsBold.wifiHigh, size: 16, color: AppColors.info),
              const SizedBox(width: 6),
              Text(
                tr('اتصال الشبكة'),
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 8),
           Text(
            tr('شاشة العميل عبر الشبكة تعمل تلقائياً عند تشغيل السيرفر من إعدادات وضع الشبكة. يمكن لأي جهاز (تابلت، هاتف) على نفس الشبكة فتح الرابط أعلاه.'),
            style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
          ),
          const SizedBox(height: 8),
          if (!_ns.isServerRunning)
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child:  Row(
                children: [
                  const Icon(PhosphorIconsBold.warningCircle,
                      color: AppColors.warning, size: 14),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      tr('السيرفر غير مشغل. شغّل السيرفر من "وضع الشبكة" لتفعيل شاشة العميل عبر الشبكة.'),
                      style: const TextStyle(fontSize: 10, color: AppColors.warning),
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
                isUsb ? tr('إعدادات USB') : tr('إعدادات Serial / COM'),
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
                           DropdownMenuItem(
                            value: null,
                            child: Text(
                              tr('لا توجد منافذ'),
                              style: const TextStyle(
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
            label:  Text(tr('تحديث المنافذ'), style: const TextStyle(fontSize: 11)),
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
                          ? tr('لم يتم العثور على أجهزة USB. تأكد من توصيل الشاشة وتثبيت الدرايفر.')
                          : tr('لم يتم العثور على منافذ COM. تأكد من توصيل كابل Serial.'),
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
           Row(
            children: [
              const Icon(PhosphorIconsBold.screencast, size: 16, color: AppColors.info),
              const SizedBox(width: 6),
              Text(
                tr('إعدادات HDMI / الشاشة الثانية'),
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
            initialValue: _selectedMonitor < monitors.length ? _selectedMonitor : 0,
            decoration:  InputDecoration(
              labelText: tr('اختر الشاشة'),
              isDense: true,
              border: const OutlineInputBorder(),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
            items: monitors.isEmpty
                ? [
                     DropdownMenuItem(
                      value: 0,
                      child: Text(
                        tr('شاشة واحدة فقط'),
                        style:
                            const TextStyle(color: AppColors.textMuted, fontSize: 12),
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
              child:  Row(
                children: [
                  const Icon(PhosphorIconsBold.info, color: AppColors.info, size: 14),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      tr('قم بتوصيل شاشة ثانية عبر HDMI أو DisplayPort، ثم اضبط الشاشة كـ "Extended Display" من إعدادات Windows.'),
                      style: const TextStyle(fontSize: 10, color: AppColors.info),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 8),
           Text(
            tr('سيتم فتح نافذة شاشة العميل في متصفح الويب على الشاشة المحددة مع عرض بيانات السلة في الوقت الفعلي.'),
            style: const TextStyle(fontSize: 10, color: AppColors.textMuted),
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
      diagnostics[tr('نوع الاتصال')] = _selectedType.label;

      if (_selectedType == CfdConnectionType.network) {
        diagnostics[tr('عنوان السيرفر')] = '${_ns.serverAddress}:${_ns.serverPort}';
        diagnostics[tr('حالة السيرفر')] = _ns.isServerRunning ? tr('يعمل ✓') : tr('متوقف ✗');
        result = _ns.isServerRunning;
        if (!result) {
          errorDetail = tr('السيرفر غير مشغل. شغّل السيرفر من إعدادات الشبكة أولاً.');
        }
      } else if (_selectedType == CfdConnectionType.serial || _selectedType == CfdConnectionType.usb) {
        final ports = _selectedType == CfdConnectionType.usb
            ? CfdUsbTransport.getAvailablePorts()
            : CfdSerialTransport.getAvailablePorts();
        diagnostics[tr('المنافذ المتاحة')] = ports.isEmpty ? tr('لا توجد') : ports.join(', ');
        diagnostics[tr('المنفذ المحدد')] = _selectedPort ?? tr('غير محدد');
        diagnostics[tr('سرعة البث')] = '$_selectedBaudRate bps';

        if (_selectedPort == null || !ports.contains(_selectedPort)) {
          errorDetail = _selectedPort == null
              ? tr('لم يتم اختيار منفذ. حدد المنفذ الصحيح.')
              : tr('المنفذ "{_selectedPort}" غير متاح. تحقق من التوصيل وأعد التحديث.', {'_selectedPort': _selectedPort});
        } else {
          result = await _cfd.testConnection(
            _selectedType,
            port: _selectedPort,
            baudRate: _selectedBaudRate,
            monitorIndex: _selectedMonitor,
          );
          if (!result) {
            errorDetail = tr('تعذر فتح المنفذ. تأكد من:\n• عدم استخدام المنفذ من برنامج آخر\n• تثبيت الدرايفر الصحيح\n• توصيل الشاشة بشكل صحيح');
          }
        }
      } else {
        // HDMI
        final monitors = CfdHdmiTransport.getAvailableMonitors();
        diagnostics[tr('عدد الشاشات')] = '${monitors.length}';
        diagnostics[tr('الشاشة المحددة')] = tr('شاشة رقم {_selectedMonitor}', {'_selectedMonitor': _selectedMonitor});

        if (monitors.length <= 1) {
          errorDetail = tr('لم يتم اكتشاف شاشة ثانية.\n• تأكد من توصيل الشاشة عبر HDMI/DisplayPort\n• اضبط الشاشة كـ "Extended Display" من إعدادات Windows');
        } else {
          result = await _cfd.testConnection(
            _selectedType,
            port: _selectedPort,
            baudRate: _selectedBaudRate,
            monitorIndex: _selectedMonitor,
          );
          if (!result) {
            errorDetail = tr('فشل فتح الشاشة الثانية. تحقق من إعدادات العرض في Windows.');
          }
        }
      }

      diagnostics[tr('النتيجة')] = result ? tr('اتصال ناجح ✓') : tr('فشل الاتصال ✗');
    } catch (e) {
      diagnostics[tr('النتيجة')] = tr('خطأ ✗');
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
              Text(success ? tr('اتصال ناجح') : tr('فشل الاتصال')),
            ],
          ),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                 Text(
                  tr('تشخيص الاتصال:'),
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
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
              child:  Text(tr('إغلاق')),
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
          AppToast.show(context, tr('تم الحفظ والاتصال بنجاح ✓'),
              type: ToastType.success);
        } else {
          AppToast.show(context, tr('تم الحفظ لكن فشل الاتصال'),
              type: ToastType.warning);
        }
      }
    } else {
      if (mounted) {
        AppToast.show(context, tr('تم الحفظ ✓'), type: ToastType.success);
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
