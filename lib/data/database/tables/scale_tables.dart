part of '../database.dart';

// ═══════════════════════════════════════════════════════════════════════════
// LABEL SCALE TABLES — Multi-scale registry for PLU export
// ═══════════════════════════════════════════════════════════════════════════

/// Registered label printing scales (barcode scales).
/// Each row represents a physical scale device on the network or serial port.
class LabelScales extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(max: 100)(); // "ميزان ديلي"
  TextColumn get brand => text().withDefault(
    const Constant('cas'),
  )(); // cas, digi, aclas, rongta, mettlerToledo, tem, dibal
  TextColumn get connectionType =>
      text().withDefault(const Constant('tcp'))(); // tcp, serial, ftp, file
  TextColumn get ipAddress => text().nullable()(); // 192.168.1.90
  IntColumn get port => integer().withDefault(const Constant(20304))();
  TextColumn get comPort => text().nullable()(); // COM3, COM4, etc.
  IntColumn get baudRate => integer().withDefault(const Constant(9600))();
  IntColumn get dataBits => integer().withDefault(const Constant(8))();
  TextColumn get parity => text().withDefault(
    const Constant('none'),
  )(); // none, odd, even, mark, space
  TextColumn get stopBits => text().withDefault(
    const Constant('one'),
  )(); // none, one, two, onePointFive
  TextColumn get handShake => text().withDefault(
    const Constant('none'),
  )(); // none, xonXoff, requestToSend, requestToSendXonXoff
  IntColumn get maxPlu =>
      integer().withDefault(const Constant(500))(); // Maximum PLU capacity
  TextColumn get ftpUsername =>
      text().nullable()(); // FTP login username (for ftp connection type)
  TextColumn get ftpPassword =>
      text().nullable()(); // FTP login password (for ftp connection type)
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}
