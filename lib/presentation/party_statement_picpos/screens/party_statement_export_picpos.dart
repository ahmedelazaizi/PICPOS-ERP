part of 'party_statement_picpos_screen.dart';

// ═══════════════════════════════════════════════════════════════════════════
// تصديرُ الكشف وطباعتُه — الفعلان الوحيدان في هذه الجولة
// ═══════════════════════════════════════════════════════════════════════════
//
// منقولان عن `party_statement_dialogs.dart` في شاشة UralCash: نفسُ مولِّدِ
// الـPDF ونفسُ بنيةِ ملفّ Excel، فالمخرَجُ الورقيُّ واحدٌ لا يتفرّع.
//
// ⚠️ **نسخةٌ مستقلّةٌ لا تفريع** (أمرُ المالك): الشاشةُ الأصليّةُ لا تُمسّ،
// والتعديلُ هنا لا يصل إليها.
//
// ⚠️ **والكشفُ يُعاد استعلامُه عند التصدير** لا يُقرأ من حالة التبويبة:
// التصديرُ متاحٌ وأيُّ تبويبةٍ مفتوحة، وقراءةُ ما حمَّلته «الحركةُ والرصيد»
// كانت ستُخرج ملفّاً فارغاً لمن صدَّر وهو على «الأوراق». والاستعلامُ نفسُه
// هو مصدرُ الحقيقة في الحالتين.

