part of 'app_main_screen.dart';

extension _MainScreenDialogs on _MainScreenState {
  String formatOfflineTime(DateTime start) {
    final diff = DateTime.now().difference(start);
    if (diff.inDays > 0) return tr('{p0} يوم', {'p0': diff.inDays});
    if (diff.inHours > 0) return tr('{p0} ساعة', {'p0': diff.inHours});
    return tr('{p0} دقيقة', {'p0': diff.inMinutes});
  }

  void showSyncDialog(BuildContext context) {
    final syncService = OfflineFallbackSyncService.instance;
    final db = ref.read(databaseProvider);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Directionality(
        textDirection: Directionality.of(context),
        child: _OfflineSyncDialog(
          syncService: syncService,
          localDb: db,
          onDone: () {
            if (mounted) setState(() {});
          },
        ),
      ),
    );
  }
}

class ScreenConfig {
  final AppScreen appScreen;
  final WidgetBuilder _builder;
  final String label;
  final IconData icon;

  /// Lazily-built screen widget (cached after first access)
  Widget? _cachedScreen;

  /// Get screen widget — built on first access, then cached.
  Widget get screen => _cachedScreen ??= Builder(builder: _builder);

  /// Backward-compatible integer index
  int get index => appScreen.value;

  ScreenConfig({
    required this.appScreen,
    required WidgetBuilder builder,
    required this.label,
    required this.icon,
  }) : _builder = builder;
}

/// Dialog that requires admin password to close the app (shown to non-admin users)
class _AdminCloseDialog extends ConsumerStatefulWidget {
  const _AdminCloseDialog();

  @override
  ConsumerState<_AdminCloseDialog> createState() => _AdminCloseDialogState();
}

class _AdminCloseDialogState extends ConsumerState<_AdminCloseDialog> {
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    final input = _passwordController.text.trim();
    if (input.isEmpty) {
      setState(() => _errorMessage = tr('الرجاء إدخال كلمة المرور'));
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Check admin_password (stored as hash)
      if (await ref.read(adminPasswordServiceProvider).verify(input)) {
        if (mounted) Navigator.pop(context, true);
        return;
      }

      // Try authenticating by password or card code
      final db = ref.read(databaseProvider);
      final userWithRole = await db.authenticateByPasswordOrCard(input);
      if (userWithRole != null) {
        final roleName = userWithRole.role?.name.toLowerCase() ?? '';
        final isSystemRole = userWithRole.role?.isSystemRole ?? false;
        final isAdmin =
            isSystemRole ||
            roleName.contains('admin') ||
            roleName.contains('مدير') ||
            roleName.contains('مسؤول') ||
            roleName.contains('manager') ||
            roleName.contains('owner');

        if (isAdmin) {
          if (mounted) Navigator.pop(context, true);
          return;
        } else {
          setState(() {
            _isLoading = false;
            _errorMessage = tr('هذا المستخدم ليس لديه صلاحية إغلاق البرنامج');
          });
          return;
        }
      }

      setState(() {
        _isLoading = false;
        _errorMessage = tr('كلمة المرور غير صحيحة');
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = tr('خطأ: {e}', {'e': e});
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.lock_outline, color: Colors.red, size: 28),
          const SizedBox(width: 12),
          Expanded(child: Text(tr('إغلاق البرنامج يتطلب كلمة مرور المدير'))),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            tr('لا يمكن إغلاق البرنامج إلا بإدخال كلمة مرور مدير النظام.'),
            style: const TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _passwordController,
            obscureText: _obscurePassword,
            autofocus: true,
            textDirection: TextDirection.ltr,
            decoration: InputDecoration(
              labelText: tr('كلمة مرور المدير'),
              prefixIcon: const Icon(Icons.vpn_key),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscurePassword ? Icons.visibility_off : Icons.visibility,
                ),
                onPressed: () =>
                    setState(() => _obscurePassword = !_obscurePassword),
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              errorText: _errorMessage,
            ),
            onSubmitted: (_) => _verify(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(tr('إلغاء')),
        ),
        ElevatedButton(
          onPressed: _isLoading ? null : _verify,
          style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
          child: _isLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Text(tr('إغلاق البرنامج')),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Offline Sync Progress Dialog
// ═══════════════════════════════════════════════════════════════════════════

class _OfflineSyncDialog extends StatefulWidget {
  final OfflineFallbackSyncService syncService;
  final AppDatabase localDb;
  final VoidCallback onDone;

  const _OfflineSyncDialog({
    required this.syncService,
    required this.localDb,
    required this.onDone,
  });

  @override
  State<_OfflineSyncDialog> createState() => _OfflineSyncDialogState();
}

class _OfflineSyncDialogState extends State<_OfflineSyncDialog> {
  bool _started = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _startSync());
  }

  Future<void> _startSync() async {
    if (_started) return;
    _started = true;
    final success = await widget.syncService.syncToPostgres(widget.localDb);
    if (success) {
      widget.onDone();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<SyncProgress>(
      valueListenable: widget.syncService.progress,
      builder: (context, progress, _) {
        final isDone = progress.isDone;
        final hasError = progress.error != null;

        return AlertDialog(
          title: Row(
            children: [
              Icon(
                isDone
                    ? (hasError
                          ? Icons.error_outline
                          : Icons.check_circle_outline)
                    : Icons.sync,
                color: isDone
                    ? (hasError ? Colors.red : Colors.green)
                    : Colors.blue,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  isDone
                      ? (hasError
                            ? tr('فشلت المزامنة')
                            : tr('تمت المزامنة بنجاح'))
                      : tr('جاري المزامنة...'),
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!isDone) ...[
                  LinearProgressIndicator(
                    value: progress.progress,
                    minHeight: 8,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    progress.statusText,
                    style: const TextStyle(fontSize: 14),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    tr('{p0} سجل تم مزامنته', {'p0': progress.rowsSynced}),
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                ],
                if (isDone && !hasError) ...[
                  const Icon(Icons.check_circle, color: Colors.green, size: 48),
                  const SizedBox(height: 12),
                  Text(
                    tr('تم نقل {p0} سجل إلى سيرفر PostgreSQL.', {
                      'p0': progress.rowsSynced,
                    }),
                    style: const TextStyle(fontSize: 14),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    tr(
                      'أعد تشغيل البرنامج للعمل مباشرة على قاعدة بيانات السيرفر.',
                    ),
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.orange.shade800,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
                if (isDone && hasError) ...[
                  const Icon(Icons.error_outline, color: Colors.red, size: 48),
                  const SizedBox(height: 12),
                  Text(
                    progress.error!,
                    style: const TextStyle(fontSize: 13, color: Colors.red),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    tr('تم مزامنة {p0} سجل قبل الخطأ.', {
                      'p0': progress.rowsSynced,
                    }),
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            if (isDone)
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: hasError ? Colors.grey : Colors.green,
                  foregroundColor: Colors.white,
                ),
                child: Text(hasError ? tr('إغلاق') : tr('حسناً')),
              ),
            if (isDone && hasError)
              TextButton(
                onPressed: () {
                  _started = false;
                  _startSync();
                },
                child: Text(tr('إعادة المحاولة')),
              ),
          ],
        );
      },
    );
  }
}
