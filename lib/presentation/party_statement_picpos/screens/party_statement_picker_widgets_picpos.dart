part of 'party_statement_picpos_screen.dart';

/// منتقي الفرع في شريط المرشِّحات — «جميع الفروع» ثمّ فروعُ المستخدم.
///
/// ⚠️ **قائمتُه `userAccessibleBranchesProvider` لا كلُّ الفروع**: مرشِّحٌ
/// يعرض أسماءَ فروعٍ لا يصلها المستخدمُ يسرّب بنيةَ الشركة، ويَعِد بأرقامٍ
/// يردّها الاستعلامُ فارغةً بلا سبب.
///
/// ⚠️ **ولا يظهر أصلاً إن كان للتجهيزة فرعٌ واحد**: اختيارٌ من واحدٍ ليس
/// اختياراً، وزرٌّ لا يغيّر شيئاً ضجيج.
class _BranchPickerButton extends ConsumerWidget {
  const _BranchPickerButton({
    required this.selectedId,
    required this.onChanged,
  });

  final int? selectedId;
  final void Function(int?) onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final branches =
        ref.watch(userAccessibleBranchesProvider).asData?.value ??
        const <Branche>[];
    if (branches.length < 2) return const SizedBox.shrink();

    final match = branches.where((b) => b.id == selectedId);
    final label = match.isEmpty ? tr('جميع الفروع') : match.first.name;
    final on = selectedId != null;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(11),
        onTap: () async {
          final picked = await showMenu<int>(
            context: context,
            position: _menuPosition(context),
            items: [
              PopupMenuItem<int>(value: -1, child: Text(tr('جميع الفروع'))),
              for (final b in branches)
                PopupMenuItem<int>(value: b.id, child: Text(b.name)),
            ],
          );
          if (picked == null) return;
          onChanged(picked == -1 ? null : picked);
        },
        child: Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 13),
          decoration: BoxDecoration(
            color: on
                ? AppColors.primary.withValues(alpha: .08)
                : context.picposField,
            borderRadius: BorderRadius.circular(11),
            border: Border.all(
              color: on ? AppColors.primary : context.picposHairline,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                PhosphorIconsBold.buildings,
                size: 15,
                color: on ? AppColors.primary : context.picposMuted,
              ),
              const SizedBox(width: 7),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: on ? context.picposBrandInk : context.picposText,
                ),
              ),
              const SizedBox(width: 5),
              Icon(
                PhosphorIconsBold.caretDown,
                size: 12,
                color: context.picposMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }

  RelativeRect _menuPosition(BuildContext context) {
    final box = context.findRenderObject() as RenderBox?;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (box == null || overlay == null) {
      return const RelativeRect.fromLTRB(0, 0, 0, 0);
    }
    final topLeft = box.localToGlobal(Offset.zero, ancestor: overlay);
    return RelativeRect.fromLTRB(
      topLeft.dx,
      topLeft.dy + box.size.height,
      overlay.size.width - topLeft.dx - box.size.width,
      0,
    );
  }
}

/// «تخصيص الأعمدة» — أيُّ أعمدةِ الكشف تُعرَض.
///
/// ⚠️ **وعمودُ التاريخ لا يُطفأ**: سطرُ كشفٍ بلا تاريخٍ لا يُقرأ ولا يُرتَّب،
/// و«تخصيصٌ» يسمح بإخفائه ليس خياراً بل بابُ كشفٍ لا معنى له.
///
/// ⚠️ **وعمودٌ واحدٌ على الأقلّ غيرُ التاريخ**: جدولٌ بعمودٍ واحدٍ ليس جدولاً،
/// والزرُّ يُعطَّل عند الحدّ بدل أن يُقبَل الاختيارُ ثمّ يُصحَّح صامتاً.
class _ColumnPickerDialog extends StatefulWidget {
  const _ColumnPickerDialog({required this.visible});

  final Set<String> visible;

  @override
  State<_ColumnPickerDialog> createState() => _ColumnPickerDialogState();
}

class _ColumnPickerDialogState extends State<_ColumnPickerDialog> {
  late Set<String> _sel = {...widget.visible};

  @override
  Widget build(BuildContext context) {
    final optional = _sel.where((c) => c != kStatementColumnDate).length;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        backgroundColor: context.picposCard,
        title: Text(
          tr('تخصيص الأعمدة'),
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: context.picposText,
          ),
        ),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final c in kStatementColumnCatalogue)
                CheckboxListTile(
                  dense: true,
                  value: _sel.contains(c.id),
                  title: Text(
                    c.label,
                    style: TextStyle(fontSize: 13, color: context.picposText),
                  ),
                  subtitle: c.id == kStatementColumnDate
                      ? Text(
                          tr('ثابتٌ — لا يُخفى'),
                          style: TextStyle(
                            fontSize: 11,
                            color: context.picposMuted,
                          ),
                        )
                      : null,
                  onChanged: c.id == kStatementColumnDate
                      ? null
                      : (v) => setState(() {
                          if (v == true) {
                            _sel.add(c.id);
                          } else if (optional > 1) {
                            _sel.remove(c.id);
                          }
                        }),
                ),
              const SizedBox(height: 6),
              Text(
                tr('يُحفَظ لك وحدَك على هذا النظام.'),
                style: TextStyle(fontSize: 11, color: context.picposMuted),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () =>
                setState(() => _sel = {...kDefaultStatementColumns}),
            child: Text(tr('إعادة ضبط')),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(tr('إلغاء')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(_sel),
            child: Text(tr('تطبيق')),
          ),
        ],
      ),
    );
  }
}
