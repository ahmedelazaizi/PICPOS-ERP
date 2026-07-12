import 'package:flutter/foundation.dart';
import 'cash_drawer_service.dart';

/// Factory function for creating web-specific cash drawer service
CashDrawerService createCashDrawerService() => CashDrawerServiceWeb();

/// Web implementation of cash drawer service (not available on web)
class CashDrawerServiceWeb implements CashDrawerService {
  @override
  bool get isAvailable => false;

  @override
  Future<bool> openDrawer({String? printerName}) async {
    // Cash drawer not available on web platform
    debugPrint('Cash drawer is not available on web platform');
    return false;
  }
}
