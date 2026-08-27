// =======================================================================
// JOURNAL ENTRY CREATE DIALOG — Phase 7 God File Splitting
// Extracted from journal_entries_screen.dart (lines 555-1030)
// =======================================================================
part of 'journal_entries_picpos_screen.dart';

/// Extension on _JournalEntriesPicPosScreenState for entry creation dialogs.
extension _JournalEntryCreateDialog on _JournalEntriesPicPosScreenState {
  // ═══════════════════════════════════════════════════════════════════════════
  // MANUAL JOURNAL ENTRY CREATION
  // ═══════════════════════════════════════════════════════════════════════════

  void showCreateEntryDialog(BuildContext context, {JournalEntryTemplateData? initialTemplate, List<Map<String, dynamic>>? templateLines}) {
    final descCtrl = TextEditingController(text: initialTemplate?.name != null ? 'قيد بناءً على قالب: ${initialTemplate?.name}' : '');
    DateTime entryDate = DateTime.now();
    String entryType = 'daily'; // daily, adjustment, salary
    int? globalCostCenterId; // Global cost center applied to new lines
    final lines = <JournalLineInput>[];

    if (templateLines != null && templateLines.isNotEmpty) {
      for (final l in templateLines) {
        final lineInput = JournalLineInput();
        lineInput.account = Account(
          id: l['account_id'] as int,
          code: l['account_code'] as String,
          name: l['account_name'] as String,
          accountType: '',
          accountNature: 'detail',
          normalBalance: 'debit',
          level: 1,
          balance: 0,
          isSystem: false,
          isActive: true,
          isHiddenFromEntries: false,
          rowVersion: 0,
        );
        lineInput.descCtrl.text = l['description'] as String? ?? '';
        lineInput.debitCtrl.text = (l['debit'] as double) > 0 ? (l['debit'] as double).toString() : '';
        lineInput.creditCtrl.text = (l['credit'] as double) > 0 ? (l['credit'] as double).toString() : '';
        lines.add(lineInput);
      }
    } else {
      lines.addAll([
        JournalLineInput(),
        JournalLineInput(),
      ]);
    }

    bool saving = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Directionality(
        textDirection: ui.TextDirection.rtl,
        child: StatefulBuilder(builder: (ctx, setDialogState) {
          final totalDebit = lines.fold(0.0, (s, l) => s + l.debit);
          final totalCredit = lines.fold(0.0, (s, l) => s + l.credit);
          final isBalanced = (totalDebit - totalCredit).abs() < 0.01 && totalDebit > 0;

          return PicPosDialog(
            icon: PhosphorIconsBold.notebook,
            title: 'إنشاء قيد يدوي',
            subtitle: initialTemplate != null
                ? 'من قالب: ${initialTemplate.name}'
                : 'قيدٌ يدويٌّ متوازنٌ يُرحَّل إلى دفتر الأستاذ',
            width: 760,
            headerChips: [
              PicPosDialogChip(
                icon: isBalanced
                    ? PhosphorIconsBold.checkCircle
                    : PhosphorIconsBold.warning,
                label: isBalanced ? 'متوازن' : 'غير متوازن',
                tint: isBalanced ? AppColors.success : AppColors.error,
              ),
            ],
            // ⚠️ الجسمُ عنصرٌ واحدٌ لا قائمةُ عناصر: `PicPosDialog` يضع ١٣
            //    بكسل بين كلِّ عنصرَين، والمسافاتُ هنا مكتوبةٌ يدويّاً
            //    بـ`SizedBox` فكان الجمعُ بينهما يضاعفها.
            body: [
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                    // Entry Type & Description & Date
                    //
                    // ⚠️ كان الأوّلُ `SizedBox(width: 130)` ثابتاً، فتصل إلى
                    //    قائمتِه قيودٌ عرضُها ٧٤ بكسل ولا تكفي نصَّها وأيقونتَها
                    //    — فيضٌ مقيسٌ بـ٦ بكسل عند العرضَين ١٢٨٠ و١٩٢٠ معاً،
                    //    لأنّ عرضَ الحوار مثبَّتٌ فلا يتغيّر بالشاشة.
                    //    و`PicPosDialogRow` يعطيه حصّةً لا رقماً، ويكسر الصفَّ
                    //    رأسيّاً تحت ٥٢٠ بدل أن يسحقه.
                    PicPosDialogRow(
                      flex: const [2, 4, 3],
                      children: [
                        DropdownButtonFormField<String>(
                          initialValue: entryType,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'نوع القيد',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          items: const [
                            DropdownMenuItem(value: 'daily', child: Text('يومية')),
                            DropdownMenuItem(value: 'adjustment', child: Text('تسوية')),
                            DropdownMenuItem(value: 'salary', child: Text('رواتب')),
                          ],
                          onChanged: (v) => setDialogState(() => entryType = v ?? 'daily'),
                        ),
                          TextField(
                            controller: descCtrl,
                            decoration: const InputDecoration(
                              labelText: 'وصف القيد',
                              hintText: 'مثال: قيد تسوية...',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          InkWell(
                            onTap: () async {
                              final date = await CompactDatePicker.showCompact(
                                ctx,
                                initialDate: entryDate,
                                firstDate: DateTime(2020),
                                lastDate: DateTime.now().add(const Duration(days: 30)),
                              );
                              if (date != null) {
                                setDialogState(() => entryDate = date);
                              }
                            },
                            child: InputDecorator(
                              decoration: const InputDecoration(
                                labelText: 'التاريخ',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(PhosphorIconsBold.calendar, size: 16),
                              ),
                              child: Text(
                                _dateFormat.format(entryDate),
                                style: GoogleFonts.cairo(fontSize: 13),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Lines header with global cost center
                    Row(
                      children: [
                        Text('بنود القيد', style: GoogleFonts.cairo(fontWeight: FontWeight.w700, fontSize: 14)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: CostCenterPicker(
                            repo: ref.read(accountingRepositoryProvider),
                            selectedId: globalCostCenterId,
                            labelOverride: 'الفرع / مركز التكلفة',
                            onChanged: (id) {
                              setDialogState(() {
                                globalCostCenterId = id;
                                for (final line in lines) {
                                  line.costCenterId = id;
                                }
                              });
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        TextButton.icon(
                          onPressed: () => setDialogState(() {
                            final newLine = JournalLineInput();
                            newLine.costCenterId = globalCostCenterId;
                            lines.add(newLine);
                          }),
                          icon: const Icon(PhosphorIconsBold.plus, size: 14),
                          label: const Text('إضافة بند'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // Lines list
                    ...lines.asMap().entries.map((entry) {
                      final i = entry.key;
                      final line = entry.value;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: context.picposField,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.border.withValues(alpha: 0.5)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: AppColors.primary.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    'بند ${i + 1}',
                                    style: GoogleFonts.cairo(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.primary),
                                  ),
                                ),
                                const Spacer(),
                                if (lines.length > 2)
                                  IconButton(
                                    icon: const Icon(PhosphorIconsBold.trash, size: 14, color: AppColors.error),
                                    onPressed: () => setDialogState(() => lines.removeAt(i)),
                                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                    padding: EdgeInsets.zero,
                                  ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            AccountAutocompleteField(
                              repo: ref.read(accountingRepositoryProvider),
                              selectedAccount: line.account,
                              onSelected: (account) {
                                setDialogState(() => line.account = account);
                              },
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Expanded(
                                  flex: 3,
                                  child: TextField(
                                    controller: line.descCtrl,
                                    decoration: InputDecoration(
                                      hintText: 'البيان',
                                      isDense: true,
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                    ),
                                    style: GoogleFonts.cairo(fontSize: 11),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  flex: 2,
                                  child: CostCenterPicker(
                                    repo: ref.read(accountingRepositoryProvider),
                                    selectedId: line.costCenterId,
                                    onChanged: (id) {
                                      setDialogState(() => line.costCenterId = id);
                                    },
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: line.debitCtrl,
                                    keyboardType: TextInputType.number,
                                    onChanged: (_) => setDialogState(() {}),
                                    decoration: InputDecoration(
                                      labelText: 'مدين',
                                      labelStyle: GoogleFonts.cairo(fontSize: 11),
                                      hintText: '0.00',
                                      isDense: true,
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                    ),
                                    style: GoogleFonts.jetBrainsMono(fontSize: 11),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: TextField(
                                    controller: line.creditCtrl,
                                    keyboardType: TextInputType.number,
                                    onChanged: (_) => setDialogState(() {}),
                                    decoration: InputDecoration(
                                      labelText: 'دائن',
                                      labelStyle: GoogleFonts.cairo(fontSize: 11),
                                      hintText: '0.00',
                                      isDense: true,
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                    ),
                                    style: GoogleFonts.jetBrainsMono(fontSize: 11),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    }),

                    // Balance indicator
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: isBalanced
                            ? AppColors.success.withValues(alpha: 0.08)
                            : AppColors.error.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isBalanced
                              ? AppColors.success.withValues(alpha: 0.3)
                              : AppColors.error.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            isBalanced ? PhosphorIconsBold.checkCircle : PhosphorIconsBold.warning,
                            size: 18,
                            color: isBalanced ? AppColors.success : AppColors.error,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'مجموع المدين: ${totalDebit.toStringAsFixed(2)}',
                            style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(width: 16),
                          Text(
                            'مجموع الدائن: ${totalCredit.toStringAsFixed(2)}',
                            style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.w600),
                          ),
                          const Spacer(),
                          Text(
                            isBalanced ? 'متوازن ✓' : 'غير متوازن!',
                            style: GoogleFonts.cairo(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: isBalanced ? AppColors.success : AppColors.error,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
            ],
            onCancel: () async {
                  // U-03: Unsaved changes guard
                  final hasData = descCtrl.text.isNotEmpty ||
                      lines.any((l) => l.account != null || l.debit > 0 || l.credit > 0 || l.descCtrl.text.isNotEmpty);
                  if (hasData) {
                    // ⚠️ `showPicPosConfirm` يُرجع `bool` غيرَ لاغٍ افتراضُه
                    //    **الرفض**، فالإغلاقُ العرَضيُّ يُبقي القيدَ لا
                    //    يبتلعه — وهو ما كان `leave != true` يضمنه هنا.
                    final leave = await showPicPosConfirm(
                      ctx,
                      icon: PhosphorIconsBold.warning,
                      title: 'تنبيه',
                      message:
                          'يوجد بيانات غير محفوظة في القيد. هل أنت متأكد من الإلغاء؟',
                      confirmLabel: 'نعم، إلغاء',
                      cancelLabel: 'لا، البقاء',
                      danger: true,
                    );
                    if (!leave) return;
                  }
                  if (ctx.mounted) Navigator.pop(ctx);
            },
            // ⚠️ الشرطُ كما كان: قيدٌ غيرُ متوازنٍ **لا** يُحفَظ، والدوّارةُ
            //    تحلّ محلَّ الأيقونة بمقاسها فلا يقفز عرضُ الزرّ.
            primaryAction: PicPosDialogAction(
              label: 'حفظ القيد',
              icon: PhosphorIconsBold.floppyDisk,
              busy: saving,
              onPressed: isBalanced && !saving
                  ? () async {
                      setDialogState(() => saving = true);
                      await saveManualEntry(ctx, descCtrl.text, entryDate, lines, entryType);
                      if (ctx.mounted) setDialogState(() => saving = false);
                    }
                  : null,
            ),
          );
        }),
      ),
    );
  }

  void showTemplateSelectionDialog(BuildContext context, IAccountingRepository repo) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PicPosDialog(
        icon: PhosphorIconsBold.copy,
        title: 'اختيار قالب قيد',
        subtitle: 'ابدأ القيدَ من قالبٍ نشطٍ بدل إدخاله من الصفر',
        width: 520,
        // ⚠️ الجسمُ قائمةٌ متمرّرةٌ بارتفاعٍ ثابت. فلو بقي `scrollable` على
        //    افتراضه لصارت تمريرتان متداخلتان في المحور نفسِه — والقائمةُ
        //    محدودةٌ هنا بـ`SizedBox` فلا تنهار، لكنّ التمريرَ يصير مربكاً.
        scrollable: false,
        onCancel: () => Navigator.pop(ctx),
        body: [
          SizedBox(
            height: 300,
            child: StreamBuilder<List<JournalEntryTemplateData>>(
              stream: repo.watchActiveTemplates(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                final templates = snapshot.data!;
                if (templates.isEmpty) {
                  return Center(
                    child: Text('لا توجد قوالب نشطة مسجلة.', style: GoogleFonts.cairo(color: AppColors.textMuted)),
                  );
                }
                return ListView.separated(
                  itemCount: templates.length,
                  separatorBuilder: (context, index) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final t = templates[index];
                    return ListTile(
                      leading: const Icon(PhosphorIconsBold.notebook, color: AppColors.primary),
                      title: Text(t.name, style: GoogleFonts.cairo(fontWeight: FontWeight.w600)),
                      subtitle: t.description?.isNotEmpty == true ? Text(t.description!, maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.cairo(fontSize: 12)) : null,
                      onTap: () async {
                        Navigator.pop(ctx);
                        final lines = await repo.getTemplateLinesWithAccounts(t.id);
                        if (!context.mounted) return;
                        showCreateEntryDialog(context, initialTemplate: t, templateLines: lines);
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> saveManualEntry(
    BuildContext ctx,
    String description,
    DateTime date,
    List<JournalLineInput> lines,
    String referenceType,
  ) async {
    if (description.isEmpty) {
      AppToast.show(context, 'يرجى إدخال وصف القيد', type: ToastType.info);
      return;
    }

    for (final line in lines) {
      if (line.account == null) {
        AppToast.show(context, 'يرجى اختيار حساب لكل بند', type: ToastType.info);
        return;
      }
      if (line.debit <= 0 && line.credit <= 0) {
        AppToast.show(context, 'كل بند يجب أن يحتوي على قيمة مدين أو دائن', type: ToastType.info);
        return;
      }
      // BUG-U13: a line may carry a debit OR a credit, never both.
      if (line.debit > 0 && line.credit > 0) {
        AppToast.show(context, 'لا يمكن إدخال مدين ودائن معاً في نفس البند',
            type: ToastType.info);
        return;
      }
    }

    // MJE-3 (batch B13 / S-EXP-REST): local per-user permission gate. The
    // manual-JE path used to be ungated locally — this was the ONLY check
    // standing between a logged-in user and posting arbitrary GL entries.
    // Checked BEFORE createJournalEntry so a denied user never reaches the
    // shared DAO call (which stays unaware of the caller/permission —
    // autopost also calls it with no user).
    if (!await _requireAccountingJournalPermission()) return;

    try {
      final repo = ref.read(accountingRepositoryProvider);
      final journalLines = lines
          .map((l) => JournalLine(
                accountId: l.account!.id,
                debit: l.debit,
                credit: l.credit,
                description: l.descCtrl.text.isNotEmpty ? l.descCtrl.text : null,
                costCenterId: l.costCenterId,
              ))
          .toList();

      await repo.createJournalEntry(
        description: description,
        date: date,
        lines: journalLines,
        referenceType: referenceType,
        isAutoPosted: false,
      );

      if (ctx.mounted) Navigator.pop(ctx);
      if (mounted) {
        AppToast.show(context, 'تم حفظ القيد بنجاح');
      }
    } catch (e) {
      if (mounted) {
        AppToast.show(context, 'خطأ: $e', type: ToastType.error);
      }
    }
  }
}
