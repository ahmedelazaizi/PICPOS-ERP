import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/design_system/spacing.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/app_toast.dart';
import '../../data/providers/providers.dart';
import '../../domain/models/attachment_policy.dart';
import 'picpos_dialog.dart';
import 'picpos_empty_state.dart';
import 'picpos_surface.dart';

/// ملفٌّ اختِير — اسمٌ وبايتات. **مُحقَنٌ ليُختبَر**.
typedef PickedAttachment = ({String name, Uint8List bytes});

/// لوحُ مرفقاتِ مستندٍ — **واحدٌ للشاشات التسعِ كلِّها** (§٨، الخطوة هـ).
///
/// ═══ 🔴 ولماذا لوحٌ واحدٌ لا لوحٌ لكلّ شاشة ═══
///
/// لأنّ السياسةَ (سقفُ الحجم · العددُ · الأنواعُ · نصُّ الرفض) لو تكرّرت
/// تسعَ مرّاتٍ لانحرفت في واحدةٍ منها بعد شهر — فتقبل شاشةُ الأصول ملفّاً
/// ترفضه شاشةُ المشتريات، والمستخدمُ لا يفهم لِمَ.
///
/// ═══ ⚠️ واللوحُ يحلّ هُويّةَ المستند بنفسه ═══
///
/// المرفقُ يُربَط بـ`entityGlobalId` لأنّ الرقمَ المحلّيَّ لا يعبر الأجهزة —
/// **ولا واحدٌ من كياناتِ العرض التسعةِ يحمل `globalId`**. فإضافتُه إليها
/// وإلى مُحوِّلاتِها تغييرٌ واسعٌ لأجل حقلٍ واحد، وقراءةٌ واحدةٌ بمفتاحٍ
/// أساسيٍّ تغني عنه. فالشاشةُ تمرّر رقمَها المحلّيَّ، واللوحُ يسأل.
///
/// ومستندٌ لم يَنَل هُويّتَه بعد **يُقال له ذلك صراحةً** — لا يفشل صامتاً
/// ولا يُنتج ورقةً معلَّقةً على رقمٍ يخصُّ مستنداً آخرَ على الخادم.
class PicPosAttachmentsPanel extends ConsumerStatefulWidget {
  const PicPosAttachmentsPanel({
    super.key,
    required this.entityType,
    required this.entityId,
    this.readOnly = false,
    this.pickFile,
    this.attachedByUserId,
  });

  /// من [kAttachmentEntities].
  final String entityType;

  /// رقمُ المستند المحلّيّ. `null` ⇒ لم يُحفَظ بعد.
  final int? entityId;

  /// مستندٌ مرحَّلٌ أو مقفَل — يُعرَض ولا يُعدَّل.
  final bool readOnly;

  /// مُنتقي الملفّات — يُحقَن في الاختبار، والافتراضيُّ `FilePicker`.
  final Future<PickedAttachment?> Function()? pickFile;

  final int? attachedByUserId;

  @override
  ConsumerState<PicPosAttachmentsPanel> createState() =>
      _PicPosAttachmentsPanelState();
}

