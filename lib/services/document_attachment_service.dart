// ═══════════════════════════════════════════════════════════════════════════
// E-10: Document Attachment Service
// Attach files (scanned invoices, contracts, delivery notes) to transactions
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path/path.dart' as path;
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:path_provider/path_provider.dart';
import '../core/theme/app_colors.dart';

/// Supported document types
enum DocumentType {
  scannedInvoice,
  receipt,
  contract,
  deliveryNote,
  bankStatement,
  taxDocument,
  warranty,
  other;

  String get labelAr => switch (this) {
    DocumentType.scannedInvoice => 'فاتورة ممسوحة',
    DocumentType.receipt => 'إيصال',
    DocumentType.contract => 'عقد',
    DocumentType.deliveryNote => 'إذن تسليم',
    DocumentType.bankStatement => 'كشف حساب بنكي',
    DocumentType.taxDocument => 'مستند ضريبي',
    DocumentType.warranty => 'شهادة ضمان',
    DocumentType.other => 'أخرى',
  };

  IconData get icon => switch (this) {
    DocumentType.scannedInvoice => PhosphorIconsBold.receipt,
    DocumentType.receipt => PhosphorIconsBold.fileText,
    DocumentType.contract => PhosphorIconsBold.handshake,
    DocumentType.deliveryNote => PhosphorIconsBold.truck,
    DocumentType.bankStatement => PhosphorIconsBold.bank,
    DocumentType.taxDocument => PhosphorIconsBold.stamp,
    DocumentType.warranty => PhosphorIconsBold.shieldCheck,
    DocumentType.other => PhosphorIconsBold.file,
  };
}

/// A single attached document
class AttachedDocument {
  final int id;
  final String entityType; // 'sales_invoice', 'purchase_invoice', 'journal_entry', etc.
  final int entityId;
  final String fileName;
  final String filePath;
  final DocumentType docType;
  final int fileSize; // bytes
  final DateTime attachedAt;
  final int attachedByUserId;
  final String? notes;

  const AttachedDocument({
    required this.id,
    required this.entityType,
    required this.entityId,
    required this.fileName,
    required this.filePath,
    required this.docType,
    required this.fileSize,
    required this.attachedAt,
    required this.attachedByUserId,
    this.notes,
  });

  String get formattedSize {
    if (fileSize < 1024) return '$fileSize B';
    if (fileSize < 1024 * 1024) return '${(fileSize / 1024).toStringAsFixed(1)} KB';
    return '${(fileSize / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String get extension => path.extension(fileName).toLowerCase();

  bool get isImage => ['.jpg', '.jpeg', '.png', '.gif', '.bmp', '.webp'].contains(extension);
  bool get isPdf => extension == '.pdf';
}

/// Service for managing document attachments
class DocumentAttachmentService {
  static const _docDirName = 'documents';
  static const maxFileSizeMB = 25;

  /// Get the storage directory for documents
  static Future<Directory> _getDocDir() async {
    final appDir = await getApplicationDocumentsDirectory();
    final docDir = Directory('${appDir.path}/$_docDirName');
    if (!await docDir.exists()) {
      await docDir.create(recursive: true);
    }
    return docDir;
  }

  /// Attach a file by copying it to the managed storage
  static Future<AttachedDocument?> attachFile({
    required String sourcePath,
    required String entityType,
    required int entityId,
    required DocumentType docType,
    required int userId,
    String? notes,
  }) async {
    final sourceFile = File(sourcePath);
    if (!await sourceFile.exists()) return null;

    final stat = await sourceFile.stat();
    if (stat.size > maxFileSizeMB * 1024 * 1024) return null;

    final docDir = await _getDocDir();
    final targetName = _generateFileName(entityType, entityId, path.basename(sourcePath));
    final targetPath = '${docDir.path}/$targetName';
    await sourceFile.copy(targetPath);

    return AttachedDocument(
      id: DateTime.now().millisecondsSinceEpoch,
      entityType: entityType,
      entityId: entityId,
      fileName: path.basename(sourcePath),
      filePath: targetPath,
      docType: docType,
      fileSize: stat.size,
      attachedAt: DateTime.now(),
      attachedByUserId: userId,
      notes: notes,
    );
  }

  static String _generateFileName(String entityType, int entityId, String original) {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final ext = path.extension(original);
    return '${entityType}_${entityId}_$timestamp$ext';
  }

  /// Delete a document attachment
  static Future<bool> deleteAttachment(AttachedDocument doc) async {
    try {
      final file = File(doc.filePath);
      if (await file.exists()) await file.delete();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Open a document with the system default app
  static Future<void> openDocument(AttachedDocument doc) async {
    if (Platform.isWindows) {
      await Process.run('explorer.exe', [doc.filePath]);
    }
  }
}

/// Widget to display attached documents on any entity
class DocumentAttachmentPanel extends StatelessWidget {
  final List<AttachedDocument> documents;
  final VoidCallback? onAttachNew;
  final ValueChanged<AttachedDocument>? onRemove;
  final ValueChanged<AttachedDocument>? onOpen;

  const DocumentAttachmentPanel({
    super.key,
    required this.documents,
    this.onAttachNew,
    this.onRemove,
    this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(PhosphorIconsBold.paperclip, size: 16, color: AppColors.textMuted),
            const SizedBox(width: 6),
            Text(
              'المستندات المرفقة (${documents.length})',
              style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.w600),
            ),
            const Spacer(),
            if (onAttachNew != null)
              TextButton.icon(
                onPressed: onAttachNew,
                icon: const Icon(PhosphorIconsBold.plus, size: 14),
                label: Text('إرفاق', style: GoogleFonts.cairo(fontSize: 11)),
              ),
          ],
        ),
        if (documents.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'لا توجد مستندات مرفقة',
              style: GoogleFonts.cairo(fontSize: 11, color: AppColors.textMuted),
            ),
          )
        else
          ...documents.map((doc) => _docRow(doc)),
      ],
    );
  }

  Widget _docRow(AttachedDocument doc) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Icon(doc.docType.icon, size: 18, color: AppColors.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(doc.fileName,
                    style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.w500),
                    overflow: TextOverflow.ellipsis),
                Text(
                  '${doc.docType.labelAr} · ${doc.formattedSize}',
                  style: GoogleFonts.cairo(fontSize: 9, color: AppColors.textMuted),
                ),
              ],
            ),
          ),
          if (onOpen != null)
            IconButton(
              icon: const Icon(PhosphorIconsBold.arrowSquareOut, size: 16),
              onPressed: () => onOpen!(doc),
              tooltip: 'فتح',
              iconSize: 16,
            ),
          if (onRemove != null)
            IconButton(
              icon: const Icon(PhosphorIconsBold.trash, size: 16, color: AppColors.error),
              onPressed: () => onRemove!(doc),
              tooltip: 'حذف',
              iconSize: 16,
            ),
        ],
      ),
    );
  }
}
