// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get treasuryManagement => 'Treasury Management';

  @override
  String get totalTreasuryBalance => 'Total Treasury Balance';

  @override
  String get receiptVoucher => 'Receipt Voucher';

  @override
  String get paymentVoucher => 'Payment Voucher';

  @override
  String get cashSafes => 'Cash Safes';

  @override
  String get bankAccounts => 'Bank Accounts';

  @override
  String get dailyClosing => 'Daily Closing';

  @override
  String get noBankAccounts => 'No bank accounts found';

  @override
  String get recentTransactions => 'Recent Transactions';

  @override
  String get noTransactions => 'No transactions found';

  @override
  String get defaultSafe => 'Default Safe';

  @override
  String get cash => 'Cash';

  @override
  String get bank => 'Bank';

  @override
  String get customerPayment => 'Customer Payment';

  @override
  String get supplierPayment => 'Supplier Payment';

  @override
  String get sales => 'Sales';

  @override
  String get purchase => 'Purchases';

  @override
  String get expense => 'Expenses';

  @override
  String get salary => 'Salaries';

  @override
  String get advance => 'Advance';

  @override
  String get loan => 'Loan';

  @override
  String get other => 'Other';

  @override
  String get resetBalances => 'Reset balances and transfer profits';

  @override
  String get close => 'Close';

  @override
  String dailyClosingTitle(Object safeName) {
    return 'Daily Closing - $safeName';
  }

  @override
  String get confirmClosing => 'Are you sure you want to close this safe?';

  @override
  String closingWarning(Object balance) {
    return 'This action will reset the current balance ($balance EGP) and start a new period.';
  }

  @override
  String get closingNote =>
      'Note: All previous transactions will be recorded in reports and will not be deleted.';

  @override
  String get cancel => 'Cancel';

  @override
  String get confirmCloseAndReset => 'Close and Reset Balance';

  @override
  String closingSuccess(Object safeName) {
    return 'Safe $safeName closed successfully';
  }

  @override
  String get enterValidAmount => 'Please enter a valid amount';

  @override
  String get selectSupplier => 'Please select a supplier';

  @override
  String get paymentVoucherCreated => 'Payment voucher created successfully';

  @override
  String get save => 'Save';

  @override
  String get voucherType => 'Voucher Type';

  @override
  String get category => 'Category';

  @override
  String get amount => 'Amount';

  @override
  String get description => 'Description (Optional)';

  @override
  String get party => 'Party (Customer/Supplier)';

  @override
  String get safe => 'Safe';
}
