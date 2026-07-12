part of '../activity_logger.dart';

// ═══════════════════════════════════════════════════════════════════════════
// SYSTEM — Navigation, Import/Export, Reports, Print, Bulk, Backup/Restore
// ═══════════════════════════════════════════════════════════════════════════

extension ActivityLoggerSystem on ActivityLogger {
  Future<void> logNavigation(int? userId, String userName, String screenName) {
    return log(userId: userId, userName: userName, action: 'screen_view', entityType: 'navigation',
        description: 'فتح شاشة: $screenName');
  }

  Future<void> logImport(int userId, String userName, String entityType_, int recordCount, {String? fileName}) {
    return log(userId: userId, userName: userName, action: 'import', entityType: entityType_,
        description: 'استيراد $entityType_${fileName != null ? " من $fileName" : ""} ($recordCount سجل)');
  }

  Future<void> logExport(int userId, String userName, String entityType_, String format, {String? fileName}) {
    return log(userId: userId, userName: userName, action: 'export', entityType: entityType_,
        description: 'تصدير $entityType_ بصيغة $format${fileName != null ? " — $fileName" : ""}');
  }

  Future<void> logReportView(int userId, String userName, String reportName) {
    return log(userId: userId, userName: userName, action: 'report_view', entityType: 'report',
        description: 'عرض تقرير: $reportName');
  }

  Future<void> logReportExport(int userId, String userName, String reportName, String format) {
    return log(userId: userId, userName: userName, action: 'report_export', entityType: 'report',
        description: 'تصدير تقرير: $reportName بصيغة $format');
  }

  Future<void> logPrint(int userId, String userName, String documentType, {String? documentId}) {
    return log(userId: userId, userName: userName, action: 'print', entityType: documentType,
        description: 'طباعة $documentType${documentId != null ? " #$documentId" : ""}');
  }

  Future<void> logButtonAction(int userId, String userName, String buttonName, String screenName) {
    return log(userId: userId, userName: userName, action: 'button_click', entityType: 'ui',
        description: 'ضغط زر "$buttonName" في شاشة $screenName');
  }

  Future<void> logBulkAction(int userId, String userName, String actionType, String entityType, int count) {
    return log(userId: userId, userName: userName, action: 'bulk_$actionType', entityType: entityType,
        description: 'عملية جماعية: $actionType على $count سجل من نوع $entityType');
  }

  Future<void> logBackup(int userId, String userName, String backupPath) {
    return log(userId: userId, userName: userName, action: 'backup', entityType: 'system',
        description: 'تم إنشاء نسخة احتياطية: $backupPath');
  }

  Future<void> logRestore(int userId, String userName, String restorePath) {
    return log(userId: userId, userName: userName, action: 'restore', entityType: 'system',
        description: 'تم استعادة قاعدة البيانات من: $restorePath');
  }
}
