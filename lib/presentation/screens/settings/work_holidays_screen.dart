import 'package:ural_erp/core/i18n/tr.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'dart:ui' as ui;
import '../../../core/config/brand.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../data/providers/providers.dart';
import '../../picpos_shell/picpos_body_handle.dart';
import '../../picpos_shell/picpos_dialog.dart';
import '../../picpos_shell/picpos_panel_groups.dart';
import '../../widgets/dialogs/app_confirm_dialog.dart';

/// أسماءُ أيام الأسبوع باصطلاح `DateTime.weekday` (‏١ = الاثنين … ٧ = الأحد).
/// الفهرسُ صفرٌ غيرُ مستعمَل — يبدأ العدُّ من ١ فيتّسق الفهرسُ مع القيمة.
List<String> get _kWeekdayNames => [
  '',
  tr('الاثنين'),
  tr('الثلاثاء'),
  tr('الأربعاء'),
  tr('الخميس'),
  tr('الجمعة'),
  tr('السبت'),
  tr('الأحد'),
];

/// شاشةُ تعريف عطلات العمل — أساسُ حساب أيام العمل الفعلية شهرياً
/// (‏`AppDatabase.workingDaysInMonth`) الذي عليه يقوم أجرُ الساعة والوقتُ
/// الإضافي المحسوب. العطلةُ إمّا يومٌ أسبوعيٌّ متكرّر وإمّا تاريخٌ بعينه،
/// ومحصورةٌ بفرعٍ أو عامّةٌ لكل الفروع (‏`branchId == null`).
class WorkHolidaysScreen extends StatefulWidget {
  const WorkHolidaysScreen({super.key});

  @override
  State<WorkHolidaysScreen> createState() => _WorkHolidaysScreenState();
}

class _WorkHolidaysScreenState extends State<WorkHolidaysScreen> {
  /// تُملَك هنا لا في `build`: وصلةٌ تُبنى مع كلِّ إطارٍ تترك الجسمَ مسجَّلاً
  /// على وصلةٍ متروكة، فيموت زرُّ الـ`AppBar` بعد أوّلِ إعادةِ بناء.
  final _addHandle = PicPosBodyHandle();

  @override
  void dispose() {
    _addHandle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final handle = _addHandle;
    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title:  Text(tr('عطلات العمل')),
          actions: [
            IconButton(
              icon: const Icon(PhosphorIconsBold.plus),
              tooltip: tr('إضافة عطلة'),
              onPressed: handle.invoke,
            ),
          ],
        ),
        body: WorkHolidaysBody(addHandle: handle),
      ),
    );
  }
}

/// جسمُ شاشة العطلات بلا قشرة (‏بلا `Scaffold`/`AppBar`/`Directionality`).
///
/// استُخرج ليركب عليه إطارُ العلامتَين معاً بلا نسخِ منطق: `WorkHolidaysScreen`
/// أعلاه (‏قشرةُ UralCash — حرفاً بحرفٍ ما كانت عليه) و
/// `WorkHolidaysPicposScreen` (‏قشرةُ PicPos: `PicPosScreenScaffold`).
/// فلا تنطبق «مصيدةُ النسخ §٥.٨»: لا نسخةَ ثانيةً تُصان، وشاشةُ UralCash لم
/// يتبدّل فيها بايت.
///
/// [addHandle] تسجّل فيه الحالةُ إجراءَ «إضافة عطلة» ليبلغه زرُّ القشرة.
/// [searchQuery] ترشيحٌ اختياريٌّ بالاسم/الوصف/الفرع؛ فارغاً لا يُرشِّح شيئاً.
class WorkHolidaysBody extends ConsumerStatefulWidget {
  final PicPosBodyHandle? addHandle;
  final String searchQuery;

  const WorkHolidaysBody({super.key, this.addHandle, this.searchQuery = ''});

  @override
  ConsumerState<WorkHolidaysBody> createState() => _WorkHolidaysBodyState();
}

