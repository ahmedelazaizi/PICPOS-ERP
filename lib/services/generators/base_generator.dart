import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

/// Base class for all generators with shared font initialization
abstract class BaseGenerator {
  static pw.Font? _arabicFont;

  /// Initialize Arabic font — local bundled asset first, Google Fonts fallback.
  /// IMPORTANT: Only cache successful Cairo loads — never cache Helvetica fallback,
  /// so the next print retries instead of permanently using a non-Arabic font.
  static Future<pw.Font> initFont() async {
    if (_arabicFont != null) return _arabicFont!;

    // ① Load from bundled asset (works offline on POS machines)
    try {
      final fontData = await rootBundle.load('assets/fonts/Cairo-Regular.ttf');
      _arabicFont = pw.Font.ttf(fontData);
      debugPrint('[Font] Loaded Cairo from bundled asset ✓');
      return _arabicFont!;
    } catch (e) {
      debugPrint('[Font] Bundled asset failed: $e');
    }

    // ② Fallback: download from Google Fonts (requires internet)
    try {
      _arabicFont = await PdfGoogleFonts.cairoRegular();
      debugPrint('[Font] Loaded Cairo from Google Fonts ✓');
      return _arabicFont!;
    } catch (e) {
      debugPrint('[Font] Google Fonts failed: $e');
    }

    // ③ Last resort: Helvetica — returned but NOT cached so next call retries
    debugPrint('[Font] WARNING: All Arabic font sources failed — Arabic text will show as boxes. '
        'Ensure assets/fonts/Cairo-Regular.ttf is bundled correctly.');
    return pw.Font.helvetica();
  }
}

/// Invoice item model for generators
class InvoiceItem {
  final String name;
  final double quantity;
  final double price;
  final double total;
  final String? note;

  InvoiceItem({
    required this.name,
    required this.quantity,
    required this.price,
    required this.total,
    this.note,
  });
}

/// Statement item model for party statements
class StatementItem {
  final DateTime date;
  final String description;
  final double debit;
  final double credit;
  final double balance;

  StatementItem({
    required this.date,
    required this.description,
    required this.debit,
    required this.credit,
    required this.balance,
  });
}
