import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_ar.dart';
import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('ar'),
    Locale('en'),
  ];

  /// No description provided for @treasuryManagement.
  ///
  /// In ar, this message translates to:
  /// **'إدارة الخزينة'**
  String get treasuryManagement;

  /// No description provided for @totalTreasuryBalance.
  ///
  /// In ar, this message translates to:
  /// **'إجمالي رصيد الخزائن'**
  String get totalTreasuryBalance;

  /// No description provided for @receiptVoucher.
  ///
  /// In ar, this message translates to:
  /// **'سند قبض'**
  String get receiptVoucher;

  /// No description provided for @paymentVoucher.
  ///
  /// In ar, this message translates to:
  /// **'سند صرف'**
  String get paymentVoucher;

  /// No description provided for @cashSafes.
  ///
  /// In ar, this message translates to:
  /// **'الخزائن النقدية'**
  String get cashSafes;

  /// No description provided for @bankAccounts.
  ///
  /// In ar, this message translates to:
  /// **'الحسابات البنكية'**
  String get bankAccounts;

  /// No description provided for @dailyClosing.
  ///
  /// In ar, this message translates to:
  /// **'الإقفال اليومي'**
  String get dailyClosing;

  /// No description provided for @noBankAccounts.
  ///
  /// In ar, this message translates to:
  /// **'لا توجد حسابات بنكية'**
  String get noBankAccounts;

  /// No description provided for @recentTransactions.
  ///
  /// In ar, this message translates to:
  /// **'آخر الحركات'**
  String get recentTransactions;

  /// No description provided for @noTransactions.
  ///
  /// In ar, this message translates to:
  /// **'لا توجد حركات'**
  String get noTransactions;

  /// No description provided for @defaultSafe.
  ///
  /// In ar, this message translates to:
  /// **'الخزينة الافتراضية'**
  String get defaultSafe;

  /// No description provided for @cash.
  ///
  /// In ar, this message translates to:
  /// **'نقدي'**
  String get cash;

  /// No description provided for @bank.
  ///
  /// In ar, this message translates to:
  /// **'بنكي'**
  String get bank;

  /// No description provided for @customerPayment.
  ///
  /// In ar, this message translates to:
  /// **'تحصيل من عميل'**
  String get customerPayment;

  /// No description provided for @supplierPayment.
  ///
  /// In ar, this message translates to:
  /// **'سداد لمورد'**
  String get supplierPayment;

  /// No description provided for @sales.
  ///
  /// In ar, this message translates to:
  /// **'مبيعات'**
  String get sales;

  /// No description provided for @purchase.
  ///
  /// In ar, this message translates to:
  /// **'مشتريات'**
  String get purchase;

  /// No description provided for @expense.
  ///
  /// In ar, this message translates to:
  /// **'مصروفات'**
  String get expense;

  /// No description provided for @salary.
  ///
  /// In ar, this message translates to:
  /// **'رواتب'**
  String get salary;

  /// No description provided for @advance.
  ///
  /// In ar, this message translates to:
  /// **'سلفة'**
  String get advance;

  /// No description provided for @loan.
  ///
  /// In ar, this message translates to:
  /// **'قرض'**
  String get loan;

  /// No description provided for @other.
  ///
  /// In ar, this message translates to:
  /// **'أخرى'**
  String get other;

  /// No description provided for @resetBalances.
  ///
  /// In ar, this message translates to:
  /// **'تصفير أرصدة الخزائن وترحيل الأرباح'**
  String get resetBalances;

  /// No description provided for @close.
  ///
  /// In ar, this message translates to:
  /// **'إقفال'**
  String get close;

  /// No description provided for @dailyClosingTitle.
  ///
  /// In ar, this message translates to:
  /// **'إقفال يومي - {safeName}'**
  String dailyClosingTitle(Object safeName);

  /// No description provided for @confirmClosing.
  ///
  /// In ar, this message translates to:
  /// **'هل أنت متأكد من رغبتك في إقفال الخزينة؟'**
  String get confirmClosing;

  /// No description provided for @closingWarning.
  ///
  /// In ar, this message translates to:
  /// **'هذا الإجراء سيقوم بتصفير الرصيد الحالي ({balance} JOD) وبداية فترة جديدة.'**
  String closingWarning(Object balance);

  /// No description provided for @closingNote.
  ///
  /// In ar, this message translates to:
  /// **'ملاحظة: سيتم تسجيل كافة الحركات السابقة في التقارير ولن تُحذف.'**
  String get closingNote;

  /// No description provided for @cancel.
  ///
  /// In ar, this message translates to:
  /// **'إلغاء'**
  String get cancel;

  /// No description provided for @confirmCloseAndReset.
  ///
  /// In ar, this message translates to:
  /// **'إقفال وتصفير الرصيد'**
  String get confirmCloseAndReset;

  /// No description provided for @closingSuccess.
  ///
  /// In ar, this message translates to:
  /// **'تم إقفال الخزينة {safeName} بنجاح'**
  String closingSuccess(Object safeName);

  /// No description provided for @enterValidAmount.
  ///
  /// In ar, this message translates to:
  /// **'يرجى إدخال مبلغ صحيح'**
  String get enterValidAmount;

  /// No description provided for @selectSupplier.
  ///
  /// In ar, this message translates to:
  /// **'يرجى اختيار المورد'**
  String get selectSupplier;

  /// No description provided for @paymentVoucherCreated.
  ///
  /// In ar, this message translates to:
  /// **'تم إنشاء سند الصرف'**
  String get paymentVoucherCreated;

  /// No description provided for @save.
  ///
  /// In ar, this message translates to:
  /// **'حفظ'**
  String get save;

  /// No description provided for @voucherType.
  ///
  /// In ar, this message translates to:
  /// **'نوع السند'**
  String get voucherType;

  /// No description provided for @category.
  ///
  /// In ar, this message translates to:
  /// **'التصنيف'**
  String get category;

  /// No description provided for @amount.
  ///
  /// In ar, this message translates to:
  /// **'المبلغ'**
  String get amount;

  /// No description provided for @description.
  ///
  /// In ar, this message translates to:
  /// **'البيان (اختياري)'**
  String get description;

  /// No description provided for @party.
  ///
  /// In ar, this message translates to:
  /// **'الجهة (عميل/مورد)'**
  String get party;

  /// No description provided for @safe.
  ///
  /// In ar, this message translates to:
  /// **'الخزينة'**
  String get safe;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['ar', 'en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'ar':
      return AppLocalizationsAr();
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