mixin _StatementExportMixin on ConsumerState<PartyStatementPicposScreen> {
  // يوفّرها هيكلُ الشاشة
  bool get isSupplier;
  int? get partyId;
  Party? get party;
  DateTimeRange get range;
  DateFormat get df;
  int? get branchId;

  String get _partyLabel => party?.name ?? widget.partyName;

  Future<List<PartyStatementEntry>> _fetchEntries() async {
    final pid = partyId;
    if (pid == null) return const [];
    return ref.read(partiesRepositoryProvider).getPartyStatement(
          pid,
          fromDate: range.start,
          toDate: range.end,
          // 🔴 **والفرعُ يُمرَّر هنا أيضاً.** بدونه يَخرج الكشفُ المطبوعُ
          //    والمصدَّرُ من **كلّ** الفروع بينما الشاشةُ تعرض واحداً — ورقةٌ
          //    وشاشةٌ برقمَين مختلفَين لنفس السؤال، والورقةُ هي ما يُوقَّع.
          branchId: branchId,
        );
  }

  Future<void> printStatement() async {
    try {
      final entries = await _fetchEntries();
      if (entries.isEmpty) {
        if (mounted) {
          AppToast.show(context, tr('لا حركات في هذه الفترة للطباعة'),
              type: ToastType.warning);
        }
        return;
      }

      final items = entries
          .map((e) => StatementItem(
                date: e.date,
                description: e.description,
                // رقمُ المستند في عموده الخاصّ لا مدموجاً في البيان — الدمجُ
                // كان يمدّد أعرضَ عمودٍ ويزاحم أعمدةَ المبالغ.
                documentNumber: e.invoiceNumber,
                debit: e.debit,
                credit: e.credit,
                balance: e.balance,
              ))
          .toList();

      // بياناتُ الشركة المسجَّلةُ لرأس المستند وتذييله — بدونها يُطبع الكشفُ
      // باسمٍ افتراضيٍّ عامٍّ وبلا هاتفٍ ولا عنوان.
      final settingsRepo = ref.read(settingsRepositoryProvider);
      final company = DocumentCompanyHeader(
        name: await settingsRepo.getSetting('company_name') ?? '',
        phone: await settingsRepo.getSetting('company_phone'),
        phone2: await settingsRepo.getSetting('company_phone2'),
        address: await settingsRepo.getSetting('company_address'),
        taxId: await settingsRepo.getSetting('company_tax_id'),
      );

      await InvoiceGenerator.printPartyStatement(
        partyName: _partyLabel,
        partyType: isSupplier ? 'supplier' : 'customer',
        partyCode: party?.code,
        currentBalance: party?.balance ?? 0,
        transactions: items,
        fromDate: range.start,
        toDate: range.end,
        company: company,
        // ⚠️ **بها وحدَها يمرّ الكشفُ على منظومة القوالب** — وبدونها يبقى
        //    المولّدُ الثابتُ كما كان. وشاشةُ UralCash **لا تُمسّ** (أمرُ
        //    المالك: نسخةٌ مستقلّةٌ لا تفريع)، فتبقى على المولّد القديم.
        db: ref.read(databaseProvider),
      );
    } catch (e) {
      unawaited(DiagnosticLogger.log(
        'PARTY-STATEMENT-PICPOS',
        '❌ تعذّرت الطباعة: $e',
      ));
      if (mounted) {
        AppToast.show(context, tr('خطأ في الطباعة: {e}', {'e': e}), type: ToastType.error);
      }
    }
  }

  Future<void> exportToExcel() async {
    try {
      final entries = await _fetchEntries();
      if (entries.isEmpty) {
        if (mounted) {
          AppToast.show(context, tr('لا حركات في هذه الفترة للتصدير'),
              type: ToastType.warning);
        }
        return;
      }

      final excel = Excel.createExcel();
      final sheetName = tr('كشف حساب');
      excel.rename('Sheet1', sheetName);
      final sheet = excel[sheetName];

      sheet.appendRow([TextCellValue(tr('كشف حساب: {_partyLabel}', {'_partyLabel': _partyLabel}))]);
      sheet.appendRow([TextCellValue(isSupplier ? tr('مورد') : tr('عميل'))]);
      sheet.appendRow([
        TextCellValue(
          tr('الفترة: {p0} - {p1}', {'p0': df.format(range.start), 'p1': df.format(range.end)}),
        )
      ]);
      sheet.appendRow([
        TextCellValue(
          tr('الرصيد الحالي: {p0} {p1}', {'p0': (party?.balance ?? 0).toStringAsFixed(AppConstants.decimalPlaces), 'p1': AppConstants.currencySymbolEn}),
        )
      ]);
      sheet.appendRow([TextCellValue('')]);

      sheet.appendRow([
        TextCellValue(tr('التاريخ')),
        TextCellValue(tr('البيان')),
        TextCellValue(tr('رقم المستند')),
        TextCellValue(tr('مدين')),
        TextCellValue(tr('دائن')),
        TextCellValue(tr('الرصيد')),
      ]);

      var debit = 0.0;
      var credit = 0.0;
      for (final e in entries) {
        debit += e.debit;
        credit += e.credit;
        sheet.appendRow([
          TextCellValue(df.format(e.date)),
          TextCellValue(e.description),
          TextCellValue(e.invoiceNumber ?? '-'),
          DoubleCellValue(e.debit),
          DoubleCellValue(e.credit),
          DoubleCellValue(e.balance),
        ]);
      }

      sheet.appendRow([TextCellValue('')]);
      sheet.appendRow([
        TextCellValue(''),
        TextCellValue(tr('الإجمالي')),
        TextCellValue(''),
        DoubleCellValue(debit),
        DoubleCellValue(credit),
        DoubleCellValue(entries.last.balance),
      ]);

      final fileName =
          'PartyStatement_${_partyLabel}_${DateTime.now().millisecondsSinceEpoch}.xlsx';
      final bytes = excel.save();
      if (bytes != null) {
        await fileUtils.saveFile(fileName, Uint8List.fromList(bytes));
        if (mounted) {
          AppToast.show(context, tr('تم تصدير الكشف إلى: {fileName}', {'fileName': fileName}),
              type: ToastType.success);
        }
      }
    } catch (e) {
      unawaited(DiagnosticLogger.log(
        'PARTY-STATEMENT-PICPOS',
        '❌ تعذّر التصدير: $e',
      ));
      if (mounted) {
        AppToast.show(context, tr('خطأ في التصدير: {e}', {'e': e}), type: ToastType.error);
      }
    }
  }
}
