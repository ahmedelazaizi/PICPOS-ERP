import 'cash_drawer_service_io.dart'
    if (dart.library.html) 'cash_drawer_service_web.dart';

/// Cash drawer service for opening cash drawers via ESC/POS commands
abstract class CashDrawerService {
  /// Factory constructor that returns platform-specific implementation
  factory CashDrawerService() => createCashDrawerService();

  /// Open the cash drawer connected to the specified port
  /// Windows typically uses COM ports (COM1, COM2, etc.) or LPT ports
  Future<bool> openDrawer({String? printerName});

  /// Check if cash drawer functionality is available on this platform
  bool get isAvailable;
}
