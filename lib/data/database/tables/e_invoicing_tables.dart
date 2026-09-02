part of '../database.dart';

// ═══════════════════════════════════════════════════════════════════════════
// E-INVOICING TABLES — الفوترة الإلكترونية (ETA + JOFOTARA)
// ═══════════════════════════════════════════════════════════════════════════

/// E-Invoice configuration per platform (ETA Egypt / JOFOTARA Jordan)
@DataClassName('EInvoiceConfigData')
class EInvoiceConfigs extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get platform => text().withLength(max: 20)(); // 'eta', 'jofotara'
  TextColumn get clientId => text().withLength(max: 200)();
  TextColumn get clientSecret => text().withLength(max: 200)();
  TextColumn get registrationNumber =>
      text().withLength(max: 50)(); // الرقم الضريبي
  TextColumn get activityCode =>
      text().nullable().withLength(max: 10)(); // كود النشاط (ETA)
  TextColumn get branchId =>
      text().nullable().withLength(max: 10)(); // فرع (ETA)
  TextColumn get documentVersion =>
      text().withDefault(const Constant('0.9'))(); // '0.9' or '1.0'
  TextColumn get codingSystem =>
      text().withDefault(const Constant('EGS'))(); // GPC, GS1, EGS
  BoolColumn get isProduction => boolean().withDefault(const Constant(false))();
  BoolColumn get isEnabled => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

/// E-Invoice submissions — tracking each invoice sent to ETA/JOFOTARA
@DataClassName('EInvoiceSubmissionData')
@TableIndex(name: 'idx_einv_submissions_sale', columns: {#saleId})
@TableIndex(name: 'idx_einv_submissions_status', columns: {#status})
class EInvoiceSubmissions extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get saleId => integer().references(SalesInvoices, #id)();
  TextColumn get platform => text().withLength(max: 20)(); // 'eta', 'jofotara'
  TextColumn get documentType =>
      text().withDefault(const Constant('invoice'))();
  // Types: invoice, credit_note, debit_note, export_invoice, receipt
  TextColumn get submissionId => text().nullable()(); // ETA submission UUID
  TextColumn get documentUuid => text().nullable()(); // ETA document UUID
  TextColumn get longId => text().nullable()(); // ETA long ID for QR
  TextColumn get internalId => text().nullable()(); // Internal reference
  TextColumn get hashKey => text().nullable()(); // Document hash (integrity)
  TextColumn get status => text().withDefault(const Constant('pending'))();
  // Status: pending, submitted, valid, invalid, rejected, cancelled
  TextColumn get qrCode => text().nullable()(); // QR code data (TLV or URL)
  TextColumn get errorMessage => text().nullable()(); // Last error details
  TextColumn get rawRequest => text().nullable()(); // JSON payload sent
  TextColumn get rawResponse => text().nullable()(); // JSON response received
  IntColumn get retryCount => integer().withDefault(const Constant(0))();
  DateTimeColumn get submittedAt => dateTime().nullable()();
  DateTimeColumn get lastCheckedAt => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  // === v173 — أعمدةُ المزامنة (المرحلة ٤: السجلُّ الرقابيُّ والتشغيلُ العابر) ===
  TextColumn get globalId => text().nullable().unique()(); // UUID for deterministic sync
  DateTimeColumn get lastModifiedAt => dateTime().nullable()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  TextColumn get originClientId => text().nullable()();
  IntColumn get rowVersion => integer().withDefault(const Constant(0))();
}

/// Tax types reference (ETA 20 types: T1-T20)
@DataClassName('TaxTypeData')
class TaxTypes extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get code => text().withLength(max: 5)(); // T1, T2, ... T20
  TextColumn get nameAr =>
      text().withLength(max: 100)(); // ضريبة القيمة المضافة
  TextColumn get nameEn => text().withLength(max: 100)(); // Value Added Tax
  BoolColumn get isPercentage => boolean()(); // true=نسبة, false=مبلغ ثابت
}

/// Tax subtypes reference (e.g., V001-V010 for T1)
@DataClassName('TaxSubtypeData')
class TaxSubtypes extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get code => text().withLength(max: 10)(); // V001, V009, Tbl01
  TextColumn get taxTypeCode => text().withLength(max: 5)(); // T1, T2
  TextColumn get nameAr => text().withLength(max: 100)();
  TextColumn get nameEn => text().withLength(max: 100)();
  RealColumn get rate => real().nullable()(); // النسبة الافتراضية (14% = 14.0)
}

/// F-10: Immutable e-invoice status audit log (Append-Only)
/// Each status change is recorded as a new row — no UPDATE or DELETE allowed.
@DataClassName('EInvoiceStatusLogData')
class EInvoiceStatusLog extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get submissionId => integer().references(EInvoiceSubmissions, #id)();
  TextColumn get oldStatus => text().nullable()();
  TextColumn get newStatus => text()();
  TextColumn get changedBy => text().nullable()(); // user or 'system'
  TextColumn get notes => text().nullable()();
  DateTimeColumn get changedAt => dateTime().withDefault(currentDateAndTime)();
  // === v173 — أعمدةُ المزامنة (المرحلة ٤: السجلُّ الرقابيُّ والتشغيلُ العابر) ===
  TextColumn get globalId => text().nullable().unique()(); // UUID for deterministic sync
  DateTimeColumn get lastModifiedAt => dateTime().nullable()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  TextColumn get originClientId => text().nullable()();
  IntColumn get rowVersion => integer().withDefault(const Constant(0))();
}
