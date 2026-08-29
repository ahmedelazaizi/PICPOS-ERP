// ignore_for_file: avoid_dynamic_calls
// =======================================================================
// COMMERCIAL PAPERS DIALOGS — Phase 7 God File Splitting
// Extracted from commercial_papers_screen.dart (lines 583-1555)
// =======================================================================
part of 'commercial_papers_screen.dart';

/// Extension on _CommercialPapersScreenState for all dialog/action methods.
extension CommercialPapersDialogs on _CommercialPapersScreenState {

  /// Show the create paper dialog
  void showCreateDialog(ICommercialPapersRepository repo, IPartiesRepository partiesRepo, ITreasuryRepository treasuryRepo) async {
    final partiesFuture = partiesRepo.getParties();
    final banksFuture = treasuryRepo.getSafesList().then((list) => list.where((s) => s.safeType == 'bank' && s.isActive).toList());

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: ui.TextDirection.rtl,
        child: CreatePaperDialog(
          direction: _currentDirection == 'portfolio' ? 'received' : _currentDirection,
          partiesFuture: partiesFuture,
          banksFuture: banksFuture,
        ),
      ),
    );

    if (result != null && result['confirmed'] == true && mounted) {
      try {
        // ⚠️ الكتلةُ كانت هنا حرفيّاً — سَكُّ `globalId` مرّةً ثمّ كتابتان
        //    به. واستُخرجت إلى `createCommercialPaper` لمّا صارت شاشةُ
        //    PicPos تُنشئ ورقةً أيضاً: نسختان من مسارٍ ماليٍّ تنحرفان بأوّل
        //    تعديل، وعطبُ Cluster 030 / Bug D كان بالضبط هويّتَين لورقةٍ
        //    واحدة. راجع تعليقَ الدالّة.
        await createCommercialPaper(
          repo: repo,
          direction: _currentDirection,
          form: result,
        );
        _invalidateStreams();
        setState(() {});
        AppToast.show(context, 'تم إنشاء الشيك بنجاح', type: ToastType.success);
      } catch (e) {
        if (mounted) AppToast.show(context, 'خطأ: $e', type: ToastType.error);
      }
    }
  }


  /// Helper: load leaf accounts for COA selector in dialogs
  Future<List<db.Account>> _loadLeafAccounts() async {
    final acctRepo = ref.read(accountingRepositoryProvider);
    final all = await acctRepo.getAllAccounts();
    final parentIds = all.where((a) => a.parentId != null).map((a) => a.parentId!).toSet();
    return all.where((a) => !parentIds.contains(a.id) && !a.isHiddenFromEntries).toList();
  }

  Future<void> changeStatus(
      ICommercialPapersRepository repo, int paperId, String newStatus) async {
    final statusInfo = getStatusInfo(newStatus);
    final accountsFuture = _loadLeafAccounts();

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: ui.TextDirection.rtl,
        child: StatusChangeDialog(
          statusLabel: statusInfo.label,
          accountsFuture: accountsFuture,
        ),
      ),
    );

    if (result == null || result['confirmed'] != true) return;

    final authState = ref.read(authProvider);
    final userId = authState.user?.id ?? 1;
    final notes = result['notes'] as String?;
    final selectedAccount = result['account'] as db.Account?;

    // Build notes with account info (kept for backward-compat — earlier
    // versions surfaced the chosen account in notes because the JE
    // didn't honour the selection at all. v130 now THREADS it into the
    // DAO too so the JE actually posts on that account; the notes line
    // remains as an audit echo so older reports still display it).
    String? finalNotes = notes?.isNotEmpty == true ? notes : null;
    if (selectedAccount != null) {
      final acctInfo = 'حساب: ${selectedAccount.code} - ${selectedAccount.name}';
      finalNotes = finalNotes != null ? '$finalNotes | $acctInfo' : acctInfo;
    }

    try {
      // ── Client mode: sync to server ──
      await ClientWriteInterceptor.updateCommercialPaperStatus(
        paperId, newStatus, changedBy: userId, notes: finalNotes,
        // Feature 048 (v130) — user-chosen contra leg threaded to server
        // so the server-side JE matches the local one's account.
        counterAccountId: selectedAccount?.id,
      );
      await repo.updatePaperStatus(
        paperId,
        newStatus,
        changedBy: userId,
        notes: finalNotes,
        counterAccountId: selectedAccount?.id,
      );
      if (mounted) {
        AppToast.show(
          context,
          'تم تغيير الحالة إلى ${statusInfo.label}',
          type: ToastType.success,
        );
      }
    } catch (e) {
      if (mounted) {
        AppToast.show(context, 'خطأ: $e', type: ToastType.error);
      }
    }
  }

  void showRenewDialog(ICommercialPapersRepository repo, dynamic paper) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: ui.TextDirection.rtl,
        child: RenewPaperDialog(
          paperNumber: paper.paperNumber,
          initialDueDate: paper.dueDate as DateTime,
        ),
      ),
    );

    if (result == null || result['confirmed'] != true) return;

    final authState = ref.read(authProvider);
    try {
      // ── Client mode: sync to server ──
      await ClientWriteInterceptor.renewCommercialPaper(
        paper.id as int, result['newDueDate'] as DateTime,
        changedBy: authState.user?.id ?? 1,
        notes: (result['notes'] as String?)?.isNotEmpty == true ? result['notes'] as String : null,
      );
      await repo.renewPaper(
        paper.id,
        result['newDueDate'] as DateTime,
        changedBy: authState.user?.id ?? 1,
        notes: (result['notes'] as String?)?.isNotEmpty == true ? result['notes'] : null,
      );
      if (mounted) AppToast.show(context, 'تم تجديد الشيك', type: ToastType.success);
    } catch (e) {
      if (mounted) AppToast.show(context, 'خطأ: $e', type: ToastType.error);
    }
  }

  void showPartialCollectionDialog(ICommercialPapersRepository repo, dynamic paper) async {
    final accountsFuture = _loadLeafAccounts();
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: ui.TextDirection.rtl,
        child: PartialCollectionDialog(
          paperNumber: paper.paperNumber,
          totalAmount: paper.amount,
          accountsFuture: accountsFuture,
        ),
      ),
    );

    if (result == null || result['confirmed'] != true) return;

    final amount = result['amount'] as double;
    final notes = result['notes'] as String?;
    final selectedAccount = result['account'] as db.Account?;
    
    final authState = ref.read(authProvider);
    String? finalNotes = notes?.isNotEmpty == true ? notes : null;
    if (selectedAccount != null) {
      final acctInfo = 'حساب: ${selectedAccount.code} - ${selectedAccount.name}';
      finalNotes = finalNotes != null ? '$finalNotes | $acctInfo' : acctInfo;
    }

    try {
      // ── Client mode: sync to server ──
      await ClientWriteInterceptor.partialCollectPaper(
        paper.id as int, amount,
        changedBy: authState.user?.id ?? 1, notes: finalNotes,
      );
      await repo.partialCollection(
        paper.id,
        amount,
        changedBy: authState.user?.id ?? 1,
        notes: finalNotes,
      );
      if (mounted) AppToast.show(context, 'تم التحصيل الجزئي', type: ToastType.success);
    } catch (e) {
      if (mounted) AppToast.show(context, 'خطأ: $e', type: ToastType.error);
    }
  }

  void showEndorseDialog(ICommercialPapersRepository repo, dynamic paper, IPartiesRepository partiesRepo) async {
    final partiesFuture = partiesRepo.getParties();
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: ui.TextDirection.rtl,
        child: EndorsePaperDialog(
          paperNumber: paper.paperNumber,
          amount: paper.amount,
          partiesFuture: partiesFuture,
        ),
      ),
    );

    if (result == null || result['confirmed'] != true) return;

    final authState = ref.read(authProvider);
    try {
      // ── Client mode: sync to server ──
      await ClientWriteInterceptor.endorseCommercialPaper(
        paper.id as int, result['partyId'] as int,
        changedBy: authState.user?.id ?? 1,
      );
      await repo.endorsePaper(
        paper.id,
        result['partyId'] as int,
        changedBy: authState.user?.id ?? 1,
      );
      if (mounted) AppToast.show(context, 'تم تظهير الشيك', type: ToastType.success);
    } catch (e) {
      if (mounted) AppToast.show(context, 'خطأ: $e', type: ToastType.error);
    }
  }

  void showDepositForCollectionDialog(ICommercialPapersRepository repo, dynamic paper, ITreasuryRepository treasuryRepo) async {
    final banksFuture = treasuryRepo.getSafesList().then((list) => list.where((s) => s.safeType == 'bank' && s.isActive).toList());
    final accountsFuture = _loadLeafAccounts();
    
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: ui.TextDirection.rtl,
        child: DepositForCollectionDialog(
          paperNumber: paper.paperNumber,
          amount: paper.amount,
          banksFuture: banksFuture,
          accountsFuture: accountsFuture,
        ),
      ),
    );

    if (result == null || result['confirmed'] != true) return;

    try {
      // ── Client mode: sync to server ──
      await ClientWriteInterceptor.depositPaperForCollection(
        paper.id as int, result['bankId'] as int,
        changedBy: 1,
      );
      await repo.depositForCollection(
        paper.id,
        result['bankId'] as int,
        changedBy: 1,
      );
      if (mounted) AppToast.show(context, 'تم الإيداع برسم التحصيل', type: ToastType.success);
    } catch (e) {
      if (mounted) AppToast.show(context, 'خطأ: $e', type: ToastType.error);
    }
  }

  void showReissueDialog(ICommercialPapersRepository repo, dynamic paper, IPartiesRepository partiesRepo) async {
    final partiesFuture = partiesRepo.getParties();
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: ui.TextDirection.rtl,
        child: ReissuePaperDialog(
          paperNumber: paper.paperNumber,
          amount: paper.amount,
          partiesFuture: partiesFuture,
        ),
      ),
    );

    if (result == null || result['confirmed'] != true) return;

    try {
      // ── Client mode: sync to server ──
      await ClientWriteInterceptor.reissueCommercialPaper(
        paper.id as int, result['partyId'] as int,
        changedBy: 1,
        notes: (result['notes'] as String?)?.isNotEmpty == true ? result['notes'] as String : null,
      );
      await repo.reissuePaper(
        paper.id,
        result['partyId'] as int,
        changedBy: 1,
        notes: (result['notes'] as String?)?.isNotEmpty == true ? result['notes'] : null,
      );
      if (mounted) AppToast.show(context, 'تم إعادة إصدار الشيك', type: ToastType.success);
    } catch (e) {
      if (mounted) AppToast.show(context, 'خطأ: $e', type: ToastType.error);
    }
  }

  void showPaperDetails(ICommercialPapersRepository repo, dynamic paper, IPartiesRepository partiesRepo) async {
    final party = await partiesRepo.getPartyById(paper.partyId);
    final partyName = party?.name;
    if (!mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: ui.TextDirection.rtl,
        child: AlertDialog(
        title: Row(
          children: [
            Icon(getTypeIcon(paper.type), color: AppColors.primary),
            const SizedBox(width: 8),
            Text(
              'شيك #${paper.paperNumber}',
              style: GoogleFonts.cairo(fontWeight: FontWeight.w700),
            ),
          ],
        ),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              detailRow('النوع', getTypeName(paper.type)),
              detailRow('الاتجاه',
                  paper.direction == 'received' ? 'وارد' : 'صادر'),
              detailRow('الطرف', partyName ?? '-'),
              detailRow('المبلغ', paper.amount.toStringAsFixed(AppConstants.decimalPlaces)),
              detailRow('الحالة', getStatusInfo(paper.status).label),
              detailRow('تاريخ الإصدار', _dateFormat.format(paper.issueDate)),
              detailRow('تاريخ الاستحقاق', _dateFormat.format(paper.dueDate)),
              if (paper.bankName != null)
                detailRow('البنك', paper.bankName!),
              if (paper.bankBranch != null)
                detailRow('فرع البنك', paper.bankBranch!),
              if (paper.accountNumber != null)
                detailRow('رقم الحساب', paper.accountNumber!),
              if (paper.notes != null) detailRow('ملاحظات', paper.notes!),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إغلاق'),
          ),
        ],
      ),
      ),
    );
  }

  Widget detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: GoogleFonts.cairo(
                fontSize: 12,
                color: Colors.grey.shade600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.cairo(
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void showHistory(ICommercialPapersRepository repo, int paperId) async {
    final history = await repo.getPaperHistory(paperId);
    if (!mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: ui.TextDirection.rtl,
        child: AlertDialog(
        title: Text('سجل التغييرات', style: GoogleFonts.cairo()),
        content: SizedBox(
          width: 400,
          height: 300,
          child: history.isEmpty
              ? Center(
                  child: Text('لا يوجد سجل',
                      style: GoogleFonts.cairo(color: Colors.grey)))
              : ListView.separated(
                  itemCount: history.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (ctx, i) {
                    final h = history[i];
                    return ListTile(
                      dense: true,
                      leading: Icon(
                        PhosphorIconsBold.arrowRight,
                        size: 16,
                        color: getStatusInfo(h.toStatus).color,
                      ),
                      title: Text(
                        '${getStatusInfo(h.fromStatus).label} → ${getStatusInfo(h.toStatus).label}',
                        style: GoogleFonts.cairo(fontSize: 12),
                      ),
                      subtitle: Text(
                        _dateFormat.format(h.changedAt),
                        style: GoogleFonts.cairo(fontSize: 10),
                      ),
                      trailing: h.notes != null
                          ? Tooltip(
                              message: h.notes!,
                              child: const Icon(PhosphorIconsBold.noteBlank,
                                  size: 14),
                            )
                          : null,
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إغلاق'),
          ),
        ],
      ),
      ),
    );
  }

  void showSummary(ICommercialPapersRepository repo) async {
    final summary = await repo.getPapersSummary();
    if (!mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: ui.TextDirection.rtl,
        child: AlertDialog(
        title: Text('ملخص الأوراق التجارية',
            style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              summarySection('واردة', summary['received'] ?? {}),
              const Divider(),
              summarySection('صادرة', summary['issued'] ?? {}),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إغلاق'),
          ),
        ],
      ),
      ),
    );
  }

  Widget summarySection(String title, Map<String, dynamic> data) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: GoogleFonts.cairo(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppColors.primary)),
        const SizedBox(height: 4),
        ...data.entries.map((e) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    getStatusInfo(e.key).label,
                    style: GoogleFonts.cairo(fontSize: 12),
                  ),
                  Text(
                    (e.value as num?)?.toStringAsFixed(AppConstants.decimalPlaces) ?? '0.00',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            )),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // HELPER METHODS — moved from parent for extension access
  // ═══════════════════════════════════════════════════════════════════════════

  IconData getTypeIcon(String type) {
    switch (type) {
      case 'cheque':
        return PhosphorIconsBold.receipt;
      case 'promissory_note':
        return PhosphorIconsBold.fileText;
      case 'bill_of_exchange':
        return PhosphorIconsBold.swap;
      default:
        return PhosphorIconsBold.receipt;
    }
  }

  String getTypeName(String type) {
    switch (type) {
      case 'cheque':
        return 'شيك';
      case 'promissory_note':
        return 'كمبيالة';
      case 'bill_of_exchange':
        return 'سند لأمر';
      default:
        return type;
    }
  }

  StatusInfo getStatusInfo(String status) {
    switch (status) {
      case 'pending':
        return StatusInfo('معلق', Colors.orange);
      case 'in_portfolio':
        return StatusInfo('في الحافظة', Colors.indigo);
      case 'deposited':
        return StatusInfo('مودع', Colors.blue);
      case 'deposited_for_collection':
        return StatusInfo('برسم التحصيل', Colors.cyan);
      case 'cashed':
        return StatusInfo('محصّل', AppColors.success);
      case 'bounced':
        return StatusInfo('مرتد', AppColors.error);
      case 'endorsed':
        return StatusInfo('مظهّر', Colors.purple);
      case 'cancelled':
        return StatusInfo('ملغي', Colors.grey);
      case 'partially_cashed':
        return StatusInfo('محصّل جزئياً', Colors.teal);
      default:
        return StatusInfo(status, Colors.grey);
    }
  }
}

class StatusInfo {
  final String label;
  final Color color;
  StatusInfo(this.label, this.color);
}