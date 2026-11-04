import 'package:printing/printing.dart' as printing_pkg;
import 'package:flutter/foundation.dart';
import '../data/database/database.dart';
import '../domain/repositories/printers_repository.dart';

/// PrinterResolver - Bridges DB-configured printers with system printers.
///
/// The Printers Management screen saves printer config (name, IP, port, purpose)
/// to the database. This service resolves those configs to actual system printers
/// that the `printing` package can use for direct printing.
class PrinterResolver {
  /// Resolve the configured POS receipt printer.
  /// Returns the matched system printer, or falls back to default/first printer.
  static Future<printing_pkg.Printer?> resolveReceiptPrinter(
    IPrintersRepository printersRepo,
  ) async {
    return resolveByPurpose(printersRepo, 'pos_receipt');
  }

  /// Resolve a printer by its configured purpose (pos_receipt, kitchen, tables, barcode).
  static Future<printing_pkg.Printer?> resolveByPurpose(
    IPrintersRepository printersRepo,
    String purpose,
  ) async {
    try {
      // 1. Get the configured printer from Repository
      final dbPrinter = await printersRepo.getActivePrinterByPurpose(purpose);
      if (dbPrinter == null) {
        debugPrint(
          '[PrinterResolver] No active "$purpose" printer configured in DB',
        );
        return null; // No configured printer → caller will show print dialog
      }

      debugPrint(
        '[PrinterResolver] DB printer: name="${dbPrinter.name}", '
        'type=${dbPrinter.printerType}, port=${dbPrinter.port}, '
        'ip=${dbPrinter.ipAddress}:${dbPrinter.portNumber}',
      );

      // 2. Get all system printers
      final systemPrinters = await printing_pkg.Printing.listPrinters();
      if (systemPrinters.isEmpty) {
        debugPrint('[PrinterResolver] No system printers found at all');
        return null;
      }

      // 3. Try to match by name (exact match first, then contains)
      printing_pkg.Printer? matched;

      // Exact name match
      matched = systemPrinters
          .where((sp) => sp.name.toLowerCase() == dbPrinter.name.toLowerCase())
          .firstOrNull;

      // Partial name match (DB name contained in system name or vice versa)
      matched ??= systemPrinters
          .where(
            (sp) =>
                sp.name.toLowerCase().contains(dbPrinter.name.toLowerCase()) ||
                dbPrinter.name.toLowerCase().contains(sp.name.toLowerCase()),
          )
          .firstOrNull;

      // Match by port name (USB printers often have a port name like "USB001")
      if (matched == null &&
          dbPrinter.port != null &&
          dbPrinter.port!.isNotEmpty) {
        matched = systemPrinters
            .where(
              (sp) =>
                  sp.name.toLowerCase().contains(
                    dbPrinter.port!.toLowerCase(),
                  ) ||
                  sp.url.toLowerCase().contains(dbPrinter.port!.toLowerCase()),
            )
            .firstOrNull;
      }

      // Match by IP address (network printers)
      if (matched == null &&
          dbPrinter.ipAddress != null &&
          dbPrinter.ipAddress!.isNotEmpty) {
        matched = systemPrinters
            .where(
              (sp) =>
                  sp.url.contains(dbPrinter.ipAddress!) ||
                  sp.name.contains(dbPrinter.ipAddress!),
            )
            .firstOrNull;
      }

      if (matched != null) {
        debugPrint(
          '[PrinterResolver] ✅ Matched system printer: "${matched.name}" (url: ${matched.url})',
        );
        return matched;
      }

      // 4. Fallback to system default
      debugPrint(
        '[PrinterResolver] ⚠ No match found for "${dbPrinter.name}", falling back to system default',
      );
      return _getSystemDefault();
    } catch (e) {
      debugPrint('[PrinterResolver] Error resolving printer: $e');
      return _getSystemDefault();
    }
  }

  /// Resolve by a specific database printer entity
  static Future<printing_pkg.Printer?> resolveByPrinter(
    Printer dbPrinter,
  ) async {
    try {
      final systemPrinters = await printing_pkg.Printing.listPrinters();
      if (systemPrinters.isEmpty) return null;

      // Exact name match
      printing_pkg.Printer? matched = systemPrinters
          .where((sp) => sp.name.toLowerCase() == dbPrinter.name.toLowerCase())
          .firstOrNull;

      // Partial name match
      matched ??= systemPrinters
          .where(
            (sp) =>
                sp.name.toLowerCase().contains(dbPrinter.name.toLowerCase()) ||
                dbPrinter.name.toLowerCase().contains(sp.name.toLowerCase()),
          )
          .firstOrNull;

      // A saved USB target is often the Windows queue name while the app's
      // friendly printer name differs (e.g. Microsoft PDF 80mm vs Microsoft
      // Print to PDF). Match that target before refusing the configured route.
      final target = dbPrinter.port?.trim().toLowerCase();
      if (matched == null && target != null && target.isNotEmpty) {
        matched = systemPrinters
            .where(
              (sp) =>
                  sp.name.toLowerCase() == target ||
                  sp.url.toLowerCase() == target ||
                  sp.name.toLowerCase().contains(target) ||
                  sp.url.toLowerCase().contains(target),
            )
            .firstOrNull;
      }

      // Never silently redirect an explicitly selected printer to the system
      // default: callers can report the unresolved configured destination.
      return matched;
    } catch (_) {
      return null;
    }
  }

  /// Get the system default printer, or the first available one.
  static Future<printing_pkg.Printer?> _getSystemDefault() async {
    try {
      final systemPrinters = await printing_pkg.Printing.listPrinters();
      if (systemPrinters.isEmpty) return null;

      // Prefer the one marked as default
      final defaultPrinter = systemPrinters
          .where((p) => p.isDefault)
          .firstOrNull;
      return defaultPrinter ?? systemPrinters.first;
    } catch (e) {
      debugPrint('[PrinterResolver] Error getting system default: $e');
      return null;
    }
  }
}
