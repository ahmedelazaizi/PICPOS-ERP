part of 'picpos_pos_screen.dart';

/// Cash drawer opening.
extension _PicPosDrawerOps on _PicPosOperations {
  /// Drawer printer resolution mirrors the UralCash screen: a drawer-specific
  /// printer wins, then the receipt printer, then the OS default. Tills often
  /// have the drawer wired to the receipt printer's kick port, so the fallback
  /// is the common case rather than an error path.
  Future<String> _drawerPrinterName() async {
    try {
      final settings = ref.read(settingsRepositoryProvider);
      final drawer = await settings.getSetting('cash_drawer_printer');
      if (drawer != null && drawer.isNotEmpty) return drawer;
      final receipt = await settings.getSetting('receipt_printer');
      return receipt ?? 'Default';
    } catch (_) {
      return 'Default';
    }
  }

  /// زر `الدرج` الصريح — الكاشير طلب الفتح، ففشله لازم يقول.
  Future<void> _openDrawer() async {
    // الفتحُ اليدويُّ يفتح الدرجَ **بلا بيعة** — وهو ما يُراقَب. والركلةُ
    // التلقائيةُ على مسار الدفع (`_openCashDrawerQuietly`) لا تُحرَس عن قصد:
    // جزءٌ من إتمام بيعةٍ مأذونةٍ سلفاً، وحراستُها توقف الكاشيرَ في منتصف كلّ
    // فاتورة.
    if (!await ensureOpenCashDrawerPermission(ref, context)) return;
    if (!mounted) return;
    try {
      await CashDrawerService()
          .openDrawer(printerName: await _drawerPrinterName());
      final user = ref.read(authProvider).user;
      await ref.read(activityLoggerProvider).logCashDrawerOpen(
            user?.id ?? 0,
            user?.displayName ?? tr('مستخدم'),
          );
    } catch (e) {
      if (mounted) {
        showPosToast(context, ref, tr('تعذّر فتح الدرج: {e}', {'e': e}),
            type: PosNotificationType.error);
      }
    }
    _refocusScanner();
  }

  /// الركلة الصامتة على مسار `دفع`.
  ///
  /// ── ليه صامتة ────────────────────────────────────────────────────────────
  /// الفاتورة اتحصّلت واتطبعت خلاص. توست أحمر عن الدرج على تِل مالوش درج أصلاً
  /// (وده تركيب شائع) كان معناه تحذير مع **كل** بيعة، والكاشير بيتعلّم يتجاهل
  /// التوستات كلها — بما فيها اللي بتقول إن الطباعة فشلت. الفشل بيتسجّل في
  /// `debugPrint` وخلاص. زر `الدرج` الصريح فوق هو اللي بيبلّغ.
  Future<void> _openCashDrawerQuietly() async {
    try {
      await CashDrawerService()
          .openDrawer(printerName: await _drawerPrinterName());
    } catch (e) {
      debugPrint('[PicPos-Drawer] فشل تشغيل الدرج: $e');
    }
  }
}