class _WorkHolidaysBodyState extends ConsumerState<WorkHolidaysBody> {
  List<WorkHoliday> _holidays = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    widget.addHandle?.register(_showAddDialog);
    _load();
  }

  @override
  void dispose() {
    widget.addHandle?.register(null);
    super.dispose();
  }

  /// H6 — نطاقُ الفروع يُحلّ مرّةً واحدةً هنا (مطابقٌ لـ`hrEmployeesProvider`)
  /// و`hasFullAccess` يُترجَم إلى `null` فلا يُفلتَر شيء.
  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final scope = await ref.read(branchScopeProvider.future);
      final repo = ref.read(hrRepositoryProvider);
      final holidays = await repo.getWorkHolidays(
        allowedBranchIds: scope.hasFullAccess ? null : scope.allowedBranchIds,
      );
      if (mounted) {
        setState(() {
          _holidays = holidays;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        AppToast.show(context, tr('خطأ في تحميل العطلات: {e}', {'e': e}),
            type: ToastType.error);
      }
    }
  }

  Future<void> _delete(WorkHoliday holiday) async {
    final confirmed = await AppConfirmDialog.show(
      context,
      title: tr('حذف عطلة'),
      message: tr('هل أنت متأكد من حذف "{p0}"؟', {'p0': holiday.name}),
      confirmLabel: tr('حذف'),
      color: AppColors.error,
      icon: PhosphorIconsBold.trash,
    );

    if (confirmed != true) return;
    try {
      final repo = ref.read(hrRepositoryProvider);
      await repo.deleteWorkHoliday(holiday.id);
      _load();
    } catch (e) {
      if (mounted) {
        AppToast.show(context, tr('خطأ في الحذف: {e}', {'e': e}), type: ToastType.error);
      }
    }
  }

  Future<void> _showAddDialog() async {
    final scope = ref.read(branchScopeProvider).value;
    final allBranches = ref.read(allBranchesProvider).value ?? const [];
    final visibleBranches = (scope == null || scope.hasFullAccess)
        ? allBranches
        : allBranches.where((b) => scope.isAllowed(b.id)).toList();

    final nameCtrl = TextEditingController();
    bool isWeekday = true;
    int weekday = DateTime.friday;
    DateTime date = DateTime.now();
    int? branchId;

    // ═══ لوحةُ `PANELS.holiday` بغلاف PicPos ═══
    //
    // ⚠️ **خروجٌ مبكّرٌ لا تفريعٌ داخل الشجرة**: حوارُ UralCash تحت هذا
    //    السطرِ لا يُمَسّ حرفاً — والشرطُ الذي يجعل النقلَ مشروعاً أنّ الفرعَ
    //    الآخرَ لا يتبدّل فيه بايت.
    //
    // ⚠️ **ونصفُ مجموعات التصميم لم تُنقَل لأنّ الجدولَ لا يحملها**: «النوع»
    //    (رسميّةٌ مدفوعة …) و«من/إلى تاريخ» و«سلوك النظام في العطلة» (منعُ
    //    فتح ورديّاتٍ · حسابُ الحضور إضافيّاً · تكرارٌ سنويّ) — وصفُّ
    //    `work_holidays` اسمٌ، ويومُ أسبوعٍ **أو** تاريخٌ واحد، وفرعٌ اختياريّ.
    //    ومجموعةٌ لا يقرأها الحفظُ وعدٌ كاذب.
    if (Brand.isPicPos) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (dialogCtx) => StatefulBuilder(
          builder: (ctx, setDialogState) {
            final groups = <PicPosPanelGroup>[
              PicPosPanelGroup(
                label: tr('بيانات العطلة'),
                child: TextField(
                  controller: nameCtrl,
                  autofocus: true,
                  decoration:  InputDecoration(
                    labelText: tr('اسم العطلة'),
                    hintText: tr('مثال: عيد الفطر'),
                    prefixIcon: const Icon(PhosphorIconsLight.calendarStar),
                  ),
                ),
              ),
              PicPosPanelGroup(
                label: tr('التكرار'),
                hint: tr('يومٌ أسبوعيٌّ يتكرّر، أو تاريخٌ واحد'),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    PicPosPanelChips(children: [
                      PicPosPanelChip(
                        label: tr('يومٌ أسبوعيٌّ متكرّر'),
                        selected: isWeekday,
                        onTap: () => setDialogState(() => isWeekday = true),
                      ),
                      PicPosPanelChip(
                        label: tr('تاريخٌ محدَّد'),
                        selected: !isWeekday,
                        onTap: () => setDialogState(() => isWeekday = false),
                      ),
                    ]),
                    const SizedBox(height: 12),
                    if (isWeekday)
                      PicPosPanelChips(children: [
                        for (var d = 1; d <= 7; d++)
                          PicPosPanelChip(
                            label: _kWeekdayNames[d],
                            selected: weekday == d,
                            onTap: () => setDialogState(() => weekday = d),
                          ),
                      ])
                    else
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: OutlinedButton.icon(
                          icon: const Icon(PhosphorIconsBold.calendar),
                          label: Text(
                            DateFormat('yyyy/MM/dd', uiLocaleCode).format(date),
                          ),
                          onPressed: () async {
                            final picked = await showDatePicker(
                              context: ctx,
                              initialDate: date,
                              firstDate: DateTime(2000),
                              lastDate: DateTime(2100),
                            );
                            if (picked != null) {
                              setDialogState(() => date = picked);
                            }
                          },
                        ),
                      ),
                  ],
                ),
              ),
              PicPosPanelGroup(
                label: tr('الفرع المتأثّر'),
                hint: tr('فرعٌ واحدٌ أو كلُّ الفروع'),
                child: PicPosPanelChips(children: [
                  PicPosPanelChip(
                    label: tr('كل الفروع'),
                    selected: branchId == null,
                    onTap: () => setDialogState(() => branchId = null),
                  ),
                  for (final b in visibleBranches)
                    PicPosPanelChip(
                      label: b.name,
                      selected: branchId == b.id,
                      onTap: () => setDialogState(() => branchId = b.id),
                    ),
                ]),
              ),
            ];

            return PicPosDialog(
              icon: PhosphorIconsBold.calendarPlus,
              title: tr('إضافة عطلة'),
              // ⚠️ وصفُ التصميم «يُغلق البيع في هذه المدة ويُحسب الأجر حسب
              //    النوع» لم يُنقَل: العطلةُ تُقرأ من `holidaysInMonth` في
              //    حساب الرواتب، ولا يمنع البيعَ شيءٌ بسببها.
              subtitle: tr('يومُ العطلة يُستثنى من حسم الغياب في حساب الرواتب'),
              width: 660,
              onCancel: () => Navigator.pop(dialogCtx, false),
              primaryAction: PicPosDialogAction(
                label: tr('إضافة العطلة'),
                icon: PhosphorIconsBold.check,
                onPressed: () async {
                  if (nameCtrl.text.trim().isEmpty) return;
                  try {
                    final repo = ref.read(hrRepositoryProvider);
                    await repo.addWorkHoliday(
                      name: nameCtrl.text,
                      weekday: isWeekday ? weekday : null,
                      date: isWeekday ? null : date,
                      branchId: branchId,
                    );
                    if (dialogCtx.mounted) Navigator.pop(dialogCtx, true);
                  } catch (e) {
                    // ArgumentError من `addWorkHoliday` — يُعرَض لا يُبتلَع.
                    if (dialogCtx.mounted) {
                      AppToast.show(dialogCtx, '$e', type: ToastType.error);
                    }
                  }
                },
              ),
              indexLabels: picposPanelLabels(groups),
              body: picposPanelBody(groups),
            );
          },
        ),
      );
      if (ok == true) _load();
      return;
    }

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => Directionality(
        textDirection: ui.TextDirection.rtl,
        child: StatefulBuilder(
          builder: (context, setState) => AlertDialog(
            title:  Text(tr('إضافة عطلة')),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameCtrl,
                    decoration:
                         InputDecoration(labelText: tr('اسم العطلة')),
                  ),
                  const SizedBox(height: 12),
                  SegmentedButton<bool>(
                    segments:  [
                      ButtonSegment(
                          value: true, label: Text(tr('يومٌ أسبوعيٌّ متكرّر'))),
                      ButtonSegment(
                          value: false, label: Text(tr('تاريخٌ محدَّد'))),
                    ],
                    selected: {isWeekday},
                    onSelectionChanged: (s) =>
                        setState(() => isWeekday = s.first),
                  ),
                  const SizedBox(height: 12),
                  if (isWeekday)
                    DropdownButtonFormField<int>(
                      initialValue: weekday,
                      decoration:
                           InputDecoration(labelText: tr('يوم الأسبوع')),
                      items: [
                        for (var d = 1; d <= 7; d++)
                          DropdownMenuItem(
                            value: d,
                            child: Text(_kWeekdayNames[d]),
                          ),
                      ],
                      onChanged: (v) => setState(() => weekday = v!),
                    )
                  else
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: OutlinedButton.icon(
                        icon: const Icon(PhosphorIconsBold.calendar),
                        label:
                            Text(DateFormat('yyyy/MM/dd', uiLocaleCode).format(date)),
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: date,
                            firstDate: DateTime(2000),
                            lastDate: DateTime(2100),
                          );
                          if (picked != null) setState(() => date = picked);
                        },
                      ),
                    ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int?>(
                    initialValue: branchId,
                    decoration:  InputDecoration(labelText: tr('الفرع')),
                    items: [
                       DropdownMenuItem<int?>(
                        value: null,
                        child: Text(tr('كل الفروع')),
                      ),
                      ...visibleBranches.map(
                        (b) => DropdownMenuItem<int?>(
                          value: b.id,
                          child: Text(b.name),
                        ),
                      ),
                    ],
                    onChanged: (v) => setState(() => branchId = v),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogCtx, false),
                child:  Text(tr('إلغاء')),
              ),
              ElevatedButton(
                onPressed: () async {
                  if (nameCtrl.text.trim().isEmpty) return;
                  try {
                    final repo = ref.read(hrRepositoryProvider);
                    await repo.addWorkHoliday(
                      name: nameCtrl.text,
                      weekday: isWeekday ? weekday : null,
                      date: isWeekday ? null : date,
                      branchId: branchId,
                    );
                    if (dialogCtx.mounted) Navigator.pop(dialogCtx, true);
                  } catch (e) {
                    // ArgumentError من `addWorkHoliday` (شكلٌ غيرُ صالح،
                    // يومُ أسبوعٍ خارج المدى، اسمٌ فارغ) — يُعرَض لا يُبتلَع.
                    if (dialogCtx.mounted) {
                      AppToast.show(dialogCtx, '$e', type: ToastType.error);
                    }
                  }
                },
                child:  Text(tr('حفظ')),
              ),
            ],
          ),
        ),
      ),
    );

    if (saved == true) _load();
  }

  String _describe(WorkHoliday h) {
    if (h.weekday != null) return _kWeekdayNames[h.weekday!];
    return DateFormat('yyyy/MM/dd', uiLocaleCode).format(h.date!);
  }

  /// ترشيحٌ بالاسم أو الوصف (‏اليوم/التاريخ) أو اسمِ الفرع. استعلامٌ فارغٌ
  /// يُرجع القائمةَ بالمرجع نفسِه، فقشرةُ UralCash تبني عينَ ما كانت تبنيه.
  List<WorkHoliday> _filter(Map<int, String> branchNames) {
    final q = widget.searchQuery.trim();
    if (q.isEmpty) return _holidays;
    return _holidays.where((h) {
      final branchLabel = h.branchId == null
          ? tr('كل الفروع')
          : (branchNames[h.branchId] ?? tr('فرعٌ محذوف'));
      return h.name.contains(q) ||
          _describe(h).contains(q) ||
          branchLabel.contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final allBranches = ref.watch(allBranchesProvider).value ?? const [];
    final branchNames = {for (final b in allBranches) b.id: b.name};
    final shown = _filter(branchNames);

    return _loading
            ? const Center(child: CircularProgressIndicator())
            : _holidays.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(PhosphorIconsLight.calendarX,
                            size: 80, color: Colors.grey.shade400),
                        const SizedBox(height: 16),
                        Text(
                          tr('لا توجد عطلاتٌ معرَّفة بعد'),
                          style: TextStyle(
                              fontSize: 18, color: Colors.grey.shade600),
                        ),
                        const SizedBox(height: 8),
                        ElevatedButton.icon(
                          icon: const Icon(PhosphorIconsBold.plus),
                          label:  Text(tr('إضافة عطلة')),
                          onPressed: _showAddDialog,
                        ),
                      ],
                    ),
                  )
                : shown.isEmpty
                ? Center(
                    child: Text(
                      tr('لا توجد عطلةٌ تطابق «{p0}»', {'p0': widget.searchQuery.trim()}),
                      style: TextStyle(
                          fontSize: 14, color: Colors.grey.shade600),
                    ),
                  )
                : Padding(
                    padding: const EdgeInsets.all(24),
                    child: Card(
                      child: ListView.separated(
                        itemCount: shown.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final holiday = shown[index];
                          final branchLabel = holiday.branchId == null
                              ? tr('كل الفروع')
                              : (branchNames[holiday.branchId] ?? tr('فرعٌ محذوف'));
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor:
                                  AppColors.primary.withValues(alpha: 0.1),
                              child: Icon(
                                holiday.weekday != null
                                    ? PhosphorIconsBold.repeat
                                    : PhosphorIconsBold.calendarCheck,
                                color: AppColors.primary,
                                size: 18,
                              ),
                            ),
                            title: Text(
                              holiday.name,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w600),
                            ),
                            subtitle: Text(
                              '${_describe(holiday)} · $branchLabel',
                              style: TextStyle(color: Colors.grey.shade600),
                            ),
                            trailing: IconButton(
                              icon: const Icon(PhosphorIconsLight.trash,
                                  color: AppColors.error),
                              tooltip: tr('حذف'),
                              onPressed: () => _delete(holiday),
                            ),
                          );
                        },
                      ),
                    ),
                  );
  }
}
