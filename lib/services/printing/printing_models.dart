import '../../domain/printing/company_identity.dart';

class InvoiceItem {
  final String name;
  final double quantity;
  final double price;
  final double total;
  final String? barcode;
  final String? note;
  /// Issue 2 (Feature 019): when true, this row represents a category-section
  /// header in a held-order print (the [name] field carries the category
  /// label, e.g. "مأكولات"). The thermal template renders these as
  /// centered, bold dividers and skips qty/price/total columns. Real items
  /// (the default false) render normally.
  final bool isCategoryHeader;

  /// كودُ الصنف والوحدةُ وخصمُ السطر وضريبتُه — أعمدةُ الجدول تسألُ عنها.
  ///
  /// نظيرُ ما في `base_generator.dart` وبالمُهيَّآت نفسِها كي لا يفترق
  /// النموذجان: هذا يخدم مسارَ الطباعة والآخرُ مسارَ المولّدات، والقالبُ
  /// الواحدُ قد يُطبع من كليهما.
  final String? code;
  final String? unit;
  final double discount;
  final double tax;

  InvoiceItem({
    required this.name,
    required this.quantity,
    required this.price,
    required this.total,
    this.barcode,
    this.note,
    this.isCategoryHeader = false,
    this.code,
    this.unit,
    this.discount = 0,
    this.tax = 0,
  });
}

class StatementItem {
  final DateTime date;
  final String description;
  final double debit;
  final double credit;
  final double balance;

  /// رقم المستند في عمود مستقل.
  ///
  /// The screen used to concatenate it into [description] (`"بيان - INV-12"`),
  /// which stretched the widest column and squeezed the numeric ones. Keeping
  /// it separate lets the layout size each column for what it actually holds.
  final String? documentNumber;

  StatementItem({
    required this.date,
    required this.description,
    required this.debit,
    required this.credit,
    required this.balance,
    this.documentNumber,
  });
}

/// بيانات الشركة كما هي مسجّلة في النظام، لرأس المستند وتذييله.
///
/// Reports used to fall back to a hard-coded brand name because the caller
/// never passed the company at all — so a printed supplier statement carried
/// no identity of the business that issued it, and no phone or address for the
/// supplier to reply to. Built from the `company_*` settings the setup wizard
/// already writes and other screens already read.
class DocumentCompanyHeader {
  final String name;
  final String? phone;
  final String? phone2;
  final String? address;
  final String? taxId;

  /// الاسمُ الإنجليزيُّ والسجلُّ التجاريّ — `company_name_en` و
  /// `company_cr_number`. فارغان ⇒ لا يُطبعان (‏`company_identity.dart`).
  final String? nameEn;
  final String? crNumber;

  const DocumentCompanyHeader({
    required this.name,
    this.phone,
    this.phone2,
    this.address,
    this.taxId,
    this.nameEn,
    this.crNumber,
  });

  /// السطرُ الإنجليزيُّ تحت الاسم العربيّ، أو `''`.
  String get secondaryNameLine =>
      companySecondaryName(nameAr: displayName, nameEn: nameEn);

  static const _fallbackName = 'الشركة';

  /// Never blank — a document with no header name reads as a broken print.
  String get displayName => name.trim().isEmpty ? _fallbackName : name.trim();

  List<String> get _contactParts => [
        if ((phone ?? '').trim().isNotEmpty) phone!.trim(),
        if ((phone2 ?? '').trim().isNotEmpty) phone2!.trim(),
        if ((address ?? '').trim().isNotEmpty) address!.trim(),
      ];

  bool get hasContactInfo => _contactParts.isNotEmpty;

  /// Joined with a separator ONLY between present values, so a company with a
  /// phone but no address doesn't print a dangling separator.
  String get contactLine => _contactParts.join('  ·  ');

  String get taxLine {
    final tax = (taxId ?? '').trim().isEmpty
        ? ''
        : 'الرقم الضريبي: ${taxId!.trim()}';
    final cr = companyCrLine(crNumber);
    return [if (tax.isNotEmpty) tax, if (cr.isNotEmpty) cr].join('  ·  ');
  }
}

