part of '../hardware_settings_widget.dart';

// ═══════════════════════════════════════════════════════════════════════════
// HARDWARE SETTINGS — Digital Scale (الميزان الرقمي)
// ═══════════════════════════════════════════════════════════════════════════

mixin _HardwareScaleMixin on ConsumerState<HardwareSettingsWidget> {
  // Abstract — provided by the shell
  String? get selectedScalePort;
  set selectedScalePort(String? val);
  int get selectedBaudRate;
  set selectedBaudRate(int val);
  bool get scaleConnected;
  set scaleConnected(bool val);
  List<String> get availablePorts;
  List<int> get baudRates;
  String get scaleModel;
  set scaleModel(String val);
  String get scaleReadType;
  set scaleReadType(String val);
  int get scaleDataBits;
  set scaleDataBits(int val);
  String get scaleHandshake;
  set scaleHandshake(String val);
  String get scaleParity;
  set scaleParity(String val);
  String get scaleStopBits;
  set scaleStopBits(String val);
  int get scaleWaitTime;
  set scaleWaitTime(int val);
  double get scaleMinWeight;
  set scaleMinWeight(double val);
  double get scaleWeightAlert;
  set scaleWeightAlert(double val);
  ScaleConnectionType get scaleConnectionType;
  set scaleConnectionType(ScaleConnectionType val);
  String get scaleTcpHost;
  set scaleTcpHost(String val);
  int get scaleTcpPort;
  set scaleTcpPort(int val);

  Widget buildSectionCard({required String title, required IconData icon, required Color iconColor, required List<Widget> children});
  Widget buildStatusBadge(String text, Color color, IconData icon);

  Future<void> connectScale() async {
    bool success;
    if (scaleConnectionType == ScaleConnectionType.tcp) {
      if (scaleTcpHost.isEmpty) {
        if (mounted) AppToast.show(context, 'يرجى إدخال عنوان IP الميزان', type: ToastType.error);
        return;
      }
      success = await ScaleService.instance.connectTcp(
        host: scaleTcpHost,
        port: scaleTcpPort,
      );
    } else {
      if (selectedScalePort == null) {
        if (mounted) AppToast.show(context, 'يرجى اختيار منفذ COM', type: ToastType.error);
        return;
      }
      success = await ScaleService.instance.connect(
        portName: selectedScalePort!,
        baudRate: selectedBaudRate,
        dataBits: scaleDataBits,
        parity: scaleParity,
        stopBits: scaleStopBits,
      );
    }
    setState(() => scaleConnected = success);
    if (mounted) {
      if (success) {
        final mode = ScaleService.instance.detectedMode;
        final modeStr = mode == ScaleMode.continuous ? 'بث مستمر' : 'أوامر';
        final connStr = scaleConnectionType == ScaleConnectionType.tcp ? 'TCP' : 'COM';
        AppToast.show(context, 'تم الاتصال بالميزان ($connStr - وضع: $modeStr)', type: ToastType.success);
      } else {
        AppToast.show(context, 'فشل الاتصال بالميزان — تأكد من الإعدادات', type: ToastType.error);
      }
    }
  }

  Future<void> disconnectScale() async {
    await ScaleService.instance.disconnect();
    setState(() => scaleConnected = false);
  }

  Future<void> testScale() async {
    final success = await ScaleService.instance.testConnection();
    if (success) {
      final weight = await ScaleService.instance.readWeight();
      if (mounted) {
        AppToast.show(context, weight != null ? 'الميزان يعمل \u2713 الوزن: ${weight.toStringAsFixed(3)} كجم' : 'الميزان يعمل \u2713', type: ToastType.success);
      }
    } else {
      if (mounted) AppToast.show(context, 'فشل اختبار الميزان - تأكد من التوصيل', type: ToastType.error);
    }
  }

  void tareScale() {
    ScaleService.instance.tare();
    if (mounted) AppToast.show(context, 'تم تصفير الميزان \u2713', type: ToastType.success);
  }

  Future<void> calibrateScale() async {
    if (!ScaleService.instance.isBinaryProtocol) {
      if (mounted) AppToast.show(context, 'المعايرة متاحة فقط لموازين البروتوكول الثنائي', type: ToastType.info);
      return;
    }

    final controller = TextEditingController();
    final result = await showDialog<double>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('معايرة الميزان'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('1. تأكد أن الميزان فارغ واضغط تصفير أولاً'),
            const Text('2. ضع وزن معروف على الميزان'),
            const Text('3. أدخل الوزن الفعلي بالكيلو'),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(hintText: 'مثال: 0.5 (لـ 500 جرام)', labelText: 'الوزن الفعلي (كجم)', suffixText: 'كجم'),
              autofocus: true,
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
            FilledButton(onPressed: () { final val = double.tryParse(controller.text); Navigator.pop(ctx, val); }, child: const Text('معايرة')),
          ],
        ),
      ),
    );

    if (result != null && result > 0) {
      final ok = await ScaleService.instance.calibrate(result);
      if (mounted) {
        if (ok) { AppToast.show(context, 'تمت المعايرة بنجاح \u2713', type: ToastType.success); }
        else { AppToast.show(context, 'فشلت المعايرة — تأكد من تصفير الميزان ووضع الوزن عليه', type: ToastType.error); }
      }
    }
  }

  bool _canConnect() {
    if (scaleConnectionType == ScaleConnectionType.tcp) {
      return scaleTcpHost.isNotEmpty;
    }
    return selectedScalePort != null;
  }

  Widget buildScaleSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface, borderRadius: BorderRadius.circular(12),
        border: scaleConnected ? Border.all(color: AppColors.success, width: 2) : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(children: [
            Icon(PhosphorIconsBold.scales, color: scaleConnected ? AppColors.success : AppColors.primary, size: 20),
            const SizedBox(width: 8),
            const Text('الميزان الرقمي', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            const Spacer(),
            if (scaleConnected) buildStatusBadge('متصل', AppColors.success, PhosphorIconsBold.checkCircle),
          ]),
          const Divider(height: 20),

          // Row 1: Scale model + Read type + Connection type
          Row(children: [
            Expanded(child: DropdownButtonFormField<String>(initialValue: scaleModel, decoration: const InputDecoration(labelText: 'نوع الميزان', isDense: true),
              items: const [
                DropdownMenuItem(value: 'auto', child: Text('اكتشاف تلقائي')),
                DropdownMenuItem(value: 'dibalG310', child: Text('Dibal G310')),
                DropdownMenuItem(value: 'aclasOS2X', child: Text('Aclas OS2X')),
                DropdownMenuItem(value: 'aclasPS1X', child: Text('Aclas PS1X')),
                DropdownMenuItem(value: 'posScale', child: Text('POS Scale')),
                DropdownMenuItem(value: 'marta', child: Text('Marta')),
                DropdownMenuItem(value: 'tem', child: Text('TEM')),
              ],
              onChanged: (v) => setState(() => scaleModel = v ?? 'auto'),
            )),
            const SizedBox(width: 12),
            Expanded(child: DropdownButtonFormField<String>(initialValue: scaleReadType, decoration: const InputDecoration(labelText: 'نوع القراءة', isDense: true),
              items: const [
                DropdownMenuItem(value: 'auto', child: Text('تلقائي')),
                DropdownMenuItem(value: 'continuous', child: Text('مستمر')),
                DropdownMenuItem(value: 'stable', child: Text('عند الاستقرار')),
                DropdownMenuItem(value: 'onEnter', child: Text('عند الضغط Enter')),
              ],
              onChanged: (v) => setState(() => scaleReadType = v ?? 'auto'),
            )),
            const SizedBox(width: 12),
            Expanded(child: DropdownButtonFormField<ScaleConnectionType>(
              value: scaleConnectionType,
              decoration: const InputDecoration(labelText: 'طريقة الاتصال', isDense: true),
              items: const [
                DropdownMenuItem(value: ScaleConnectionType.serial, child: Text('COM Port (USB/RS232)')),
                DropdownMenuItem(value: ScaleConnectionType.tcp, child: Text('شبكة (TCP/IP)')),
              ],
              onChanged: (v) => setState(() => scaleConnectionType = v ?? ScaleConnectionType.serial),
            )),
          ]),
          const SizedBox(height: 12),

          // Connection settings — conditional on connection type
          if (scaleConnectionType == ScaleConnectionType.tcp) ...[
            // TCP/IP settings
            Row(children: [
              Expanded(flex: 3, child: TextFormField(
                initialValue: scaleTcpHost,
                decoration: const InputDecoration(
                  labelText: 'عنوان IP الميزان',
                  hintText: 'مثال: 192.168.1.100',
                  isDense: true,
                  prefixIcon: Icon(PhosphorIconsBold.globe, size: 18),
                ),
                onChanged: (v) => scaleTcpHost = v.trim(),
              )),
              const SizedBox(width: 12),
              Expanded(flex: 1, child: TextFormField(
                initialValue: '$scaleTcpPort',
                decoration: const InputDecoration(
                  labelText: 'المنفذ (Port)',
                  hintText: '4001',
                  isDense: true,
                ),
                keyboardType: TextInputType.number,
                onChanged: (v) => scaleTcpPort = int.tryParse(v) ?? 4001,
              )),
            ]),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.info.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Row(children: [
                Icon(PhosphorIconsBold.info, size: 14, color: AppColors.info),
                SizedBox(width: 6),
                Expanded(child: Text(
                  'أدخل عنوان IP الميزان فقط. المنافذ الشائعة: 4001, 8000, 9100. لا حاجة لـ COM Port.',
                  style: TextStyle(fontSize: 11, color: AppColors.info),
                )),
              ]),
            ),
          ] else ...[
            // Serial COM Port settings
            Row(children: [
              Expanded(flex: 2, child: DropdownButtonFormField<String>(initialValue: selectedScalePort, decoration: const InputDecoration(labelText: 'COM Port', isDense: true),
                items: availablePorts.map((port) => DropdownMenuItem(value: port, child: Text(port))).toList(),
                onChanged: (v) => setState(() => selectedScalePort = v), hint: const Text('اختر المنفذ'),
              )),
              const SizedBox(width: 12),
              Expanded(child: DropdownButtonFormField<int>(initialValue: selectedBaudRate, decoration: const InputDecoration(labelText: 'Baud Rate', isDense: true),
                items: baudRates.map((rate) => DropdownMenuItem(value: rate, child: Text('$rate'))).toList(),
                onChanged: (v) => setState(() => selectedBaudRate = v ?? 9600),
              )),
            ]),
            const SizedBox(height: 12),

            // Row 3: Data Bits + Handshake + Parity
            Row(children: [
              Expanded(child: DropdownButtonFormField<int>(initialValue: scaleDataBits, decoration: const InputDecoration(labelText: 'Data Bits', isDense: true),
                items: const [DropdownMenuItem(value: 7, child: Text('7')), DropdownMenuItem(value: 8, child: Text('8'))],
                onChanged: (v) => setState(() => scaleDataBits = v ?? 8),
              )),
              const SizedBox(width: 12),
              Expanded(child: DropdownButtonFormField<String>(initialValue: scaleHandshake, decoration: const InputDecoration(labelText: 'Handshake', isDense: true),
                items: const [
                  DropdownMenuItem(value: 'none', child: Text('None')),
                  DropdownMenuItem(value: 'xonXoff', child: Text('Xon/Xoff')),
                  DropdownMenuItem(value: 'rts', child: Text('RTS')),
                  DropdownMenuItem(value: 'rtsXonXoff', child: Text('RTS + Xon/Xoff')),
                ],
                onChanged: (v) => setState(() => scaleHandshake = v ?? 'none'),
              )),
              const SizedBox(width: 12),
              Expanded(child: DropdownButtonFormField<String>(initialValue: scaleParity, decoration: const InputDecoration(labelText: 'Parity', isDense: true),
                items: const [
                  DropdownMenuItem(value: 'none', child: Text('None')),
                  DropdownMenuItem(value: 'odd', child: Text('Odd')),
                  DropdownMenuItem(value: 'even', child: Text('Even')),
                  DropdownMenuItem(value: 'mark', child: Text('Mark')),
                  DropdownMenuItem(value: 'space', child: Text('Space')),
                ],
                onChanged: (v) => setState(() => scaleParity = v ?? 'none'),
              )),
            ]),
            const SizedBox(height: 12),

            // Row 4: Stop Bits
            Row(children: [
              Expanded(child: DropdownButtonFormField<String>(initialValue: scaleStopBits, decoration: const InputDecoration(labelText: 'Stop Bits', isDense: true),
                items: const [
                  DropdownMenuItem(value: 'none', child: Text('None')),
                  DropdownMenuItem(value: 'one', child: Text('One')),
                  DropdownMenuItem(value: 'two', child: Text('Two')),
                  DropdownMenuItem(value: 'onePointFive', child: Text('1.5')),
                ],
                onChanged: (v) => setState(() => scaleStopBits = v ?? 'one'),
              )),
              const SizedBox(width: 12),
              const Expanded(child: SizedBox()), // spacer
              const SizedBox(width: 12),
              const Expanded(child: SizedBox()), // spacer
            ]),
          ],
          const SizedBox(height: 12),

          // Row: Wait Time + Min Weight + Weight Alert (shared for both modes)
          Row(children: [
            Expanded(child: TextFormField(initialValue: '$scaleWaitTime', decoration: const InputDecoration(labelText: 'مدة الانتظار (ث)', isDense: true),
              keyboardType: TextInputType.number, onChanged: (v) => scaleWaitTime = int.tryParse(v) ?? 30,
            )),
            const SizedBox(width: 12),
            Expanded(child: TextFormField(initialValue: scaleMinWeight > 0 ? scaleMinWeight.toString() : '', decoration: const InputDecoration(labelText: 'أقل وزن (كغ)', isDense: true),
              keyboardType: const TextInputType.numberWithOptions(decimal: true), onChanged: (v) => scaleMinWeight = double.tryParse(v) ?? 0.0,
            )),
            const SizedBox(width: 12),
            Expanded(child: TextFormField(initialValue: scaleWeightAlert > 0 ? scaleWeightAlert.toString() : '', decoration: const InputDecoration(labelText: 'تنبيه الوزن (كغ)', isDense: true),
              keyboardType: const TextInputType.numberWithOptions(decimal: true), onChanged: (v) => scaleWeightAlert = double.tryParse(v) ?? 0.0,
            )),
          ]),
          const SizedBox(height: 14),

          // Action buttons
          Row(children: [
            if (scaleConnected)
              Expanded(child: OutlinedButton.icon(
                onPressed: disconnectScale, icon: const Icon(PhosphorIconsBold.plugsConnected, size: 16), label: const Text('قطع الاتصال'),
                style: OutlinedButton.styleFrom(foregroundColor: AppColors.error),
              ))
            else
              Expanded(child: ElevatedButton.icon(
                onPressed: _canConnect() ? connectScale : null,
                icon: const Icon(PhosphorIconsBold.plugs, size: 16), label: const Text('اتصال'),
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.success),
              )),
            const SizedBox(width: 8),
            ElevatedButton.icon(onPressed: !scaleConnected ? null : testScale, icon: const Icon(PhosphorIconsBold.scales, size: 16), label: const Text('اختبار')),
            const SizedBox(width: 8),
            ElevatedButton.icon(onPressed: !scaleConnected ? null : tareScale, icon: const Icon(PhosphorIconsBold.arrowCounterClockwise, size: 16), label: const Text('تصفير'),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.warning)),
            const SizedBox(width: 8),
            ElevatedButton.icon(onPressed: !scaleConnected ? null : calibrateScale, icon: const Icon(PhosphorIconsBold.wrench, size: 16), label: const Text('معايرة'),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurple)),
          ]),
        ],
      ),
    );
  }
}
