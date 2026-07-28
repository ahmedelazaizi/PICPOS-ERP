// نسخة حرفية من lib/presentation/screens/settings/network_mode_settings.dart
// (مصيدة النسخ §٥.٨) — أي إصلاح منطقي يتصلّح في المصدر أولاً ثم يُنقل بـ patch
// لهذا الملف. لا يُنسخ أبداً من D:\URAL-ERP. `part of` فقط تغيّر — لا تعديل
// منطقي ولا تسمية (الكلاس خاص، لا تعارض عبر المكتبات).
part of 'settings_picpos_screen.dart';

// ═══════════════════════════════════════════════════════════════════════════
// NETWORK MODE SETTINGS — Server/Client/Standalone
// ═══════════════════════════════════════════════════════════════════════════

/// Network Mode Settings — Server/Client/Standalone
class _NetworkModeSettings extends ConsumerStatefulWidget {
  const _NetworkModeSettings();

  @override
  ConsumerState<_NetworkModeSettings> createState() =>
      _NetworkModeSettingsState();
}

class _NetworkModeSettingsState extends ConsumerState<_NetworkModeSettings> {
  final _addressController = TextEditingController();
  final _portController = TextEditingController(text: '8080');
  bool _loading = true;
  bool _isServerStarting = false;
  bool _isTesting = false;
  bool _isSyncing = false;
  String? _testResult;
  int? _selectedBranchId;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final syncRepo = ref.read(syncRepositoryProvider);
    await syncRepo.loadSettings();
    _addressController.text = syncRepo.serverAddress ?? '';
    _portController.text = syncRepo.serverPort.toString();
    // Load saved client branch assignment
    final prefs = await SharedPreferences.getInstance();
    _selectedBranchId = prefs.getInt('client_branch_id');
    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    _addressController.dispose();
    _portController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Mode selector
          Row(
            children: [
              const Icon(PhosphorIconsBold.wifiHigh, color: AppColors.primary),
              const SizedBox(width: 12),
              const Text('وضع التشغيل', style: AppTypography.bodyLarge),
              const Spacer(),
              _buildModeChip(
                NetworkMode.standalone,
                'مستقل',
                PhosphorIconsBold.monitor,
              ),
              const SizedBox(width: 8),
              _buildModeChip(
                NetworkMode.server,
                'سيرفر',
                PhosphorIconsBold.cloud,
              ),
              const SizedBox(width: 8),
              _buildModeChip(
                NetworkMode.client,
                'عميل',
                PhosphorIconsBold.devices,
              ),
            ],
          ),

          if (ref.watch(syncRepositoryProvider).mode == NetworkMode.server) ...[
            const Divider(height: 24),
            _buildServerPanel(),
          ],