/// إجماليات كشف الحساب — تُحسب على **كل** الحركات لا على صفحة واحدة.
///
/// The PDF had no totals row at all, while the Excel export from the same
/// screen did. A two-page statement printed with no debit/credit total and no
/// closing balance.
class StatementTotals {
  final double totalDebit;
  final double totalCredit;
  final double closingBalance;

  const StatementTotals({
    required this.totalDebit,
    required this.totalCredit,
    required this.closingBalance,
  });

  factory StatementTotals.from(List<StatementItem> items) {
    var debit = 0.0;
    var credit = 0.0;
    for (final i in items) {
      debit += i.debit;
      credit += i.credit;
    }
    return StatementTotals(
      totalDebit: debit,
      totalCredit: credit,
      // The running balance of the LAST movement — not a sum of balances.
      closingBalance: items.isEmpty ? 0 : items.last.balance,
    );
  }
}

/// قياس أعمدة كشف الحساب حسب المحتوى الفعلي.
///
/// Widths were fixed flex values, so a long description or an 8-digit amount
/// wrapped or clipped. This sizes the columns from what the data actually
/// contains and, when the row is genuinely dense, steps the font down instead
/// of truncating — shrinking text is acceptable, losing figures is not.
class StatementColumnLayout {
  final int dateFlex;
  final int documentFlex;
  final int descriptionFlex;
  final int amountFlex;
  final double fontSize;
  final bool showDocumentColumn;

  const StatementColumnLayout({
    required this.dateFlex,
    required this.documentFlex,
    required this.descriptionFlex,
    required this.amountFlex,
    required this.fontSize,
    required this.showDocumentColumn,
  });

  static const double _baseFontSize = 9.0;

  /// Never below this — past it the print stops being readable, and the right
  /// answer becomes a wider page or fewer columns, not smaller type.
  static const double minFontSize = 6.0;

  factory StatementColumnLayout.forItems(List<StatementItem> items) {
    final hasDoc = items.any((i) => (i.documentNumber ?? '').trim().isNotEmpty);

    var longestDescription = 0;
    var longestDocument = 0;
    var longestAmount = 0;
    for (final i in items) {
      if (i.description.length > longestDescription) {
        longestDescription = i.description.length;
      }
      final doc = (i.documentNumber ?? '').length;
      if (doc > longestDocument) longestDocument = doc;
      for (final v in [i.debit, i.credit, i.balance]) {
        final len = v.toStringAsFixed(2).length;
        if (len > longestAmount) longestAmount = len;
      }
    }

    // Amount columns grow in steps: 2 up to ~7 chars (9999.99), then wider.
    final amountFlex = longestAmount <= 7
        ? 2
        : longestAmount <= 10
            ? 3
            : 4;

    // Description is the only genuinely elastic column, but it must stay ahead
    // of the others so it absorbs slack rather than the numbers being squeezed.
    final descriptionFlex =
        (longestDescription <= 20 ? 3 : longestDescription <= 45 ? 4 : 5)
            .clamp(amountFlex + 1, 6);

    final documentFlex = !hasDoc
        ? 0
        : longestDocument <= 10
            ? 2
            : 3;

    // Total width pressure decides the font step. Each unit over the
    // comfortable budget costs a quarter point, floored at minFontSize.
    final totalFlex =
        2 + documentFlex + descriptionFlex + (amountFlex * 3);
    const comfortable = 12;
    final overflow = (totalFlex - comfortable).clamp(0, 100);
    final fontSize =
        (_baseFontSize - overflow * 0.25).clamp(minFontSize, _baseFontSize);

    return StatementColumnLayout(
      dateFlex: 2,
      documentFlex: documentFlex,
      descriptionFlex: descriptionFlex,
      amountFlex: amountFlex,
      fontSize: fontSize.toDouble(),
      showDocumentColumn: hasDoc,
    );
  }
}