class _PicPosAttachmentsPanelState
    extends ConsumerState<PicPosAttachmentsPanel> {
  bool _busy = false;

  Future<PickedAttachment?> _pick() async {
    final injected = widget.pickFile;
    if (injected != null) return injected();
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: kAttachmentAllowedExtensions,
      withData: true,
    );
    final files = result?.files ?? const [];
    if (files.isEmpty) return null;
    final file = files.first;
    final bytes = file.bytes;
    if (bytes == null) return null;
    return (name: file.name, bytes: bytes);
  }

  Future<void> _add(String entityGlobalId) async {
    if (_busy) return;
    final picked = await _pick();
    if (picked == null || !mounted) return;

    setState(() => _busy = true);
    try {
      final res = await ref.read(attachmentsRepositoryProvider).addAttachment(
            entityType: widget.entityType,
            entityId: widget.entityId,
            entityGlobalId: entityGlobalId,
            fileName: picked.name,
            bytes: picked.bytes,
            attachedByUserId: widget.attachedByUserId,
          );
      if (!mounted) return;
      if (res.error != null) {
        AppToast.show(context, res.error!, type: ToastType.error);
      } else {
        AppToast.show(context, 'أُرفق «${picked.name}»');
      }
    } catch (e) {
      if (mounted) {
        AppToast.show(context, 'تعذّر الإرفاق: $e', type: ToastType.error);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(AttachmentData row) async {
    final gid = row.globalId;
    if (gid == null || gid.isEmpty) return;
    final ok = await showPicPosConfirm(
      context,
      icon: PhosphorIconsBold.trash,
      title: 'حذفُ مرفق',
      message: 'يُحذَف «${row.fileName}» ولا يعود ملفُّه. '
          'ويبقى في المستند أثرُ أنَّ ورقةً كانت معه.',
      confirmLabel: 'حذف',
      danger: true,
    );
    if (!ok || !mounted) return;

    setState(() => _busy = true);
    try {
      final err =
          await ref.read(attachmentsRepositoryProvider).deleteAttachment(gid);
      if (!mounted) return;
      if (err != null) AppToast.show(context, err, type: ToastType.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _open(AttachmentData row) async {
    setState(() => _busy = true);
    Uint8List? bytes;
    try {
      bytes =
          await ref.read(attachmentsRepositoryProvider).attachmentBytes(row);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (!mounted) return;
    final loaded = bytes;
    if (loaded == null) {
      // ⚠️ **ولا يُقال «المرفقُ تالف»**: الأرجحُ أنّ جلبَه من الخادم تعذّر،
      //    والورقةُ سليمةٌ هناك. ورسالةُ عطبٍ كاذبةٌ تدفع المستخدمَ إلى
      //    إعادةِ رفعِ ما هو مرفوعٌ أصلاً.
      AppToast.show(context, 'تعذّر جلبُ المرفق من الخادم — جرّب ثانيةً',
          type: ToastType.error);
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (_) => _AttachmentPreview(row: row, bytes: loaded),
    );
  }

  Widget _notice(String text, {required Key key}) => Container(
        key: key,
        padding: const EdgeInsets.all(Spacing.md),
        decoration: BoxDecoration(
          color: context.picposField,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: context.picposHairline),
        ),
        child: Text(
          text,
          style:
              const TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
      );

  Widget _header(int count, {VoidCallback? onAdd}) => Row(
        children: [
          const Icon(PhosphorIconsBold.paperclip,
              size: 16, color: AppColors.textSecondary),
          const SizedBox(width: Spacing.xs),
          Text(
            'المرفقات ($count/$kAttachmentMaxPerDocument)',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.textSecondary,
            ),
          ),
          const Spacer(),
          TextButton.icon(
            key: const Key('attachments_add'),
            onPressed: onAdd,
            icon: const Icon(PhosphorIconsBold.plus, size: 14),
            label: const Text('إضافة'),
          ),
        ],
      );

  Widget _shell(List<Widget> children) => Column(
        key: const Key('attachments_panel'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: children,
      );

  @override
  Widget build(BuildContext context) {
    final entity = attachmentEntityFor(widget.entityType);
    final label = entity?.labelAr ?? 'المستند';
    final id = widget.entityId;

    if (entity == null) {
      return _shell([
        _header(0),
        const SizedBox(height: Spacing.xs),
        _notice('نوعُ مستندٍ لا يقبل المرفقات: ${widget.entityType}',
            key: const Key('attachments_unsupported')),
      ]);
    }

    if (id == null) {
      return _shell([
        _header(0),
        const SizedBox(height: Spacing.xs),
        _notice('احفظ $label أوّلاً — المرفقُ يُربَط بهُويّته لا برقمه '
            'على هذا الجهاز.', key: const Key('attachments_locked')),
      ]);
    }

    final anchor = ref.watch(
        attachmentAnchorProvider((entityType: widget.entityType, entityId: id)));

    return anchor.when(
      loading: () => _shell([
        _header(0),
        const SizedBox(height: Spacing.xs),
        const Padding(
          key: Key('attachments_resolving'),
          padding: EdgeInsets.symmetric(vertical: Spacing.md),
          child: Center(
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ),
      ]),
      error: (e, _) => _shell([
        _header(0),
        const SizedBox(height: Spacing.xs),
        _notice('تعذّرت قراءةُ هُويّة $label: $e',
            key: const Key('attachments_anchor_error')),
      ]),
      data: (gid) {
        if (gid == null) {
          return _shell([
            _header(0),
            const SizedBox(height: Spacing.xs),
            _notice(
                'لم يَنَل $label هُويّتَه العالميّةَ بعد — يُرفَق بعد أوّل '
                'مزامنةٍ أو إعادةِ حفظ.',
                key: const Key('attachments_locked')),
          ]);
        }

        final async = ref.watch(attachmentsStreamProvider((
          entityType: widget.entityType,
          entityId: id,
          entityGlobalId: gid,
        )));
        final rows = async.asData?.value ?? const <AttachmentData>[];
        final canAdd = !widget.readOnly &&
            !_busy &&
            rows.length < kAttachmentMaxPerDocument;

        return _shell([
          _header(rows.length, onAdd: canAdd ? () => _add(gid) : null),
          const SizedBox(height: Spacing.xs),
          if (rows.isEmpty)
            const Padding(
              key: Key('attachments_empty'),
              padding: EdgeInsets.symmetric(vertical: Spacing.md),
              child: PicPosEmptyState(
                icon: PhosphorIconsBold.paperclip,
                title: 'لا مرفقاتٍ بعد',
                hint: 'صورٌ أو ملفّاتُ PDF حتّى ٥ م.ب للملفّ.',
              ),
            )
          else
            ...rows.map((r) => _AttachmentTile(
                  row: r,
                  readOnly: widget.readOnly,
                  busy: _busy,
                  onOpen: () => _open(r),
                  onDelete: () => _delete(r),
                )),
        ]);
      },
    );
  }
}

class _AttachmentTile extends StatelessWidget {
  const _AttachmentTile({
    required this.row,
    required this.readOnly,
    required this.busy,
    required this.onOpen,
    required this.onDelete,
  });

  final AttachmentData row;
  final bool readOnly;
  final bool busy;
  final VoidCallback onOpen;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final gid = row.globalId ?? '${row.id}';
    final docType = AttachmentDocType.fromCode(row.docType);
    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.xs),
      child: Material(
        color: context.picposField,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          key: Key('attachment_tile_$gid'),
          onTap: busy ? null : onOpen,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: Spacing.md, vertical: Spacing.sm),
            child: Row(
              children: [
                Icon(
                  isAttachmentPdf(row.mimeType)
                      ? PhosphorIconsBold.filePdf
                      : PhosphorIconsBold.image,
                  size: 18,
                  color: AppColors.textSecondary,
                ),
                const SizedBox(width: Spacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        row.fileName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                      Text(
                        '${docType.labelAr} · '
                        '${formatAttachmentSize(row.byteSize)}',
                        style: const TextStyle(
                            fontSize: 11, color: AppColors.textMuted),
                      ),
                    ],
                  ),
                ),
                if (!readOnly)
                  IconButton(
                    key: Key('attachment_delete_$gid'),
                    onPressed: busy ? null : onDelete,
                    icon: const Icon(PhosphorIconsBold.trash,
                        size: 16, color: AppColors.error),
                    tooltip: 'حذف',
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// عرضُ المرفق — صورةٌ داخلَ الحوار، وPDF بطاقةُ وصف.
class _AttachmentPreview extends StatelessWidget {
  const _AttachmentPreview({required this.row, required this.bytes});

  final AttachmentData row;
  final Uint8List bytes;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      key: const Key('attachment_preview'),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 640),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(Spacing.md),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      row.fileName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w700),
                    ),
                  ),
                  IconButton(
                    key: const Key('attachment_preview_close'),
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(PhosphorIconsBold.x, size: 16),
                  ),
                ],
              ),
            ),
            Flexible(
              child: isAttachmentImage(row.mimeType)
                  ? InteractiveViewer(
                      child: Image.memory(bytes, fit: BoxFit.contain),
                    )
                  : Padding(
                      padding: const EdgeInsets.all(Spacing.xl),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(PhosphorIconsBold.filePdf,
                              size: 48, color: AppColors.textMuted),
                          const SizedBox(height: Spacing.md),
                          Text(
                            '${formatAttachmentSize(row.byteSize)} · PDF',
                            style: const TextStyle(
                                fontSize: 12, color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