          // strict-client OK: client-specific UI panel; mirror has its own.
          if (ref.watch(syncRepositoryProvider).mode == NetworkMode.client) ...[
            const Divider(height: 24),
            _buildClientPanel(),
          ],
        ],
      ),
    );
  }

  Widget _buildModeChip(NetworkMode mode, String label, IconData icon) {
    final syncRepo = ref.read(syncRepositoryProvider);
    final isSelected = syncRepo.mode == mode;
    return ChoiceChip(
      avatar: Icon(
        icon,
        size: 18,
        color: isSelected ? Colors.white : AppColors.textMuted,
      ),
      label: Text(
        label,
        style: TextStyle(color: isSelected ? Colors.white : null),
      ),
      selected: isSelected,
      selectedColor: AppColors.primary,
      onSelected: (selected) async {
        if (selected) {
          await syncRepo.setMode(mode);
          setState(() {});
        }
      },
    );
  }

  // ignore: unused_element
  Widget _buildNetworkSettings() {
    final syncRepo = ref.watch(syncRepositoryProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // CFD & QR Menu Quick Access (Prominent)
        Card(
          margin: const EdgeInsets.only(bottom: 24),
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: AppColors.primary.withValues(alpha: 0.1)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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
                          'شاشة العميل والمنيو (Quick Access)',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: syncRepo.isServerRunning
                            ? AppColors.success.withValues(alpha: 0.1)
                            : AppColors.error.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        syncRepo.isServerRunning ? 'متصل' : 'غير متصل',
                        style: TextStyle(
                          color: syncRepo.isServerRunning
                              ? AppColors.success
                              : AppColors.error,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                if (!syncRepo.isServerRunning)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.warning.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(
                        children: [
                          Icon(
                            PhosphorIconsBold.warningCircle,
                            color: AppColors.warning,
                            size: 16,
                          ),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'يجب بدء تشغيل السيرفر من "إعدادات الربط" أدناه لتفعيل الروابط.',
                              style: TextStyle(
                                fontSize: 11,
                                color: AppColors.warning,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                _buildUrlLink(
                  title: 'شاشة العميل (CFD)',
                  url: 'http://${syncRepo.serverAddress}:${syncRepo.serverPort}/cfd',
                  icon: PhosphorIconsBold.monitor,
                  color: Colors.blue,
                  enabled: syncRepo.isServerRunning,
                ),
                const SizedBox(height: 12),
                _buildUrlLink(
                  title: 'منيو الطاولات (QR Menu)',
                  url: 'http://${syncRepo.serverAddress}:${syncRepo.serverPort}/menu',
                  icon: PhosphorIconsBold.qrCode,
                  color: Colors.purple,
                  enabled: syncRepo.isServerRunning,
                ),
              ],
            ),
          ),
        ),

        const Text('إعدادات الربط والشبكة', style: AppTypography.h3),
        const SizedBox(height: 16), // Added spacing
      ],
    );
  }

  Widget _buildServerPanel() {
    final syncRepo = ref.watch(syncRepositoryProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Server status
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: syncRepo.isServerRunning
                ? AppColors.success.withValues(alpha: 0.1)
                : AppColors.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: syncRepo.isServerRunning ? AppColors.success : AppColors.border,
            ),
          ),
          child: Row(
            children: [
              Icon(
                syncRepo.isServerRunning
                    ? PhosphorIconsBold.checkCircle
                    : PhosphorIconsBold.warning,
                color: syncRepo.isServerRunning
                    ? AppColors.success
                    : AppColors.warning,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      syncRepo.isServerRunning ? 'السيرفر يعمل' : 'السيرفر متوقف',
                      style: AppTypography.bodyLarge,
                    ),
                    if (syncRepo.isServerRunning) ...[
                      Text(
                        'http://${syncRepo.serverAddress}:${syncRepo.serverPort}',
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                          color: AppColors.primary,
                        ),
                      ),
                      Text(
                        'العملاء المتصلين: ${syncRepo.connectedClientCount}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textMuted,
                        ),
                      ),
                      const SizedBox(height: 6),
                      // A-SEC-1: the API token is only exposed via /api/health
                      // while this window is open — click it before pairing a
                      // brand-new client/mirror device.
                      OutlinedButton.icon(
                        onPressed: () {
                          syncRepo.openDevicePairingWindow();
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                    'نافذة اقتران جهاز جديد مفتوحة لمدة 5 دقائق'),
                              ),
                            );
                          }
                        },
                        icon: const Icon(Icons.devices, size: 16),
                        label: const Text('افتح نافذة اقتران جهاز جديد'),
                      ),
                    ],
                  ],
                ),
              ),
              ElevatedButton.icon(
                onPressed: _isServerStarting
                    ? null
                    : () async {
                        setState(() => _isServerStarting = true);
                        if (syncRepo.isServerRunning) {
                          await syncRepo.stopServer();
                        } else {
                          await syncRepo.startServer(
                            port: int.tryParse(_portController.text) ?? 8080,
                          );
                        }
                        if (mounted) setState(() => _isServerStarting = false);
                      },
                icon: Icon(
                  syncRepo.isServerRunning
                      ? PhosphorIconsBold.stop
                      : PhosphorIconsBold.play,
                  size: 18,
                ),
                label: Text(syncRepo.isServerRunning ? 'إيقاف' : 'تشغيل'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: syncRepo.isServerRunning
                      ? AppColors.error
                      : AppColors.success,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (syncRepo.isServerRunning) ...[
          const SizedBox(height: 8),
          Center(
            child: Text(
              syncRepo.isServerUsingTls
                  ? '🔒 السيرفر يعمل عبر HTTPS (TLS مفعَّل)'
                  : 'السيرفر قيد التشغيل (HTTP — غير مشفَّر)',
              style: TextStyle(
                fontSize: 11,
                color: syncRepo.isServerUsingTls
                    ? AppColors.success
                    : AppColors.warning,
              ),
            ),
          ),
        ],
        const Divider(height: 24),
        _buildTlsPanel(),
      ],
    );
  }

  Widget _buildTlsPanel() {
    final syncRepo = ref.watch(syncRepositoryProvider);
    final validationError = syncRepo.validateTlsConfig();
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
              const Icon(PhosphorIconsBold.lock, color: AppColors.primary),
              const SizedBox(width: 8),
              const Text(
                'أمان TLS / HTTPS',
                style: AppTypography.bodyLarge,
              ),
              const Spacer(),
              Switch(
                value: syncRepo.tlsEnabled,
                onChanged: syncRepo.isServerRunning
                    ? null
                    : (v) async {
                        await syncRepo.configureTls(
                          enabled: v,
                          certPath: syncRepo.tlsCertPath,
                          keyPath: syncRepo.tlsKeyPath,
                        );
                        if (mounted) setState(() {});
                      },
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            syncRepo.tlsCertPath == null
                ? 'لم يُحدَّد ملف شهادة'
                : 'شهادة: ${syncRepo.tlsCertPath}',
            style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
          ),
          Text(
            syncRepo.tlsKeyPath == null
                ? 'لم يُحدَّد ملف مفتاح'
                : 'مفتاح: ${syncRepo.tlsKeyPath}',
            style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(PhosphorIconsBold.fileArrowUp, size: 16),
                  label: const Text('اختر ملف الشهادة (cert.pem)'),
                  onPressed: syncRepo.isServerRunning
                      ? null
                      : () => _pickTlsFile(isCert: true),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(PhosphorIconsBold.key, size: 16),
                  label: const Text('اختر ملف المفتاح (key.pem)'),
                  onPressed: syncRepo.isServerRunning
                      ? null
                      : () => _pickTlsFile(isCert: false),
                ),
              ),
            ],
          ),
          if (validationError != null) ...[
            const SizedBox(height: 8),
            Text(
              '⚠️ $validationError',
              style: const TextStyle(fontSize: 11, color: AppColors.error),
            ),
          ],
          const SizedBox(height: 8),
          const Text(
            'لتوليد شهادة ذاتية: scripts/generate_self_signed_cert.ps1 — راجع docs/DEPLOYMENT.md',
            style: TextStyle(fontSize: 10, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }

  Future<void> _pickTlsFile({required bool isCert}) async {
    final result = await FilePicker.pickFiles(
      type: FileType.any,
      dialogTitle: isCert ? 'اختر ملف الشهادة' : 'اختر ملف المفتاح الخاص',
    );
    if (result == null || result.files.single.path == null) return;
    final path = result.files.single.path!;
    final syncRepo = ref.read(syncRepositoryProvider);
    await syncRepo.configureTls(
      enabled: syncRepo.tlsEnabled,
      certPath: isCert ? path : syncRepo.tlsCertPath,
      keyPath: isCert ? syncRepo.tlsKeyPath : path,
    );
    if (mounted) setState(() {});
  }

  Widget _buildUrlLink({
    required String title,
    required String url,
    required IconData icon,
    required Color color,
    bool enabled = true,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
          Icon(icon, size: 20, color: enabled ? color : Colors.grey),
          const SizedBox(width: 12),
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
                    fontSize: 11,
                    color: enabled
                        ? AppColors.textMuted
                        : Colors.grey.withValues(alpha: 0.5),
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(
              PhosphorIconsBold.arrowSquareOut,
              size: 20,
              color: enabled ? null : Colors.grey,
            ),
            onPressed: enabled ? () => launchUrl(Uri.parse(url)) : null,
            tooltip: enabled ? 'فتح في المتصفح' : 'السيرفر متوقف',
          ),
        ],
      ),
    );
  }

  Widget _buildClientPanel() {
    final isUrl = _addressController.text.startsWith('http://') ||
        _addressController.text.startsWith('https://');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Server address
        Row(
          children: [
            const Text('عنوان السيرفر: ', style: AppTypography.bodyLarge),
            Expanded(
              child: TextField(
                controller: _addressController,
                onChanged: (_) => setState(() {}), // refresh port visibility
                decoration: const InputDecoration(
                  isDense: true,
                  border: OutlineInputBorder(),
                  hintText: '192.168.1.100  أو  https://xxx.ngrok-free.app',
                  hintStyle: TextStyle(fontSize: 12),
                ),
              ),
            ),
            if (!isUrl) ...[
              const SizedBox(width: 8),
              const Text(':', style: AppTypography.bodyLarge),
              const SizedBox(width: 8),
              SizedBox(
                width: 80,
                child: TextField(
                  controller: _portController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    isDense: true,
                    border: OutlineInputBorder(),
                    hintText: '8080',
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 12),
        // Actions
        Row(
          children: [
            ElevatedButton.icon(
              onPressed: _isTesting
                  ? null
                  : () async {
                      setState(() {
                        _isTesting = true;
                        _testResult = null;
                      });
                      final syncRepo = ref.read(syncRepositoryProvider);
                      final result = await syncRepo.testConnection(
                        _addressController.text,
                        int.tryParse(_portController.text) ?? 8080,
                      );
                      if (mounted) {
                        setState(() {
                          _isTesting = false;
                          _testResult = result['success'] == true
                              ? '✅ تم الاتصال بنجاح'
                              : '❌ فشل: ${result['error']}';
                        });
                      }
                    },
              icon: _isTesting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(PhosphorIconsBold.plugs, size: 18),
              label: const Text('اختبار الاتصال'),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.info),
            ),
            const SizedBox(width: 12),
            ElevatedButton.icon(
              onPressed: _isSyncing
                  ? null
                  : () async {
                      final syncRepo = ref.read(syncRepositoryProvider);
                      syncRepo.setServerAddress(
                        _addressController.text,
                        port: int.tryParse(_portController.text) ?? 8080,
                      );
                      await syncRepo.saveSettings();
                      setState(() {
                        _testResult = '✅ تم حفظ الإعدادات — جاري الاتصال...';
                        _isSyncing = true;
                      });

                      // Step 1: test connection first (extracts API token)
                      final testResult = await syncRepo.testConnection(
                        _addressController.text,
                        int.tryParse(_portController.text) ?? 8080,
                      );
                      if (testResult['success'] != true) {
                        if (mounted) {
                          setState(() {
                            _isSyncing = false;
                            _testResult = '❌ فشل الاتصال: ${testResult['error']}';
                          });
                        }
                        return;
                      }

                      // Step 2: full sync with token already set
                      try {
                        final ns = NetworkService.instance;
                        final serverUrl = ns.buildServerUrl(
                          address: _addressController.text,
                          port: int.tryParse(_portController.text) ?? 8080,
                        );
                        final result = await syncRepo.performFullSync(serverUrl);
                        WebSocketSyncClient.instance.connect();
                        if (mounted) {
                          setState(() {
                            _isSyncing = false;
                            _testResult = result.success
                                ? '✅ تمت المزامنة — ${result.itemsSynced} عنصر'
                                : '⚠️ ${result.message}';
                          });
                        }
                      } catch (e) {
                        if (mounted) {
                          setState(() {
                            _isSyncing = false;
                            _testResult = '❌ فشلت المزامنة: $e';
                          });
                        }
                      }
                    },
              icon: _isSyncing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(PhosphorIconsBold.floppyDisk, size: 18),
              label: Text(_isSyncing ? 'جاري المزامنة...' : 'حفظ وربط'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.success,
              ),
            ),
          ],
        ),
        if (_testResult != null) ...[
          const SizedBox(height: 8),
          Text(
            _testResult!,
            style: TextStyle(
              color: _testResult!.startsWith('✅')
                  ? AppColors.success
                  : AppColors.error,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
        const SizedBox(height: 16),
        // ── Branch Assignment ──
        _buildBranchAssignmentDropdown(),
      ],
    );
  }

  Widget _buildBranchAssignmentDropdown() {
    final branchRepo = ref.read(branchRepositoryProvider);
    return StreamBuilder<List<Branche>>(
      stream: branchRepo.watchAllBranches(),
      builder: (context, snapshot) {
        final branches = snapshot.data ?? [];
        if (branches.isEmpty) {
          return const Text(
            '⚠️ لا توجد فروع — قم بالمزامنة أولاً',
            style: TextStyle(color: Colors.grey, fontSize: 12),
          );
        }
        // Validate current selection
        final validIds = branches.map((b) => b.id).toSet();
        final currentVal = validIds.contains(_selectedBranchId) ? _selectedBranchId : null;
        return Row(
          children: [
            const Icon(PhosphorIconsBold.buildings, color: AppColors.primary, size: 20),
            const SizedBox(width: 8),
            const Text('الفرع المعين: ', style: AppTypography.bodyLarge),
            const SizedBox(width: 8),
            Expanded(
              child: DropdownButtonFormField<int?>(
                initialValue: currentVal,
                decoration: const InputDecoration(
                  isDense: true,
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                items: [
                  const DropdownMenuItem<int?>(
                    value: null,
                    child: Text('غير محدد'),
                  ),
                  ...branches.map(
                    (b) => DropdownMenuItem<int?>(
                      value: b.id,
                      child: Text(b.name),
                    ),
                  ),
                ],
                onChanged: (value) async {
                  setState(() => _selectedBranchId = value);
                  final prefs = await SharedPreferences.getInstance();
                  if (value != null) {
                    await prefs.setInt('client_branch_id', value);
                  } else {
                    await prefs.remove('client_branch_id');
                  }
                  // Re-init sync service so it picks up the new branch_id
                  // without requiring an app restart.
                  await SyncService.instance?.initialize();
                  if (mounted) {
                    AppToast.show(context, 'تم حفظ الفرع المعين', type: ToastType.success);
                  }
                },
              ),
            ),
          ],
        );
      },
    );
  }
}
