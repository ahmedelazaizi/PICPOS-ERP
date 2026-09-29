import 'package:ural_erp/core/i18n/tr.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../data/database/pg_config.dart';
import '../../../data/database/connection_io.dart' show testPostgresConnection;
import '../../../data/providers/providers.dart';
import '../../../services/network_service.dart';
import '../../../core/config/brand.dart';

/// Shows the full-screen database connection settings dialog.
void showDatabaseSettingsDialog(BuildContext context) {
  showDialog(
    context: context,
    builder: (_) => const _DatabaseSettingsDialog(),
  );
}

class _DatabaseSettingsDialog extends ConsumerStatefulWidget {
  const _DatabaseSettingsDialog();

  @override
  ConsumerState<_DatabaseSettingsDialog> createState() =>
      _DatabaseSettingsDialogState();
}

class _DatabaseSettingsDialogState
    extends ConsumerState<_DatabaseSettingsDialog> {
  DatabaseMode _mode = DatabaseMode.sqlite;
  bool _testing = false;
  String? _testResult; // null = not tested, '' = success, 'error msg' = failed

  final _hostCtrl = TextEditingController(text: 'localhost');
  final _portCtrl = TextEditingController(text: '5432');
  final _dbCtrl = TextEditingController(text: Brand.pgIdentifier);
  final _userCtrl = TextEditingController(text: Brand.pgIdentifier);
  final _passCtrl = TextEditingController();
  bool _useSsl = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final mode = await PostgresConfig.loadMode();
    final config = await PostgresConfig.load();
    if (!mounted) return;
    setState(() {
      _mode = mode;
      _hostCtrl.text = config.host;
      _portCtrl.text = config.port.toString();
      _dbCtrl.text = config.database;
      _userCtrl.text = config.username;
      _passCtrl.text = config.password;
      _useSsl = config.useSsl;
    });
  }

  PostgresConfig _buildConfig() => PostgresConfig(
        host: _hostCtrl.text.trim(),
        port: int.tryParse(_portCtrl.text.trim()) ?? 5432,
        database: _dbCtrl.text.trim(),
        username: _userCtrl.text.trim(),
        password: _passCtrl.text,
        useSsl: _useSsl,
      );

  Future<void> _testConnection() async {
    setState(() {
      _testing = true;
      _testResult = null;
    });

    final config = _buildConfig();
    final error = await testPostgresConnection(config);

    if (!mounted) return;
    setState(() {
      _testing = false;
      _testResult = error ?? ''; // '' means success
    });

    if (error == null) {
      AppToast.show(context, tr('تم الاتصال بنجاح ✓'), type: ToastType.success);
    } else {
      AppToast.show(context, tr('فشل الاتصال: {error}', {'error': error}), type: ToastType.error);
    }
  }

  Future<void> _saveAndApply() async {
    // Save mode
    await PostgresConfig.saveMode(_mode);

    // Save PostgreSQL config
    if (_mode == DatabaseMode.postgres) {
      final config = _buildConfig();
      await config.save();

      // Auto-configure network mode based on PostgreSQL host:
      // - localhost/127.0.0.1 → this machine IS the server → NetworkMode.server
      //   (starts HTTP API on port 8080 for clients to connect)
      // - remote host → this machine is a client → NetworkMode.client
      //   (syncs data via HTTP from the remote server)
      final ns = NetworkService.instance;
      final db = ref.read(databaseProvider);
      final pgHost = config.host.trim();
      if (pgHost == 'localhost' || pgHost == '127.0.0.1') {
        // Spec 089: thread DB into setMode so prefs + canonical DB store
        // are updated together.
        await ns.setMode(NetworkMode.server, db: db);
        await ns.saveSettings();
        debugPrint('[DB Settings] Auto-configured SERVER mode: HTTP API will start on port 8080');
      } else {
        // FIX: Only set address — preserve the server port from Setup Wizard.
        // The user configures the WAN port in the Setup Wizard (e.g. 9090),
        // which may differ from the internal LAN port (8080).
        // Previously this hardcoded port: 8080, overwriting the WAN port.
        final existingPort = ns.serverPort;
        ns.setServerAddress(pgHost, port: existingPort != 8080 ? existingPort : null);
        await ns.setMode(NetworkMode.client, db: db);
        await ns.saveSettings();
        debugPrint('[DB Settings] Auto-configured CLIENT mode: HTTP sync to $pgHost:${ns.serverPort}');
      }
    }

    // When switching to SQLite (local), reset NetworkService mode
    // to standalone. This clears any stale 'client' mode.
    if (_mode == DatabaseMode.sqlite) {
      final currentNetMode = NetworkService.instance.mode;
      if (currentNetMode != NetworkMode.client && currentNetMode != NetworkMode.mirror) {
        await NetworkService.instance.setMode(
          NetworkMode.standalone,
          db: ref.read(databaseProvider),
        );
      }
    }

    if (!mounted) return;

    Navigator.pop(context);

    // Show restart prompt
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          icon: const Icon(PhosphorIconsBold.arrowsClockwise,
              size: 48, color: AppColors.primary),
          title:  Text(tr('يلزم إعادة تشغيل التطبيق')),
          content:  Text(
            tr('تم حفظ إعدادات قاعدة البيانات بنجاح.\nيلزم إغلاق التطبيق وإعادة فتحه لتفعيل التغييرات.'),
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx),
              child:  Text(tr('حسناً')),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _hostCtrl.dispose();
    _portCtrl.dispose();
    _dbCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500, maxHeight: 700),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withAlpha(25),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(PhosphorIconsBold.database,
                          color: AppColors.primary, size: 28),
                    ),
                    const SizedBox(width: 12),
                     Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(tr('إعدادات قاعدة البيانات'),
                              style: const TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.bold)),
                          Text(tr('اختيار وضع الاتصال: محلي أو سيرفر'),
                              style: const TextStyle(
                                  fontSize: 12, color: AppColors.textSecondary)),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(PhosphorIconsBold.x),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // Mode selector
                SegmentedButton<DatabaseMode>(
                  segments: [
                     ButtonSegment(
                      value: DatabaseMode.sqlite,
                      label: Text(tr('محلي (SQLite)')),
                      icon: const Icon(PhosphorIconsBold.desktop, size: 18),
                    ),
                     ButtonSegment(
                      value: DatabaseMode.postgres,
                      label: Text(tr('سيرفر (PostgreSQL)')),
                      icon: const Icon(PhosphorIconsBold.cloudArrowUp, size: 18),
                    ),
                  ],
                  selected: {_mode},
                  onSelectionChanged: (s) =>
                      setState(() => _mode = s.first),
                ),
                const SizedBox(height: 16),

                // PostgreSQL config (shown only in postgres mode)
                if (_mode == DatabaseMode.postgres)
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        children: [
                          // Info banner
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppColors.info.withAlpha(20),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                  color: AppColors.info.withAlpha(60)),
                            ),
                            child:  Row(
                              children: [
                                const Icon(PhosphorIconsBold.info,
                                    color: AppColors.info, size: 20),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    tr('يجب أن يكون سيرفر PostgreSQL يعمل ومتاح على الشبكة قبل الاتصال'),
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),

                          // Host & Port
                          Row(
                            children: [
                              Expanded(
                                flex: 3,
                                child: TextField(
                                  controller: _hostCtrl,
                                  decoration:  InputDecoration(
                                    labelText: tr('عنوان السيرفر (Host/IP)'),
                                    hintText: '192.168.1.100',
                                    prefixIcon: const Icon(
                                        PhosphorIconsBold.globe, size: 18),
                                    border: const OutlineInputBorder(),
                                    isDense: true,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: TextField(
                                  controller: _portCtrl,
                                  decoration:  InputDecoration(
                                    labelText: tr('البورت'),
                                    hintText: '5432',
                                    border: const OutlineInputBorder(),
                                    isDense: true,
                                  ),
                                  keyboardType: TextInputType.number,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),

                          // Database name
                          TextField(
                            controller: _dbCtrl,
                            decoration:  InputDecoration(
                              labelText: tr('اسم قاعدة البيانات'),
                              hintText: Brand.pgIdentifier,
                              prefixIcon:
                                  const Icon(PhosphorIconsBold.database, size: 18),
                              border: const OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                          const SizedBox(height: 12),

                          // Username & Password
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _userCtrl,
                                  decoration:  InputDecoration(
                                    labelText: tr('اسم المستخدم'),
                                    hintText: Brand.pgIdentifier,
                                    prefixIcon:
                                        const Icon(PhosphorIconsBold.user, size: 18),
                                    border: const OutlineInputBorder(),
                                    isDense: true,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: TextField(
                                  controller: _passCtrl,
                                  obscureText: true,
                                  decoration:  InputDecoration(
                                    labelText: tr('كلمة المرور'),
                                    prefixIcon:
                                        const Icon(PhosphorIconsBold.lock, size: 18),
                                    border: const OutlineInputBorder(),
                                    isDense: true,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),

                          // SSL toggle
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title:  Text(tr('تفعيل SSL (اتصال مشفر)')),
                            subtitle:  Text(
                              tr('مطلوب للاتصالات عبر الإنترنت'),
                              style: const TextStyle(fontSize: 11),
                            ),
                            secondary: const Icon(PhosphorIconsBold.shieldCheck,
                                color: AppColors.success),
                            value: _useSsl,
                            onChanged: (v) => setState(() => _useSsl = v),
                          ),
                          const SizedBox(height: 12),

                          // Test Connection button
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: _testing ? null : _testConnection,
                              icon: _testing
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2))
                                  : const Icon(PhosphorIconsBold.plugsConnected,
                                      size: 18),
                              label: Text(_testing
                                  ? tr('جاري اختبار الاتصال...')
                                  : tr('اختبار الاتصال')),
                            ),
                          ),

                          // Test result
                          if (_testResult != null) ...[
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: _testResult!.isEmpty
                                    ? AppColors.success.withAlpha(20)
                                    : AppColors.error.withAlpha(20),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: _testResult!.isEmpty
                                      ? AppColors.success
                                      : AppColors.error,
                                  width: 0.5,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    _testResult!.isEmpty
                                        ? PhosphorIconsBold.checkCircle
                                        : PhosphorIconsBold.xCircle,
                                    size: 20,
                                    color: _testResult!.isEmpty
                                        ? AppColors.success
                                        : AppColors.error,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      _testResult!.isEmpty
                                          ? tr('تم الاتصال بنجاح!')
                                          : _testResult!,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: _testResult!.isEmpty
                                            ? AppColors.success
                                            : AppColors.error,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),

                // SQLite mode info
                if (_mode == DatabaseMode.sqlite)
                  Expanded(
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(PhosphorIconsBold.desktop,
                              size: 64,
                              color: AppColors.textSecondary.withAlpha(100)),
                          const SizedBox(height: 16),
                           Text(
                            tr('الوضع المحلي (الافتراضي)'),
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            tr('قاعدة البيانات مخزنة على هذا الجهاز فقط.\nمناسب للعمل بدون سيرفر.'),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontSize: 13,
                                color: AppColors.textSecondary.withAlpha(180)),
                          ),
                        ],
                      ),
                    ),
                  ),

                const SizedBox(height: 16),

                // Actions
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        child:  Text(tr('إلغاء')),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton.icon(
                        onPressed: _saveAndApply,
                        icon:
                            const Icon(PhosphorIconsBold.floppyDisk, size: 18),
                        label:  Text(tr('حفظ وتطبيق')),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
